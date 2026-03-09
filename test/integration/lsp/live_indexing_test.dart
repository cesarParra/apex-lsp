import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/lsp_matchers.dart';
import '../../support/cursor_utils.dart';
import '../../support/lsp_client.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

/// Polls [probe] every few milliseconds until it returns a passing value or
/// [timeout] expires, then returns the last result regardless.
///
/// Used to wait for async server-side work (re-indexing) to complete before
/// asserting on completion results.
Future<T> _pollUntil<T>(
  Future<T> Function() probe, {
  bool Function(T)? until,
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  late T last;
  while (DateTime.now().isBefore(deadline)) {
    last = await probe();
    if (until == null || until(last)) return last;
    await Future<void>.delayed(interval);
  }
  return last;
}

void main() {
  group('live indexing (textDocument/didSave)', () {
    late TestWorkspace workspace;
    late LspClient client;
    late MemoryFileSystem fileSystem;

    setUp(() async {
      final result = createLspClient();
      client = result.client..start();
      fileSystem = result.fileSystem;
      workspace = await createTestWorkspace(
        fileSystem: fileSystem,
        classFiles: [
          (
            name: 'Widget.cls',
            source: 'public class Widget { public String color; }',
          ),
        ],
      );
      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
    });

    tearDown(() async {
      await client.dispose();
    });

    test(
      'completions reflect a new field after the .cls file is saved',
      () async {
        final textWithPosition = extractCursorPosition('''
Widget w;
w.{cursor}''');
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final completionsBefore = await _pollUntil(
          () => client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          ),
          until: (list) => list.items.any((i) => i.label == 'color'),
        );
        expect(completionsBefore, containsCompletion('color'));
        expect(completionsBefore, doesNotContainCompletion('size'));

        // Update the file in the memory filesystem to add a new field.
        final classFile = fileSystem.file(
          '${workspace.classesPath}/Widget.cls',
        );
        await classFile.writeAsString(
          'public class Widget { public String color; public Integer size; }',
        );

        // Notify the server of the save.
        await client.saveDocument(uri: Uri.file(classFile.path).toString());

        // Poll until the re-indexed field appears in completions.
        final completionsAfter = await _pollUntil(
          () => client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          ),
          until: (list) => list.items.any((i) => i.label == 'size'),
        );

        expect(completionsAfter, containsCompletion('size'));
        expect(completionsAfter, containsCompletion('color'));
      },
    );
  });

  group('live indexing (workspace/didDeleteFiles)', () {
    late TestWorkspace workspace;
    late LspClient client;
    late MemoryFileSystem fileSystem;

    setUp(() async {
      final result = createLspClient();
      client = result.client..start();
      fileSystem = result.fileSystem;
      workspace = await createTestWorkspace(
        fileSystem: fileSystem,
        classFiles: [
          (name: 'Alpha.cls', source: 'public class Alpha {}'),
          (name: 'Beta.cls', source: 'public class Beta {}'),
        ],
      );
      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
    });

    tearDown(() async {
      await client.dispose();
    });

    test(
      'completions no longer include a class after its .cls file is deleted',
      () async {
        final textWithPosition = extractCursorPosition('{cursor}');
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        // Both classes visible before deletion.
        final completionsBefore = await client.completion(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );
        expect(completionsBefore, containsCompletion('Alpha'));
        expect(completionsBefore, containsCompletion('Beta'));

        // Delete Alpha.cls from the memory filesystem and notify the server.
        final alphaFile = fileSystem.file('${workspace.classesPath}/Alpha.cls');
        await alphaFile.delete();
        await client.deleteFiles(uris: [Uri.file(alphaFile.path).toString()]);

        // Poll until Alpha disappears from completions.
        final completionsAfter = await _pollUntil(
          () => client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          ),
          until: (list) => list.items.every((i) => i.label != 'Alpha'),
        );

        expect(completionsAfter, doesNotContainCompletion('Alpha'));
        expect(completionsAfter, containsCompletion('Beta'));
      },
    );
  });
}
