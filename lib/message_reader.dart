import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'message.dart';

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
  /// successfully parsed message. The stream continues until the input
  /// stream closes or an unrecoverable error occurs.
  ///
  /// **Protocol handling:**
  /// - Buffers incoming bytes until a complete message is available
  /// - Validates Content-Length header
  /// - Decodes JSON payloads as UTF-8
  /// - Routes messages to appropriate types (requests vs notifications)
  ///
  /// Invalid or malformed messages are silently skipped to maintain server
  /// stability.
  ///
  /// Example:
  /// ```dart
  /// await for (final message in reader.messages()) {
  ///   if (message is InitializeRequest) {
  ///     // Handle initialization
  ///   }
  /// }
  /// ```
  Stream<IncomingMessage> messages() async* {
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

        final decoded = _tryDecodeJson(bodyText);
        if (decoded == null) {
          // TODO: Handle? Ignore malformed JSON in this minimal implementation.
          continue;
        }

        final msg = _parseJsonRpcMessage(decoded);
        if (msg != null) {
          yield msg;
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

  /// Attempts to decode a JSON string into a Dart object.
  ///
  /// - [text]: The JSON string to decode.
  ///
  /// Returns the decoded object, or `null` if the JSON is malformed.
  ///
  /// TODO: Return proper error object rather than null. That will allow us to not have to be checking for `Object`
  /// types in the code above
  static Object? _tryDecodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// Parses a decoded JSON object into a typed LSP message.
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
  /// Returns the parsed message, or `null` if the message is invalid,
  /// unsupported, or malformed.
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
  static IncomingMessage? _parseJsonRpcMessage(Object decoded) {
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
      return switch (method) {
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
    } else if (hasMethod && (!hasId || id == null)) {
      final rawParams = decoded['params'];

      return switch (method) {
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
