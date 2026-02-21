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

    group('ServerNotInitialized (-32002)', () {
      test(
        'returns ServerNotInitialized for unknown method before initialize',
        () async {
          // Send an unknown request without initializing first.
          // The server must return ServerNotInitialized, not MethodNotFound,
          // because the initialization guard runs before method dispatch.
          final response = await client.sendRawRequest(
            method: 'textDocument/hover',
            params: {
              'textDocument': {'uri': 'file:///test.cls'},
              'position': {'line': 0, 'character': 0},
            },
          );

          expect(response, isLspError(-32002));
        },
      );

      test(
        'returns ServerNotInitialized for known method before initialize',
        () async {
          // Even a method the server supports returns ServerNotInitialized
          // when sent before the initialize handshake.
          final response = await client.sendRawRequest(
            method: 'textDocument/completion',
            params: {
              'textDocument': {'uri': 'file:///test.cls'},
              'position': {'line': 0, 'character': 0},
            },
          );

          expect(response, isLspError(-32002));
        },
      );
    });

    group(r'MethodNotFound (-32601)', () {
      setUp(() async {
        // Initialize so we reach method dispatch (past the ServerNotInitialized guard).
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );
      });

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
          method: 'textDocument/definition',
          params: {
            'textDocument': {'uri': 'file:///test.cls'},
            'position': {'line': 0, 'character': 0},
          },
        );

        expect(response, isLspError(-32601));
        final error = response['error'] as Map<String, Object?>;
        final message = error['message'] as String;
        expect(message, contains('Unknown method'));
        expect(message, contains('textDocument/definition'));
      });
    });

    group(r'RequestCancelled (-32800) for $/cancelRequest', () {
      test('registers cancellation for future requests', () async {
        // Initialize first.
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        final requestId = 999;

        // Send cancellation BEFORE the request.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'method': r'$/cancelRequest',
          'params': {'id': requestId},
        });

        // Then send the request - should be immediately cancelled.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'shutdown',
        });

        // Server should send RequestCancelled error.
        final response = await client.waitForAnyResponse(
          timeout: const Duration(seconds: 2),
        );

        expect(response, isLspError(-32800));
        expect(response['id'], equals(requestId));
      });

      test('registers cancellation before initialize is called', () async {
        // $/cancelRequest must be processed regardless of initialization state.
        final requestId = 777;

        client.input.addFrame({
          'jsonrpc': '2.0',
          'method': r'$/cancelRequest',
          'params': {'id': requestId},
        });

        // Initialize so we can then send the cancelled request.
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        // The cancellation sent before init should still be registered.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'shutdown',
        });

        final response = await client.waitForAnyResponse(
          timeout: const Duration(seconds: 2),
        );

        expect(response, isLspError(-32800));
        expect(response['id'], equals(requestId));
      });

      test('handles cancellation after request completes', () async {
        // Initialize first so completion can work.
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        // Send and complete a request.
        final requestId = 888;
        client.input.addFrame({
          'jsonrpc': '2.0',
          'id': requestId,
          'method': 'shutdown',
        });

        final response = await client.waitForAnyResponse(
          timeout: const Duration(seconds: 2),
        );
        expect(response['id'], equals(requestId));
        expect(response.containsKey('result'), isTrue);

        // Send cancellation after completion - should be silently ignored.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'method': r'$/cancelRequest',
          'params': {'id': requestId},
        });

        // Wait a bit and verify server is still responsive.
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final shutdownResponse = await client.sendRawRequest(
          method: 'shutdown',
        );
        expect(shutdownResponse.containsKey('result'), isTrue);
      });
    });

    group('Exit before initialize', () {
      test('exit in NotInitialized state terminates with code 1', () async {
        // The exit notification must be honoured regardless of whether
        // the server has been initialized. Without initialize, the spec
        // requires exit code 1.
        //
        // In tests, exitFn throws _ExitCalled, which propagates through
        // server.run() and is caught by dispose(). We just verify the
        // server task ends promptly (i.e. the notification was processed).
        client.input.addFrame({'jsonrpc': '2.0', 'method': 'exit'});

        // dispose() awaits the server task and swallows _ExitCalled.
        // If exit was NOT processed this would hang for 2 seconds.
        await client.dispose().timeout(const Duration(seconds: 2));
      });
    });

    group('Client Response Parsing', () {
      test('parses and handles successful client response', () async {
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        // Client responds to a server request (like window/workDoneProgress/create)
        // with a success response.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'id': 'test-request-123',
          'result': null,
        });

        // Server should parse it without errors (verify via logs or no crash).
        // Since responses are just logged for now, we just verify no error.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Server should still be responsive.
        final shutdownResponse = await client.sendRawRequest(
          method: 'shutdown',
        );
        expect(shutdownResponse.containsKey('result'), isTrue);
      });

      test('parses and handles error client response', () async {
        await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        // Client responds with an error.
        client.input.addFrame({
          'jsonrpc': '2.0',
          'id': 'test-request-456',
          'error': {'code': -32601, 'message': 'Method not found'},
        });

        // Server should parse it without crashing.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Server should still be responsive.
        final shutdownResponse = await client.sendRawRequest(
          method: 'shutdown',
        );
        expect(shutdownResponse.containsKey('result'), isTrue);
      });
    });
  });
}
