import 'dart:async';

import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/server.dart';

import 'lsp_test_harness.dart';

/// Result returned from [LspClient.initialize].
final class InitializeResult {
  final Map<String, Object?> capabilities;
  final Map<String, Object?>? serverInfo;

  InitializeResult({required this.capabilities, this.serverInfo});
}

final class Document {
  final String uri;
  final String text;

  const Document({required this.uri, required this.text});

  Document.withText(this.text) : uri = 'file:///tmp/anydoc.cls';
}

/// High-level LSP client for integration tests.
///
/// Wraps the low-level [InMemoryByteSink], [InMemoryLspInput], and [Server]
/// to provide a clean, human-readable API that hides JSON-RPC protocol
/// details like framing, request IDs, and polling.
final class LspClient {
  final InMemoryByteSink sink;
  final InMemoryLspInput input;
  final Server server;

  int _nextId = 1;
  Future<void>? _serverTask;

  LspClient({required this.sink, required this.input, required this.server});

  /// Starts the server loop in the background.
  void start() {
    _serverTask = server.run();
  }

  /// Sends an `initialize` request and `initialized` notification.
  ///
  /// When [waitForIndexing] is true, waits for the `$/progress` end
  /// notification before returning — proving that indexing completed.
  Future<InitializeResult> initialize({
    required Uri workspaceUri,
    bool waitForIndexing = true,
  }) async {
    final id = _nextId++;
    input.addFrame(
      jsonRpcInitialize(
        id: id,
        workspaceFolders: [
          {'uri': workspaceUri.toString(), 'name': 'workspace'},
        ],
      ),
    );

    final response = await _waitForResponse(id: id);
    final result = response['result'] as Map<String, Object?>;

    input.addFrame(jsonRpcNotification(method: 'initialized'));

    if (waitForIndexing) {
      await _waitForNotification(
        method: r'$/progress',
        predicate: (params) =>
            (params['value'] as Map<String, Object?>)['kind'] == 'end',
        timeout: const Duration(seconds: 10),
      );
    }

    return InitializeResult(
      capabilities: result['capabilities'] as Map<String, Object?>,
      serverInfo: result['serverInfo'] as Map<String, Object?>?,
    );
  }

  /// Sends a `textDocument/didOpen` notification.
  Future<void> openDocument(Document document) async {
    input.addFrame(
      jsonRpcNotification(
        method: 'textDocument/didOpen',
        params: {
          'textDocument': {'uri': document.uri, 'text': document.text},
        },
      ),
    );
    // Allow the server to process the notification.
    await _pumpEventLoop();
  }

  /// Sends a `textDocument/didChange` notification (full sync).
  Future<void> changeDocument(Document document) async {
    input.addFrame(
      jsonRpcNotification(
        method: 'textDocument/didChange',
        params: {
          'textDocument': {'uri': document.uri},
          'contentChanges': [
            {'text': document.text},
          ],
        },
      ),
    );
    await _pumpEventLoop();
  }

  /// Sends a `textDocument/didClose` notification.
  Future<void> closeDocument({required String uri}) async {
    input.addFrame(
      jsonRpcNotification(
        method: 'textDocument/didClose',
        params: {
          'textDocument': {'uri': uri},
        },
      ),
    );
    await _pumpEventLoop();
  }

  /// Sends a `textDocument/completion` request and returns the parsed result.
  Future<CompletionList> completion({
    required String uri,
    required int line,
    required int character,
  }) async {
    final id = _nextId++;
    input.addFrame(
      jsonRpcRequest(
        id: id,
        method: 'textDocument/completion',
        params: {
          'textDocument': {'uri': uri},
          'position': {'line': line, 'character': character},
        },
      ),
    );

    final response = await _waitForResponse(id: id);
    final result = response['result'] as Map<String, Object?>;
    return _parseCompletionList(result);
  }

  /// Sends an arbitrary JSON-RPC request and returns the full response map.
  ///
  /// Useful for testing error cases where the response includes an `error`
  /// field rather than a `result`.
  Future<Map<String, Object?>> sendRawRequest({
    required String method,
    Object? params,
  }) async {
    final id = _nextId++;
    input.addFrame(jsonRpcRequest(id: id, method: method, params: params));
    return _waitForResponse(id: id);
  }

  /// Sends `shutdown` + `exit` and awaits the server task.
  Future<void> shutdown() async {
    final id = _nextId++;
    input.addFrame(jsonRpcRequest(id: id, method: 'shutdown'));
    await _waitForResponse(id: id);

    input.addFrame(jsonRpcNotification(method: 'exit'));

    if (_serverTask != null) {
      try {
        await _serverTask!.timeout(const Duration(seconds: 2));
      } catch (_) {
        // The server throws an _ExitCalled exception on exit.
      }
    }
  }

  /// Waits for any response from the server (useful for error responses
  /// where the request ID may be null or unknown at the call site).
  Future<Map<String, Object?>> waitForAnyResponse({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _pollFrames(
      timeout: timeout,
      predicate: (frame) =>
          frame.containsKey('id') &&
          (frame.containsKey('result') || frame.containsKey('error')),
      timeoutMessage: 'Timed out waiting for any response',
    );
  }

  /// Safe to call in `tearDown` even if the server already exited.
  Future<void> dispose() async {
    try {
      await input.close();
    } catch (_) {}
    if (_serverTask != null) {
      try {
        await _serverTask!.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Internal polling helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> _pollFrames({
    required Duration timeout,
    required bool Function(Map<String, Object?> frame) predicate,
    String? timeoutMessage,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final frames = sink.takeFrames();

      for (final frame in frames) {
        if (frame is Map) {
          final casted = frame.cast<String, Object?>();
          if (predicate(casted)) return casted;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    throw StateError(timeoutMessage ?? 'Timed out waiting for expected frame');
  }

  Future<Map<String, Object?>> _waitForResponse({
    required Object id,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _pollFrames(
      timeout: timeout,
      predicate: (frame) => frame['id'] == id,
      timeoutMessage: 'Timed out waiting for response id=$id',
    );
  }

  Future<Map<String, Object?>> _waitForNotification({
    required String method,
    required bool Function(Map<String, Object?> params) predicate,
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _pollFrames(
      timeout: timeout,
      predicate: (frame) {
        if (frame['method'] != method) return false;
        final params = frame['params'];
        return params is Map && predicate(params.cast<String, Object?>());
      },
      timeoutMessage: 'Timed out waiting for notification $method',
    );
  }

  Future<void> _pumpEventLoop() =>
      Future<void>.delayed(const Duration(milliseconds: 25));

  CompletionList _parseCompletionList(Map<String, Object?> json) {
    final isIncomplete = json['isIncomplete'] as bool;
    final rawItems = json['items'] as List<Object?>;
    final items = rawItems.map((raw) {
      final map = raw as Map<String, Object?>;
      final kindValue = map['kind'] as int?;
      final labelDetails = map['labelDetails'] as Map<String, Object?>?;
      return CompletionItem(
        label: map['label'] as String,
        insertText: map['insertText'] as String?,
        kind: kindValue != null
            ? CompletionItemKind.values.firstWhere((k) => k.value == kindValue)
            : null,
        detail: map['detail'] as String?,
        labelDetails: labelDetails != null
            ? CompletionItemLabelDetails(
                detail: labelDetails['detail'] as String?,
                description: labelDetails['description'] as String?,
              )
            : null,
      );
    }).toList();
    return CompletionList(isIncomplete: isIncomplete, items: items);
  }
}
