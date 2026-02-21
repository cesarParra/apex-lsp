import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'message.dart';

/// Result of parsing a single LSP message.
///
/// This sealed class allows the message reader to communicate parse errors
/// to the server while preserving request IDs when possible, enabling proper
/// JSON-RPC error responses.
sealed class MessageParseResult {}

/// Successfully parsed message.
final class ParsedMessage extends MessageParseResult {
  final Object message;
  ParsedMessage(this.message);
}

/// Parse error with optional request ID (extracted when possible).
final class ParseErrorResult extends MessageParseResult {
  final Object? requestId;
  final String errorMessage;

  ParseErrorResult({required this.requestId, required this.errorMessage});
}

/// Method not found error for unknown JSON-RPC methods.
final class MethodNotFoundResult extends MessageParseResult {
  final Object requestId;
  final String method;

  MethodNotFoundResult({required this.requestId, required this.method});
}

/// Reads and parses Language Server Protocol messages from a byte stream.
///
/// This class handles the LSP message framing protocol, which consists of
/// HTTP-style headers followed by a JSON payload. Each message has a
/// `Content-Length` header indicating the size of the JSON body.
///
/// **Message format:**
/// ```
/// Content-Length: <bytes>\r\n
/// \r\n
/// <JSON payload>
/// ```
///
/// **Key features:**
/// - Streams incoming LSP messages as they arrive
/// - Handles partial reads and buffering
/// - Parses both requests (with `id`) and notifications (without `id`)
/// - UTF-8 decoding of JSON payloads
/// - ASCII decoding of headers
///
/// Example:
/// ```dart
/// final reader = MessageReader(stdin);
/// await for (final message in reader.messages()) {
///   switch (message) {
///     case InitializeRequest():
///       // Handle initialization
///     case CompletionRequest():
///       // Handle completion
///   }
/// }
/// ```
///
/// See also:
///  * [LspOut], which sends outgoing LSP messages.
///  * [IncomingMessage], the base type for all parsed messages.
final class MessageReader {
  MessageReader(Stream<List<int>> input) : _input = input;

  final Stream<List<int>> _input;

  /// Streams LSP messages parsed from the input byte stream.
  ///
  /// Continuously reads and parses LSP-framed messages, yielding each
  /// successfully parsed message or parse error. The stream continues until
  /// the input stream closes or an unrecoverable error occurs.
  ///
  /// **Protocol handling:**
  /// - Buffers incoming bytes until a complete message is available
  /// - Validates Content-Length header
  /// - Decodes JSON payloads as UTF-8
  /// - Routes messages to appropriate types (requests vs notifications)
  /// - Returns [ParseErrorResult] for malformed JSON (per JSON-RPC 2.0)
  ///
  /// Example:
  /// ```dart
  /// await for (final result in reader.messages()) {
  ///   switch (result) {
  ///     case ParsedMessage(:final message):
  ///       // Handle the message
  ///     case ParseErrorResult():
  ///       // Send error response
  ///   }
  /// }
  /// ```
  Stream<MessageParseResult> messages() async* {
    // Buffer of bytes read so far.
    final buffer = BytesBuilder(copy: false);

    await for (final chunk in _input) {
      buffer.add(chunk);

      while (true) {
        final data = buffer.toBytes();

        // Find header terminator: \r\n\r\n
        final headerEnd = _indexOfCrlfCrlf(data);
        if (headerEnd == -1) break;

        // Header is ASCII up to headerEnd (exclusive).
        final headerBytes = data.sublist(0, headerEnd);
        final headerText = ascii.decode(headerBytes, allowInvalid: true);

        final contentLength = _parseContentLength(headerText);
        if (contentLength == null) {
          // Invalid framing; drop this header and continue searching.
          // In a real server, you would probably send a parse error.
          _consume(buffer, headerEnd + 4);
          continue;
        }

        final bodyStart = headerEnd + 4; // skip \r\n\r\n
        final bodyEnd = bodyStart + contentLength;

        if (data.length < bodyEnd) {
          // Wait for more bytes.
          break;
        }

        final bodyBytes = data.sublist(bodyStart, bodyEnd);
        final bodyText = utf8.decode(bodyBytes, allowMalformed: true);

        // Consume used bytes from the buffer.
        _consume(buffer, bodyEnd);

        final parseResult = _tryDecodeJson(bodyText);
        switch (parseResult) {
          case ParseErrorResult():
            // Yield parse error immediately so server can respond.
            yield parseResult;
          case MethodNotFoundResult():
            // Yield method not found error so server can respond.
            yield parseResult;
          case ParsedMessage(:final message):
            // Try to parse into a typed message.
            final messageResult = _parseJsonRpcMessage(message);
            if (messageResult != null) {
              yield messageResult;
            }
          // Note: null means silently ignored (e.g., unknown $/notifications)
        }
      }
    }
  }

  /// Finds the position of the header terminator `\r\n\r\n` in the byte array.
  ///
  /// - [data]: The byte array to search within.
  ///
  /// Returns the index of the first `\r` in the `\r\n\r\n` sequence, or -1
  /// if the sequence is not found.
  static int _indexOfCrlfCrlf(Uint8List data) {
    // Search for "\r\n\r\n" (13,10,13,10)
    for (var i = 0; i + 3 < data.length; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// Extracts the Content-Length value from LSP message headers.
  ///
  /// Parses headers in the format `Header-Name: value\r\n` and returns the
  /// numeric value of the `Content-Length` header.
  ///
  /// - [headers]: The complete header section as an ASCII string.
  ///
  /// Returns the content length in bytes, or `null` if the header is missing,
  /// malformed, or contains an invalid value.
  ///
  /// Example:
  /// ```dart
  /// final headers = 'Content-Length: 42\r\nContent-Type: application/json\r\n';
  /// final length = _parseContentLength(headers); // 42
  /// ```
  static int? _parseContentLength(String headers) {
    // Small parser for Content-Length: <number>
    // Header fields are separated by \r\n.
    final lines = headers.split('\r\n');
    for (final line in lines) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;

      final name = line.substring(0, idx).trim().toLowerCase();
      if (name != 'content-length') continue;

      final value = line.substring(idx + 1).trim();
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 0) return null;
      return parsed;
    }
    return null;
  }

  /// Attempts to decode the JSON payload from a message body.
  ///
  /// Returns a [MessageParseResult] containing either:
  /// - A successfully decoded object
  /// - A parse error with the request ID extracted when possible
  ///
  /// When JSON is malformed, this method attempts to extract the `id` field
  /// using a simple regex pattern to enable proper error responses per
  /// JSON-RPC 2.0 specification.
  static MessageParseResult _tryDecodeJson(String text) {
    try {
      final decoded = jsonDecode(text);
      // JSON must be an object for JSON-RPC 2.0.
      if (decoded is! Map) {
        return ParseErrorResult(
          requestId: null,
          errorMessage: 'JSON-RPC message must be an object',
        );
      }
      return ParsedMessage(decoded);
    } catch (error) {
      // Try to extract the request ID for better error responses.
      final requestId = _extractRequestId(text);
      return ParseErrorResult(
        requestId: requestId,
        errorMessage: 'Parse error: $error',
      );
    }
  }

  /// Attempts to extract the request ID from malformed JSON.
  ///
  /// Uses a simple pattern match to find `"id": <value>` in the text.
  /// Returns `null` if no ID can be extracted.
  static Object? _extractRequestId(String text) {
    // Look for "id": followed by a number or string.
    // This is a best-effort extraction and won't handle all cases.
    final match = RegExp(r'"id"\s*:\s*(\d+|"[^"]*")').firstMatch(text);
    if (match == null) return null;

    final idText = match.group(1);
    if (idText == null) return null;

    // Try parsing as int first, then as string.
    if (idText.startsWith('"')) {
      return idText.substring(1, idText.length - 1);
    }
    return int.tryParse(idText);
  }

  /// Parses a decoded JSON object into a typed LSP message or error result.
  ///
  /// Validates JSON-RPC 2.0 format and routes the message to the appropriate
  /// message type based on the `method` field and presence of `id`.
  ///
  /// - [decoded]: The decoded JSON object from the message payload.
  ///
  /// **Message routing:**
  /// - Messages with `method` and `id` are requests
  /// - Messages with `method` but no `id` are notifications
  /// - Responses (with `id` but no `method`) are currently ignored
  ///
  /// **Return values:**
  /// - `ParsedMessage` for known/supported methods
  /// - `MethodNotFoundResult` for unknown request methods
  /// - `null` for unknown notifications (silently ignored per LSP spec)
  ///
  /// Supported requests:
  /// - `initialize`
  /// - `shutdown`
  /// - `textDocument/completion`
  ///
  /// Supported notifications:
  /// - `initialized`
  /// - `exit`
  /// - `textDocument/didOpen`
  /// - `textDocument/didChange`
  /// - `textDocument/didClose`
  static MessageParseResult? _parseJsonRpcMessage(Object decoded) {
    if (decoded is! Map) return null;

    final jsonrpc = decoded['jsonrpc'];
    if (jsonrpc != '2.0') return null;

    final method = decoded['method'];
    final hasMethod = method is String;

    final hasId = decoded.containsKey('id');
    final id = decoded['id'];

    // Per JSON-RPC:
    // - Requests have "method" + "id"
    // - Notifications have "method" and no "id"
    if (hasMethod && hasId && id != null) {
      Object idAsObject = id as Object;
      final rawParams = decoded['params'];
      final incomingMessage = switch (method) {
        'initialize' => InitializeRequest(
          idAsObject,
          InitializedParams.fromJson(rawParams as Map<String, dynamic>),
        ),
        'shutdown' => ShutdownRequest(idAsObject),
        'textDocument/completion' => switch (rawParams) {
          final Map<String, Object?> paramsJson => CompletionRequest(
            idAsObject,
            CompletionParams.fromJson(paramsJson),
          ),
          _ => null,
        },
        _ => null,
      };

      if (incomingMessage != null) {
        return ParsedMessage(incomingMessage);
      }

      // Unknown request method - return MethodNotFound error.
      return MethodNotFoundResult(requestId: idAsObject, method: method);
    } else if (hasMethod && (!hasId || id == null)) {
      final rawParams = decoded['params'];

      final incomingMessage = switch (method) {
        'initialized' => InitializedMessage(),
        'exit' => ExitMessage(),

        'textDocument/didOpen' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidOpenMessage(
            DidOpenTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        'textDocument/didChange' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidChangeMessage(
            DidChangeTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        'textDocument/didClose' => switch (rawParams) {
          final Map<String, Object?> paramsJson => TextDocumentDidCloseMessage(
            DidCloseTextDocumentParams.fromJson(paramsJson),
          ),
          _ => null,
        },

        _ => null,
      };

      if (incomingMessage != null) {
        return ParsedMessage(incomingMessage);
      }

      // Unknown notification - silently ignore per LSP spec.
      // (Client can send $/notifications we don't support.)
      return null;
    }

    // TODO: Responses are ignored by servers in this minimal implementation,
    // let's handle them (and avoid returning null)
    return null;
  }

  /// Removes the first [count] bytes from the buffer.
  ///
  /// This is used after successfully parsing a message to discard the
  /// consumed bytes and retain any remaining data for the next message.
  ///
  /// - [buffer]: The byte buffer to modify.
  /// - [count]: The number of bytes to remove from the beginning.
  static void _consume(BytesBuilder buffer, int count) {
    final data = buffer.toBytes();
    final remaining = data.sublist(count);
    buffer.clear();
    if (remaining.isNotEmpty) buffer.add(remaining);
  }
}
