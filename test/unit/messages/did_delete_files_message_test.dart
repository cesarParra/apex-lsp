import 'dart:async';

import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

void main() {
  group('workspace/didDeleteFiles notification parsing', () {
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
      'parses a single deleted file into WorkspaceDidDeleteFilesMessage',
      () async {
        final result = await parse({
          'jsonrpc': '2.0',
          'method': 'workspace/didDeleteFiles',
          'params': {
            'files': [
              {'uri': 'file:///workspace/MyClass.cls'},
            ],
          },
        });

        expect(result, isA<ParsedMessage>());
        final message = (result as ParsedMessage).message;
        expect(message, isA<WorkspaceDidDeleteFilesMessage>());
        final delete = message as WorkspaceDidDeleteFilesMessage;
        expect(delete.params.files, hasLength(1));
        expect(
          delete.params.files.first.uri,
          equals('file:///workspace/MyClass.cls'),
        );
      },
    );

    test('parses multiple deleted files', () async {
      final result = await parse({
        'jsonrpc': '2.0',
        'method': 'workspace/didDeleteFiles',
        'params': {
          'files': [
            {'uri': 'file:///workspace/Foo.cls'},
            {'uri': 'file:///workspace/Bar.cls'},
          ],
        },
      });

      final message =
          (result as ParsedMessage).message as WorkspaceDidDeleteFilesMessage;
      expect(message.params.files, hasLength(2));
      expect(
        message.params.files.map((f) => f.uri).toList(),
        containsAll(['file:///workspace/Foo.cls', 'file:///workspace/Bar.cls']),
      );
    });

    test('silently ignores didDeleteFiles with missing params', () async {
      final frame = lspFrame({
        'jsonrpc': '2.0',
        'method': 'workspace/didDeleteFiles',
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
