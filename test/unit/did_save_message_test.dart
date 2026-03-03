import 'dart:async';

import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:test/test.dart';

import '../support/lsp_test_harness.dart';

void main() {
  group('textDocument/didSave notification parsing', () {
    Future<MessageParseResult> parse(Map<String, Object?> json) async {
      final frame = lspFrame(json);
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);
      final resultFuture = reader.messages().first;
      controller.add(frame);
      unawaited(controller.close());
      return resultFuture;
    }

    test(
      'parses didSave notification into TextDocumentDidSaveMessage',
      () async {
        final result = await parse({
          'jsonrpc': '2.0',
          'method': 'textDocument/didSave',
          'params': {
            'textDocument': {'uri': 'file:///workspace/MyClass.cls'},
          },
        });

        expect(result, isA<ParsedMessage>());
        final message = (result as ParsedMessage).message;
        expect(message, isA<TextDocumentDidSaveMessage>());
        final save = message as TextDocumentDidSaveMessage;
        expect(
          save.params.textDocument.uri,
          equals('file:///workspace/MyClass.cls'),
        );
      },
    );

    test('parses didSave for a field-meta.xml file', () async {
      final result = await parse({
        'jsonrpc': '2.0',
        'method': 'textDocument/didSave',
        'params': {
          'textDocument': {
            'uri':
                'file:///workspace/objects/Account/fields/Name.field-meta.xml',
          },
        },
      });

      final message =
          (result as ParsedMessage).message as TextDocumentDidSaveMessage;
      expect(
        message.params.textDocument.uri,
        equals('file:///workspace/objects/Account/fields/Name.field-meta.xml'),
      );
    });

    test('silently ignores didSave with missing params', () async {
      // Missing params entirely, should be ignored (returns null from parser,
      // so the stream emits nothing).
      final frame = lspFrame({
        'jsonrpc': '2.0',
        'method': 'textDocument/didSave',
      });
      final controller = StreamController<List<int>>();
      final reader = MessageReader(controller.stream);
      final messagesFuture = reader.messages().toList();
      controller.add(frame);
      unawaited(controller.close());

      final messages = await messagesFuture;
      expect(messages, isEmpty);
    });
  });
}
