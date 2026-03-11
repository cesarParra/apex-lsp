import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_matchers.dart';
import '../../support/lsp_client.dart';

import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('when indexing', () {
    test('the first run with no .sf-zed builds a complete index', () async {
      final fileSystem = MemoryFileSystem();
      final client = await createInitializedClient(
        fileSystem: fileSystem,
        classFiles: [(name: 'Greeter.cls', source: 'public class Greeter {}')],
      );

      final indexDir = fileSystem.directory(
        '${client.workspace!.directory.path}/$indexRootFolderName/$apexIndexFolderName',
      );
      expect(indexDir.existsSync(), isTrue);
      expect(
        fileSystem.file('${indexDir.path}/Greeter.json').existsSync(),
        isTrue,
      );

      await client.dispose();
    });

    test('a restart with no source changes does not re-index files', () async {
      final fileSystem = MemoryFileSystem();
      final firstClient = await createInitializedClient(
        fileSystem: fileSystem,
        classFiles: [(name: 'Greeter.cls', source: 'public class Greeter {}')],
      );
      await firstClient.dispose();

      final jsonFile = fileSystem.file(
        '${firstClient.workspace!.directory.path}/$indexRootFolderName/$apexIndexFolderName/Greeter.json',
      );
      final modifiedAfterFirstRun = jsonFile.lastModifiedSync();

      // Second run -- nothing changed, so Greeter.json should be untouched.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final secondClient = await createInitializedClient(
        fileSystem: fileSystem,
        workspace: firstClient.workspace,
      );
      await secondClient.dispose();

      expect(
        jsonFile.lastModifiedSync(),
        equals(modifiedAfterFirstRun),
        reason:
            'Greeter.json should not be re-indexed when source is unchanged',
      );
    });

    test(
      'a restart after modifying one file re-indexes only the changed file',
      () async {
        final fileSystem = MemoryFileSystem();
        final firstClient = await createInitializedClient(
          fileSystem: fileSystem,
          classFiles: [
            (name: 'Alpha.cls', source: 'public class Alpha {}'),
            (name: 'Beta.cls', source: 'public class Beta {}'),
          ],
        );
        await firstClient.dispose();

        final alphaJson = fileSystem.file(
          '${firstClient.workspace!.directory.path}/$indexRootFolderName/$apexIndexFolderName/Alpha.json',
        );
        final betaJson = fileSystem.file(
          '${firstClient.workspace!.directory.path}/$indexRootFolderName/$apexIndexFolderName/Beta.json',
        );
        final alphaModified = alphaJson.lastModifiedSync();
        final betaModified = betaJson.lastModifiedSync();

        // Touch only Beta.cls -- wait long enough for the filesystem to record
        // a distinct modification timestamp.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await fileSystem
            .file('${firstClient.workspace!.classesPath}/Beta.cls')
            .writeAsString('public class Beta { public String name; }');

        final secondClient = await createInitializedClient(
          fileSystem: fileSystem,
          workspace: firstClient.workspace,
        );
        await secondClient.dispose();

        expect(
          alphaJson.lastModifiedSync(),
          equals(alphaModified),
          reason: 'Alpha.json should not be re-indexed',
        );
        expect(
          betaJson.lastModifiedSync().isAfter(betaModified),
          isTrue,
          reason: 'Beta.json should be re-indexed after Beta.cls changed',
        );
      },
    );

    test(
      'workspace completions still work when the index is loaded from a prior run',
      () async {
        final fileSystem = MemoryFileSystem();
        const classFiles = [
          (name: 'Season.cls', source: 'public enum Season { SPRING, SUMMER }'),
        ];

        // First run -- builds index.
        final firstClient = await createInitializedClient(
          fileSystem: fileSystem,
          classFiles: classFiles,
        );
        await firstClient.dispose();

        // Second run -- index already exists, should be reused.
        final secondClient = await createInitializedClient(
          fileSystem: fileSystem,
          workspace: firstClient.workspace,
        );

        final textWithPosition = extractCursorPosition('Sea{cursor}');
        final document = Document.withText(textWithPosition.text);
        await secondClient.openDocument(document);

        final completions = await secondClient.completion(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(completions, containsCompletion('Season'));

        await secondClient.dispose();
      },
    );
  });

  group('when saving indexed files', () {
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

  group('when deleting indexed files', () {
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

/// Polls [probe] every few milliseconds until it returns a passing value or
/// [timeout] expires, then returns the last result regardless.
///
/// Used to wait for async server-side work (re-indexing) to complete before
/// asserting on completion results.
Future<T> _pollUntil<T>(
  Future<T> Function() probe, {
  bool Function(T)? until,
  Duration timeout = const Duration(seconds: 5),
  Duration interval = const Duration(milliseconds: 1),
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
