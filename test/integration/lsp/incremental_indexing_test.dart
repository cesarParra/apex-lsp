import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_matchers.dart';
import '../../support/lsp_client.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('incremental indexing', () {
    test('first run with no .sf-zed builds a complete index', () async {
      final fileSystem = MemoryFileSystem();
      final workspace = await createTestWorkspace(
        fileSystem: fileSystem,
        classFiles: [(name: 'Greeter.cls', source: 'public class Greeter {}')],
      );

      final (:client, fileSystem: _) = createLspClient(fileSystem: fileSystem);
      client.start();
      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      final indexDir = fileSystem.directory(
        '${workspace.directory.path}/$indexRootFolderName/$apexIndexFolderName',
      );
      expect(indexDir.existsSync(), isTrue);
      expect(
        fileSystem.file('${indexDir.path}/Greeter.json').existsSync(),
        isTrue,
      );

      await client.dispose();
    });

    test('restart with no source changes does not re-index files', () async {
      final fileSystem = MemoryFileSystem();
      final workspace = await createTestWorkspace(
        fileSystem: fileSystem,
        classFiles: [(name: 'Greeter.cls', source: 'public class Greeter {}')],
      );

      // First run -- builds the index.
      final firstResult = createLspClient(fileSystem: fileSystem);
      final firstClient = firstResult.client..start();
      await firstClient.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
      await firstClient.dispose();

      final jsonFile = fileSystem.file(
        '${workspace.directory.path}/$indexRootFolderName/$apexIndexFolderName/Greeter.json',
      );
      final modifiedAfterFirstRun = jsonFile.lastModifiedSync();

      // Second run -- nothing changed, so Greeter.json should be untouched.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final secondResult = createLspClient(fileSystem: fileSystem);
      final secondClient = secondResult.client..start();
      await secondClient.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
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
      'restart after modifying one file re-indexes only the changed file',
      () async {
        final fileSystem = MemoryFileSystem();
        final workspace = await createTestWorkspace(
          fileSystem: fileSystem,
          classFiles: [
            (name: 'Alpha.cls', source: 'public class Alpha {}'),
            (name: 'Beta.cls', source: 'public class Beta {}'),
          ],
        );

        // First run.
        final firstResult = createLspClient(fileSystem: fileSystem);
        final firstClient = firstResult.client..start();
        await firstClient.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: true,
        );
        await firstClient.dispose();

        final alphaJson = fileSystem.file(
          '${workspace.directory.path}/$indexRootFolderName/$apexIndexFolderName/Alpha.json',
        );
        final betaJson = fileSystem.file(
          '${workspace.directory.path}/$indexRootFolderName/$apexIndexFolderName/Beta.json',
        );
        final alphaModified = alphaJson.lastModifiedSync();
        final betaModified = betaJson.lastModifiedSync();

        // Touch only Beta.cls -- wait long enough for the filesystem to record
        // a distinct modification timestamp.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await fileSystem
            .file('${workspace.classesPath}/Beta.cls')
            .writeAsString('public class Beta { public String name; }');

        // Second run.
        final secondResult = createLspClient(fileSystem: fileSystem);
        final secondClient = secondResult.client..start();
        await secondClient.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: true,
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
        final workspace = await createTestWorkspace(
          fileSystem: fileSystem,
          classFiles: [
            (
              name: 'Season.cls',
              source: 'public enum Season { SPRING, SUMMER }',
            ),
          ],
        );

        // First run -- builds index.
        final firstResult = createLspClient(fileSystem: fileSystem);
        final firstClient = firstResult.client..start();
        await firstClient.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: true,
        );
        await firstClient.dispose();

        // Second run -- index already exists, should be reused.
        final secondResult = createLspClient(fileSystem: fileSystem);
        final secondClient = secondResult.client..start();
        await secondClient.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: true,
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
}
