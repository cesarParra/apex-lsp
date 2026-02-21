import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/utils/platform.dart';

/// Captures bytes written by [LspOut] into an in-memory buffer.
///
/// Use [takeBytes] to retrieve and clear all bytes written so far.
/// Use [takeFrames] to decode LSP-framed JSON-RPC messages that have been
/// written so far.
final class InMemoryByteSink implements LspByteSink {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    _buffer.add(data);
  }

  @override
  Future<void> flush() async {
    // No-op for in-memory sink.
  }

  /// Returns all bytes written so far and clears the internal buffer.
  Uint8List takeBytes() {
    final bytes = _buffer.toBytes();
    _buffer.clear();
    return bytes;
  }

  /// Decodes and returns all complete LSP frames written so far, then clears them
  /// from the internal buffer.
  ///
  /// Any trailing partial frame remains buffered for the next call.
  List<Object?> takeFrames({bool allowMalformedJson = true}) {
    final data = _buffer.toBytes();
    final frames = <Object?>[];

    var offset = 0;
    while (true) {
      final headerEnd = _indexOfCrlfCrlf(data, start: offset);
      if (headerEnd == -1) break;

      final headerBytes = data.sublist(offset, headerEnd);
      final headerText = ascii.decode(headerBytes, allowInvalid: true);

      final contentLength = _parseContentLength(headerText);
      if (contentLength == null) {
        // Drop invalid header block and continue scanning.
        offset = headerEnd + 4;
        continue;
      }

      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + contentLength;
      if (data.length < bodyEnd) break; // partial frame, keep buffered

      final bodyBytes = data.sublist(bodyStart, bodyEnd);
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);

      Object? decoded;
      try {
        decoded = jsonDecode(bodyText);
      } catch (_) {
        if (!allowMalformedJson) rethrow;
        decoded = null;
      }

      frames.add(decoded);
      offset = bodyEnd;
    }

    // Keep trailing partial bytes.
    final remaining = data.sublist(offset);
    _buffer.clear();
    if (remaining.isNotEmpty) _buffer.add(remaining);

    return frames;
  }

  static int _indexOfCrlfCrlf(Uint8List data, {required int start}) {
    // Search for "\r\n\r\n" (13,10,13,10)
    for (var i = start; i + 3 < data.length; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static int? _parseContentLength(String headers) {
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
}

/// Builds a single LSP-framed JSON-RPC message payload.
///
/// The returned bytes are:
/// - `Content-Length: <n>\r\n\r\n`
/// - followed by the UTF-8 JSON body with exactly `<n>` bytes.
Uint8List lspFrame(Object json) {
  final payload = jsonEncode(json);
  final body = utf8.encode(payload);
  final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');

  final out = BytesBuilder(copy: false);
  out.add(header);
  out.add(body);
  return out.toBytes();
}

/// Splits [bytes] into chunks of size [chunkSize] (last chunk may be smaller).
///
/// Useful to simulate arbitrary IO chunking in tests.
List<Uint8List> chunkBytes(Uint8List bytes, {required int chunkSize}) {
  if (chunkSize <= 0) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be > 0');
  }

  final chunks = <Uint8List>[];
  var offset = 0;
  while (offset < bytes.length) {
    final end = (offset + chunkSize).clamp(0, bytes.length);
    chunks.add(Uint8List.sublistView(bytes, offset, end));
    offset = end;
  }
  return chunks;
}

/// A simple in-memory stream driver for feeding LSP frames to the server.
///
/// Example usage:
/// - create [input] and pass to `Server(input: harness.stream, ...)`
/// - call [addFrame] / [addFrames] during the test
/// - call [close] when done
final class InMemoryLspInput {
  final StreamController<List<int>> _controller;

  InMemoryLspInput({bool sync = true})
    : _controller = StreamController<List<int>>(sync: sync);

  Stream<List<int>> get stream => _controller.stream;

  void addBytes(List<int> bytes) => _controller.add(bytes);

  void addFrame(Object json) => _controller.add(lspFrame(json));

  void addFrames(Iterable<Object> jsonMessages) {
    for (final msg in jsonMessages) {
      addFrame(msg);
    }
  }

  /// Adds a frame but split into chunks of [chunkSize] to simulate streaming.
  void addFrameChunked(Object json, {required int chunkSize}) {
    final framed = lspFrame(json);
    for (final chunk in chunkBytes(framed, chunkSize: chunkSize)) {
      _controller.add(chunk);
    }
  }

  Future<void> close() => _controller.close();
}

final class FakeLspPlatform implements LspPlatform {
  FakeLspPlatform({this.isWindows = false, this.pathSeparator = '/'});

  @override
  final bool isWindows;

  @override
  final String pathSeparator;
}

/// Helper to build a minimal `initialize` request.
Map<String, Object?> jsonRpcInitialize({
  required Object id,
  List<Map<String, String>>? workspaceFolders,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': 'initialize',
    'params': <String, Object?>{
      if (workspaceFolders != null) 'workspaceFolders': workspaceFolders,
    },
  };
}

/// Helper to build a JSON-RPC request.
Map<String, Object?> jsonRpcRequest({
  required Object id,
  required String method,
  Object? params,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };
}

/// Helper to build a JSON-RPC notification.
Map<String, Object?> jsonRpcNotification({
  required String method,
  Object? params,
}) {
  return <String, Object?>{
    'jsonrpc': '2.0',
    'method': method,
    if (params != null) 'params': params,
  };
}
