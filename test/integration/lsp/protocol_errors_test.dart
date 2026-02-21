import 'dart:convert';

import 'package:test/test.dart';

import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('LSP Protocol Errors', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(classFiles: []);
      client = createLspClient()..start();
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    group('ParseError (-32700)', () {
      test('returns ParseError for malformed JSON', () async {
        // Build a properly framed message with invalid JSON body.
        final malformedJson = '{invalid json}';
        final body = utf8.encode(malformedJson);
        final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');

        final frame = <int>[];
        frame.addAll(header);
        frame.addAll(body);

        // Send raw bytes directly.
        client.input.addBytes(frame);

        // Server should send back a ParseError response.
        // Since we don't have a valid request ID, expect id: null.
        final response = await client.waitForAnyResponse(
          timeout: const Duration(seconds: 2),
        );

        expect(response, isLspError(-32700));
        expect(response['id'], isNull);
      });

      test(
        'returns ParseError with request ID when ID is extractable',
        () async {
          // Malformed JSON that contains a parseable "id" field.
          final malformedJson = '{"jsonrpc":"2.0","id":42,"method":invalid}';
          final body = utf8.encode(malformedJson);
          final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');

          final frame = <int>[];
          frame.addAll(header);
          frame.addAll(body);

          client.input.addBytes(frame);

          final response = await client.waitForAnyResponse(
            timeout: const Duration(seconds: 2),
          );

          expect(response, isLspError(-32700));
          expect(response['id'], equals(42));
        },
      );

      test('returns ParseError for non-object JSON', () async {
        // Valid JSON, but not an object (protocol violation).
        final malformedJson = '"just a string"';
        final body = utf8.encode(malformedJson);
        final header = ascii.encode('Content-Length: ${body.length}\r\n\r\n');

        final frame = <int>[];
        frame.addAll(header);
        frame.addAll(body);

        client.input.addBytes(frame);

        final response = await client.waitForAnyResponse(
          timeout: const Duration(seconds: 2),
        );

        expect(response, isLspError(-32700));
        expect(response['id'], isNull);
      });
    });

    group(r'MethodNotFound (-32601) for unknown $/ requests', () {
      test(r'returns MethodNotFound for unknown $/request', () async {
        final response = await client.sendRawRequest(
          method: r'$/unknownRequest',
          params: {'foo': 'bar'},
        );

        expect(response, isLspError(-32601));
        final error = response['error'] as Map<String, Object?>;
        final message = error['message'] as String;
        expect(message, contains('Unknown method'));
        expect(message, contains(r'$/unknownRequest'));
      });

      test(r'silently ignores unknown $/notification', () async {
        // Send an unknown $/notification - should be silently ignored.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'method': r'$/unknownNotification',
          'params': {'foo': 'bar'},
        });

        // Wait a bit to ensure server doesn't crash or send error.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Verify server is still responsive by sending a valid request.
        final response = await client.sendRawRequest(method: 'shutdown');

        expect(response['result'], isNull);
        expect(response.containsKey('error'), isFalse);
      });
    });

    group(r'MethodNotFound (-32601) for unknown non-$/ methods', () {
      test('returns MethodNotFound for unknown request method', () async {
        final response = await client.sendRawRequest(
          method: 'unknownMethod',
          params: {'foo': 'bar'},
        );

        expect(response, isLspError(-32601));
        final error = response['error'] as Map<String, Object?>;
        final message = error['message'] as String;
        expect(message, contains('Unknown method'));
        expect(message, contains('unknownMethod'));
      });

      test('returns MethodNotFound for unsupported LSP method', () async {
        // A real LSP method that we don't support yet.
        final response = await client.sendRawRequest(
          method: 'textDocument/hover',
          params: {
            'textDocument': {'uri': 'file:///test.cls'},
            'position': {'line': 0, 'character': 0},
          },
        );

        expect(response, isLspError(-32601));
        final error = response['error'] as Map<String, Object?>;
        final message = error['message'] as String;
        expect(message, contains('Unknown method'));
        expect(message, contains('textDocument/hover'));
      });
    });
  });
}
