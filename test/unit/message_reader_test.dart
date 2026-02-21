import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:test/test.dart';

void main() {
  group('MessageReader response parsing', () {
    test('parses successful client response with null result', () async {
      final json = {'jsonrpc': '2.0', 'id': 'test-123', 'result': null};

      final frame = _createLspFrame(json);
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);

      // Start listening before adding data.
      final resultFuture = reader.messages().first;
      controller.add(frame);
      unawaited(controller.close());

      final result = await resultFuture;

      expect(result, isA<ParsedMessage>());
      final parsed = result as ParsedMessage;
      expect(parsed.message, isA<ClientResponse>());
      final response = parsed.message as ClientSuccessResponse;
      expect(response.id, equals('test-123'));
      expect(response.result, isNull);
    });

    test('parses successful client response with object result', () async {
      final json = {
        'jsonrpc': '2.0',
        'id': 42,
        'result': {'status': 'ok'},
      };

      final frame = _createLspFrame(json);
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);

      final resultFuture = reader.messages().first;
      controller.add(frame);
      unawaited(controller.close());

      final result = await resultFuture;

      final parsed = result as ParsedMessage;
      final response = parsed.message as ClientSuccessResponse;
      expect(response.id, equals(42));
      expect(response.result, equals({'status': 'ok'}));
    });

    test('parses error client response', () async {
      final json = {
        'jsonrpc': '2.0',
        'id': 'test-456',
        'error': {
          'code': -32601,
          'message': 'Method not found',
          'data': 'additional info',
        },
      };

      final frame = _createLspFrame(json);
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);

      final resultFuture = reader.messages().first;
      controller.add(frame);
      unawaited(controller.close());

      final result = await resultFuture;

      final parsed = result as ParsedMessage;
      final response = parsed.message as ClientErrorResponse;
      expect(response.id, equals('test-456'));
      expect(response.error.code, equals(-32601));
      expect(response.error.message, equals('Method not found'));
      expect(response.error.data, equals('additional info'));
    });

    test('returns null for response without id', () async {
      final json = {'jsonrpc': '2.0', 'result': null};

      final frame = _createLspFrame(json);
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);

      final messagesFuture = reader.messages().toList();
      controller.add(frame);
      unawaited(controller.close());

      final messages = await messagesFuture;

      // Malformed response (no id) should be silently ignored.
      expect(messages, isEmpty);
    });
  });
}

/// Creates an LSP-framed message from JSON.
Uint8List _createLspFrame(Object json) {
  final payload = jsonEncode(json);
  final body = utf8.encode(payload);
  final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');

  final out = BytesBuilder(copy: false);
  out.add(header);
  out.add(body);
  return out.toBytes();
}
