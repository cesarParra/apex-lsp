import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_matchers.dart';
import '../../support/lsp_client.dart';

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
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
        await Future<void>.delayed(const Duration(milliseconds: 1100));
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
}
