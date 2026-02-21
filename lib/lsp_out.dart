import 'dart:convert';
import 'dart:io';

import 'message.dart';

/// Abstraction for writing LSP message bytes to an output stream.
///
/// This interface allows the LSP server to write messages without depending
/// directly on `Stdout`, enabling testing with in-memory implementations.
///
/// See also:
///  * [StdoutByteSink], the production implementation for stdout.
abstract interface class LspByteSink {
  /// Writes raw bytes to the output stream.
  ///
  /// - [data]: The bytes to write.
  void add(List<int> data);

  /// Flushes any buffered data to the underlying stream.
  Future<void> flush();
}

/// Production implementation of [LspByteSink] that writes to stdout.
///
/// Example:
/// ```dart
/// final sink = StdoutByteSink(stdout);
/// final lspOut = LspOut(output: sink);
/// ```
final class StdoutByteSink implements LspByteSink {
  StdoutByteSink(this._stdout);

  final Stdout _stdout;

  @override
  void add(List<int> data) => _stdout.add(data);

  @override
  Future<void> flush() => _stdout.flush();
}

/// Handles sending LSP protocol messages to the client.
///
/// This class encapsulates LSP message framing and provides typed methods
/// for common LSP notifications and responses. All messages are formatted
/// according to the Language Server Protocol specification with proper
/// Content-Length headers.
///
/// **Key features:**
/// - Sends responses to LSP requests
/// - Sends notifications (log messages, progress updates, etc.)
/// - Handles LSP message framing automatically
/// - Abstracts output stream via [LspByteSink]
///
/// Example:
/// ```dart
/// final output = LspOut(output: StdoutByteSink(stdout));
/// await output.logMessage(MessageType.info, 'Server started');
/// await output.sendResponse(id: 1, result: {'version': '1.0'});
/// ```
///
/// See also:
///  * [LspByteSink], which provides the underlying output stream.
///  * [MessageReader], which handles incoming messages.
class LspOut {
  LspOut({required LspByteSink output}) : _output = output;

  final LspByteSink _output;

  /// Flushes any buffered output to the underlying stream.
  Future<void> flush() => _output.flush();

  /// Writes raw bytes to the output stream.
  ///
  /// This is a low-level method. Prefer using the typed message methods
  /// like [logMessage], [sendResponse], etc.
  void add(List<int> data) => _output.add(data);

  /// Sends a `window/logMessage` notification to the client.
  ///
  /// Log messages appear in the client's output panel and are useful for
  /// debugging and informational purposes. They do not interrupt the user.
  ///
  /// - [type]: The severity level (error, warning, info, or log).
  /// - [message]: The message content to log.
  ///
  /// Example:
  /// ```dart
  /// await output.logMessage(MessageType.info, 'Indexing complete');
  /// await output.logMessage(MessageType.error, 'Failed to parse file');
  /// ```
  Future<void> logMessage(MessageType type, String message) async {
    _writeMessage(LogMessage(MessageParams(type: type, message: message)));
  }

  /// Sends a debug-level log message with an `[apex-lsp]` prefix.
  ///
  /// This is a convenience method for logging debug information.
  ///
  /// - [message]: The debug message to log.
  void debug(String message) {
    logMessage(.log, '[apex-lsp] $message');
  }

  /// Sends a `window/showMessage` notification to display a message to the user.
  ///
  /// Unlike [logMessage], this notification may display a visible popup or
  /// notification to the user, depending on the client implementation.
  ///
  /// - [type]: The severity level of the message.
  /// - [message]: The message content to display.
  ///
  /// Example:
  /// ```dart
  /// await output.showMessage(MessageType.error, 'Index corrupted');
  /// ```
  Future<void> showMessage(MessageType type, String message) async {
    try {
      _writeMessage(ShowMessage(MessageParams(type: type, message: message)));
    } catch (e) {
      await logMessage(.error, 'showMessage failed: $e');
    }
  }

  /// Sends a successful response to an LSP request.
  ///
  /// - [id]: The request ID from the original request message.
  /// - [result]: The result payload. Can be `null` for requests that return nothing.
  ///
  /// Example:
  /// ```dart
  /// await output.sendResponse(
  ///   id: req.id,
  ///   result: {'capabilities': {...}},
  /// );
  /// ```
  Future<void> sendResponse({
    required Object id,
    required Object? result,
  }) async {
    _writeMessage(SuccessResponseMessage(id, result));
  }

  /// Sends an error response to an LSP request.
  ///
  /// - [id]: The request ID from the original request message, or `null` for
  ///   parse errors where the ID cannot be determined.
  /// - [code]: The LSP error code (e.g., -32002 for ServerNotInitialized).
  /// - [message]: Human-readable error message.
  /// - [data]: Optional additional error data.
  ///
  /// Example:
  /// ```dart
  /// await output.sendError(
  ///   id: req.id,
  ///   code: -32002,
  ///   message: 'Server not initialized',
  /// );
  /// ```
  Future<void> sendError({
    required Object? id,
    required int code,
    required String message,
    Object? data,
  }) async {
    final errorObj = ResponseError(code, message, data);
    _writeMessage(ErrorResponseMessage(id, errorObj));
  }

  /// Sends a `window/workDoneProgress/create` request to create a progress indicator.
  ///
  /// This requests the client to create a progress UI element (like a progress
  /// bar) that can be updated with subsequent [progress] notifications.
  ///
  /// - [token]: A unique identifier for this progress session.
  ///
  /// After creating the progress indicator, use [progress] to send updates.
  ///
  /// Example:
  /// ```dart
  /// final token = ProgressToken.string('indexing-123');
  /// await output.workDoneProgressCreate(token: token);
  /// output.progress(params: WorkDoneProgressParams(
  ///   token: token,
  ///   value: WorkDoneProgressBegin(title: 'Indexing'),
  /// ));
  /// ```
  Future<void> workDoneProgressCreate({required ProgressToken token}) async {
    const requestId = 'workDoneProgressCreate';
    final params = WorkDoneProgressCreateParams(token: token);
    _writeMessage(WorkDoneProgressCreateRequest(id: requestId, params: params));
  }

  /// Sends a `$/progress` notification to update a progress indicator.
  ///
  /// This updates the progress UI created by [workDoneProgressCreate].
  /// The value can be a begin, report, or end event.
  ///
  /// - [params]: Contains the progress token and the update value.
  ///
  /// Example:
  /// ```dart
  /// output.progress(params: WorkDoneProgressParams(
  ///   token: token,
  ///   value: WorkDoneProgressReport(percentage: 50, message: 'Half done'),
  /// ));
  /// output.progress(params: WorkDoneProgressParams(
  ///   token: token,
  ///   value: WorkDoneProgressEnd(message: 'Complete'),
  /// ));
  /// ```
  void progress({required WorkDoneProgressParams params}) {
    _writeMessage(WorkDoneProgressNotification(params));
  }

  /// Writes an LSP message with proper protocol framing.
  ///
  /// Serializes the message to JSON and wraps it with LSP headers:
  /// ```
  /// Content-Length: <bytes>\r\n
  /// \r\n
  /// <json payload>
  /// ```
  ///
  /// This is a low-level method used by all public message-sending methods.
  void _writeMessage(OutgoingMessage message) {
    final payload = jsonEncode(message.toJson());
    final bytes = utf8.encode(payload);

    // LSP framing:
    // Content-Length: <bytes>\r\n
    // \r\n
    // <json>
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';

    // Write header + json to the configured sink.
    _output.add(utf8.encode(header));
    _output.add(bytes);
    // Do not add extra newlines; protocol framing must be exact.
  }
}
