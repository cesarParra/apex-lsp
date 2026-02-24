import 'dart:async';
import 'dart:io';

import 'package:apex_lsp/cancellation_tracker.dart';
import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/gitignore.dart';
import 'package:apex_lsp/hover/hover_formatter.dart';
import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/initialization_status.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_lsp/utils/text_utils.dart';
import 'package:file/file.dart';

import 'lsp_out.dart';
import 'message.dart';
import 'message_reader.dart';

/// Function signature for exiting the server process.
///
/// Takes an exit code where 0 indicates clean shutdown and non-zero
/// indicates an error condition.
typedef ExitFn = Never Function(int exitCode);

/// Language Server Protocol implementation for Apex code intelligence.
///
/// This server provides completion suggestions for Apex files in Salesforce
/// projects by maintaining an index of workspace types and analyzing open
/// documents. It follows the LSP lifecycle: initialize → initialized →
/// requests/notifications → shutdown → exit.
///
/// **Key responsibilities:**
/// - Handling LSP protocol messages (requests and notifications)
/// - Managing workspace indexing of Apex classes, enums, and interfaces
/// - Providing completion suggestions based on cursor position
/// - Tracking open documents and their content changes
///
/// Example usage:
/// ```dart
/// final server = Server(
///   output: LspOut(output: StdoutByteSink(stdout)),
///   reader: MessageReader(stdin),
///   exitFn: exit,
///   openDocuments: OpenDocuments(),
///   localIndexer: LocalIndexer(bindings: treeSitterBindings),
///   workspaceIndexer: Indexer(sfdxWorkspaceLocator: locator, fileSystem: fs, platform: platform),
/// );
/// await server.run();
/// ```
///
/// See also:
///  * [MessageReader], which parses incoming LSP messages.
///  * [LspOut], which sends outgoing LSP responses.
///  * [WorkspaceIndexer], which indexes workspace Apex files.
final class Server {
  Server({
    required LspOut output,
    required MessageReader reader,
    required ExitFn exitFn,
    required OpenDocuments openDocuments,
    required LocalIndexer localIndexer,
    required WorkspaceIndexer workspaceIndexer,
    required CancellationTracker cancellationTracker,
    required FileSystem fileSystem,
    required LspPlatform platform,
  }) : _output = output,
       _reader = reader,
       _exitFn = exitFn,
       _openDocuments = openDocuments,
       _localIndexer = localIndexer,
       _workspaceIndexer = workspaceIndexer,
       _cancellationTracker = cancellationTracker,
       _fileSystem = fileSystem,
       _platform = platform;

  final LspOut _output;
  final MessageReader _reader;
  final ExitFn _exitFn;

  final OpenDocuments _openDocuments;
  final LocalIndexer _localIndexer;
  final WorkspaceIndexer _workspaceIndexer;
  final CancellationTracker _cancellationTracker;
  final FileSystem _fileSystem;
  final LspPlatform _platform;
  IndexRepository? _indexRepository;

  InitializationStatus _initializationStatus = NotInitialized();
  bool _shutdownRequested = false;
  bool _exiting = false;

  /// Sends a log message to the LSP client.
  ///
  /// Messages are only sent after the server has been initialized. Log messages
  /// appear in the client's output panel but do not interrupt the user.
  ///
  /// - [type]: The severity level of the message.
  /// - [message]: The message content to log.
  ///
  /// Example:
  /// ```dart
  /// await server.logMessage(MessageType.info, 'Indexing complete');
  /// ```
  Future<void> logMessage(MessageType type, String message) async {
    switch (_initializationStatus) {
      case Initialized():
        await _output.logMessage(type, message);
      case NotInitialized():
    }
  }

  /// Starts the main server loop.
  ///
  /// Continuously reads and processes LSP messages from the [_reader] until
  /// an exit notification is received or the input stream closes. Each message
  /// is routed to the appropriate handler based on its type.
  ///
  /// This method blocks until the server exits.
  ///
  /// Example:
  /// ```dart
  /// final server = Server(...);
  /// await server.run(); // Blocks until exit
  /// ```
  Future<void> run() async {
    await for (final result in _reader.messages()) {
      if (_exiting) break;

      switch (result) {
        case ParseErrorResult(:final requestId, :final errorMessage):
          // Send JSON-RPC ParseError response per spec.
          await _output.sendError(
            id: requestId,
            code: JsonRpcErrorCode.parseError.code,
            message: 'Parse error',
            data: errorMessage,
          );
        case ParsedMessage(:final message):
          switch (message) {
            case RequestMessage():
              await _handleRequest(message);
            case IncomingNotificationMessage():
              await _handleNotification(message);
            case ClientResponse():
              await _handleClientResponse(message);
          }
      }
    }
  }

  /// Handles incoming LSP request messages.
  ///
  /// Routes requests to appropriate handlers based on the request method.
  /// Enforces that the server must be initialized before handling most requests,
  /// except for `initialize` and `shutdown`.
  ///
  /// - [req]: The incoming request message to handle.
  ///
  /// Returns an error response if the server is not initialized and the request
  /// is not `initialize` or `shutdown`.
  Future<void> _handleRequest(RequestMessage req) async {
    // Check if request has been cancelled
    if (_cancellationTracker.isCancelled(req.id)) {
      await _output.sendError(
        id: req.id,
        code: JsonRpcErrorCode.requestCancelled.code,
        message: 'Request cancelled',
      );
      return;
    }

    switch (_initializationStatus) {
      case NotInitialized():
        if (req.method != 'initialize' && req.method != 'shutdown') {
          await _output.sendError(
            id: req.id,
            code: JsonRpcErrorCode.serverNotInitialized.code,
            message: 'Server not initialized',
          );
          return;
        }
      case Initialized():
    }

    switch (req) {
      case InitializeRequest():
        await _onInitialize(req);
      case ShutdownRequest():
        _shutdownRequested = true;
        await _output.sendResponse(id: req.id, result: null);
      case CompletionRequest(:final id, :final params):
        await _onCompletion(
          id: id,
          params: params,
          localIndexer: _localIndexer,
        );
      case HoverRequest(:final id, :final params):
        await _onHover(id: id, params: params, localIndexer: _localIndexer);
      case UnknownRequest(:final id, :final method):
        await _output.sendError(
          id: id,
          code: JsonRpcErrorCode.methodNotFound.code,
          message: "Unknown method '$method'",
        );
    }
  }

  /// Handles incoming LSP notification messages.
  ///
  /// Processes notifications such as document open/change/close events and
  /// triggers workspace indexing after initialization. The `exit` notification
  /// terminates the server process.
  ///
  /// - [note]: The incoming notification message to handle.
  ///
  /// Protocol-lifecycle notifications (`exit`, `$/cancelRequest`) are handled
  /// unconditionally regardless of initialization state, as required by the
  /// LSP specification. All other notifications require the server to be in
  /// the [Initialized] state.
  Future<void> _handleNotification(IncomingNotificationMessage note) async {
    switch (note) {
      case ExitMessage():
        // Spec: exit 0 if shutdown was requested, exit 1 otherwise.
        // Must be handled regardless of initialization state.
        _exiting = true;
        exitCode = _shutdownRequested ? 0 : 1;
        await _output.flush();
        _exitFn(exitCode);

      case CancelRequestNotification(:final params):
        // Must be registered regardless of initialization state so that
        // cancellations sent before the server initialises are not lost.
        _cancellationTracker.cancel(params.id);

      case InitializedMessage():
        if (_initializationStatus case Initialized(:final params)) {
          await logMessage(MessageType.info, 'Apex LSP initialized');

          try {
            await _ensureGitignoreUpdated(params);
          } catch (_) {
            // A failure to update .gitignore should not be catastrophic.
          }

          final token = ProgressToken.string(
            'apex-lsp-indexing-${DateTime.now().millisecondsSinceEpoch}',
          );
          await _output.workDoneProgressCreate(token: token);

          await for (final value in _workspaceIndexer.index(
            params,
            token: token,
          )) {
            _output.progress(params: value);
          }

          _indexRepository = _workspaceIndexer.getIndexLoader(
            log: (message) =>
                logMessage(MessageType.log, '[apex-lsp] $message'),
          );

          final declarations = await _indexRepository!.getDeclarations();
          await logMessage(
            MessageType.log,
            '[apex-lsp] Workspace index loaded: '
            '${declarations.length} types: '
            '${declarations.map((d) => d.name.value).toList()}',
          );
        }

      case TextDocumentDidOpenMessage(:final params):
        if (_initializationStatus is Initialized) {
          _openDocuments.didOpen(params);
        }
      case TextDocumentDidChangeMessage(:final params):
        if (_initializationStatus is Initialized) {
          _openDocuments.didChange(params);
        }
      case TextDocumentDidCloseMessage(:final params):
        if (_initializationStatus is Initialized) {
          _openDocuments.didClose(params);
        }
    }
  }

  /// Handles client responses to server-initiated requests.
  ///
  /// When the server sends a request to the client (like `window/workDoneProgress/create`),
  /// the client responds with either a success or error response. This method logs
  /// the response for debugging purposes.
  ///
  /// - [response]: The client response message.
  Future<void> _handleClientResponse(ClientResponse response) async {
    switch (response) {
      case ClientSuccessResponse(:final id, :final result):
        await logMessage(
          MessageType.log,
          '[apex-lsp] Client response to request $id: success (result=$result)',
        );
      case ClientErrorResponse(:final id, :final error):
        await logMessage(
          MessageType.warning,
          '[apex-lsp] Client response to request $id: error ${error.code} - ${error.message}',
        );
    }
  }

  /// Handles the LSP `initialize` request.
  ///
  /// Transitions the server from [NotInitialized] to [Initialized] state and
  /// sends back the server capabilities including text document sync and
  /// completion support.
  ///
  /// - [req]: The initialize request containing workspace information.
  ///
  /// This must be the first request sent to the server. After responding,
  /// the client will send an `initialized` notification to begin normal operation.
  Future<void> _onInitialize(InitializeRequest req) async {
    _initializationStatus = Initialized(params: req.params);

    // Minimal InitializeResult with full document sync.
    final result = <String, Object?>{
      'capabilities': <String, Object?>{
        'textDocumentSync': 1, // TextDocumentSyncKind.Full
        // Very basic completions using the prebuilt index.
        // We keep it minimal: advertise that we support completion requests.
        'completionProvider': <String, Object?>{
          'triggerCharacters': ['.'],
        },
        'hoverProvider': true,
      },
      // TODO: Get from dynamic JSON or pubspec or something like that
      'serverInfo': <String, Object?>{'name': 'apex-lsp', 'version': '0.0.1'},
    };

    await _output.sendResponse(id: req.id, result: result);
  }

  /// Handles the LSP `textDocument/completion` request.
  ///
  /// Provides completion suggestions at the specified cursor position by
  /// parsing the document with the local indexer and computing candidates
  /// based on the completion context.
  ///
  /// - [id]: The request ID to include in the response.
  /// - [params]: Contains the document URI and cursor position.
  /// - [localIndexer]: Used to parse and index the current document.
  ///
  /// Returns an empty completion list if the document is not open or cannot
  /// be retrieved.
  Future<void> _onCompletion({
    required Object id,
    required CompletionParams params,
    required LocalIndexer localIndexer,
  }) async {
    final text = _openDocuments.get(params.textDocument.uri);
    if (text == null) {
      return;
    }
    final localIndex = localIndexer.parseAndIndex(text);
    final workspaceTypes = await _indexRepository?.getDeclarations() ?? [];

    await logMessage(
      MessageType.log,
      '[apex-lsp] Completion request: '
      'uri=${params.textDocument.uri} '
      'pos=(${params.position.line}:${params.position.character}) '
      'localIndex=${localIndex.length} '
      'workspaceTypes=${workspaceTypes.length}',
    );

    final index = [...localIndex, ...workspaceTypes];
    final completionList = await onCompletion(
      text: text,
      position: params.position,
      index: index,
      sources: [declarationSource(index), keywordSource],
      log: (message) => logMessage(MessageType.log, '[apex-lsp] $message'),
    );
    await _output.sendResponse(id: id, result: completionList.toJson());
  }

  /// Handles the LSP `textDocument/hover` request.
  ///
  /// Resolves the symbol at the cursor position by parsing the document with
  /// the local indexer and searching the combined index, then formats a
  /// markdown hover response. Returns `null` if no symbol is found.
  ///
  /// - [id]: The request ID to include in the response.
  /// - [params]: Contains the document URI and cursor position.
  /// - [localIndexer]: Used to parse and index the current document.
  Future<void> _onHover({
    required Object id,
    required HoverParams params,
    required LocalIndexer localIndexer,
  }) async {
    final text = _openDocuments.get(params.textDocument.uri);
    if (text == null) {
      await _output.sendResponse(id: id, result: null);
      return;
    }

    final localIndex = localIndexer.parseAndIndex(text);
    final workspaceTypes = await _indexRepository?.getDeclarations() ?? [];
    final index = [...localIndex, ...workspaceTypes];

    final cursorOffset = offsetAtPosition(
      text: text,
      line: params.position.line,
      character: params.position.character,
    );

    final resolved = resolveSymbolAt(
      cursorOffset: cursorOffset,
      text: text,
      index: index,
    );

    final result = resolved != null ? formatHover(resolved).toJson() : null;
    await _output.sendResponse(id: id, result: result);
  }

  Future<void> _ensureGitignoreUpdated(InitializedParams params) async {
    final folders = params.workspaceFolders;
    if (folders == null || folders.isEmpty) return;

    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri == null) continue;
      final rootPath = uri.toFilePath(windows: _platform.isWindows);
      final rootDir = _fileSystem.directory(rootPath);
      await ensureSfZedIgnored(rootDir, _fileSystem);
    }
  }
}
