import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

final class FakeLspPlatform implements LspPlatform {
  FakeLspPlatform({this.isWindows = false, this.pathSeparator = '/'});

  @override
  final bool isWindows;

  @override
  final String pathSeparator;
}

void main() {
  group('Indexer', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late WorkspaceIndexer indexer;
    late Directory workspaceRoot;
    late Uri workspaceUri;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      indexer = WorkspaceIndexer(
        sfdxWorkspaceLocator: SfdxWorkspaceLocator(
          fileSystem: fs,
          platform: platform,
        ),
        fileSystem: fs,
        platform: platform,
      );

      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);
    });

    test('indexes Apex files and generates metadata', () async {
      final projectFile = workspaceRoot.childFile('sfdx-project.json');
      projectFile.writeAsStringSync(
        jsonEncode({
          'packageDirectories': [
            {'path': 'force-app', 'default': true},
          ],
        }),
      );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      final fooFile = classesDir.childFile('Foo.cls');
      fooFile.writeAsStringSync('public class Foo { public void hello(){} }');

      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'repo'),
      ]);

      final token = ProgressToken.string('test-token');
      final progressEvents = await indexer.index(params, token: token).toList();

      expect(progressEvents, isNotEmpty);
      expect(
        (progressEvents.first.value as WorkDoneProgressBegin).title,
        equals('Indexing Apex files'),
      );
      expect(
        (progressEvents.last.value as WorkDoneProgressEnd).message,
        equals('Indexing complete'),
      );

      final indexDir = workspaceRoot.childDirectory('.sf-zed');
      expect(indexDir.existsSync(), isTrue);

      final metadataFile = indexDir.childFile('Foo.json');
      expect(metadataFile.existsSync(), isTrue);

      final metadata = jsonDecode(metadataFile.readAsStringSync());
      expect(metadata['className'], equals('Foo'));
      expect(
        metadata['source']['relativePath'],
        equals('force-app/main/default/classes/Foo.cls'),
      );
    });

    test('skips indexing if no workspace folders provided', () async {
      final params = InitializedParams(null);
      final events = await indexer
          .index(params, token: ProgressToken.string('test-token'))
          .toList();
      expect(events, isEmpty);
    });
  });

  group('IndexRepository', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late Directory workspaceRoot;
    late Uri workspaceUri;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);
    });

    /// Runs the Indexer to produce `.sf-zed` metadata from `.cls` files,
    /// then returns an [IndexRepository] pointed at the same workspace.
    Future<IndexRepository> indexAndCreateRepository({
      required Map<String, String> classFiles,
    }) async {
      final projectFile = workspaceRoot.childFile('sfdx-project.json');
      projectFile.writeAsStringSync(
        jsonEncode({
          'packageDirectories': [
            {'path': 'force-app', 'default': true},
          ],
        }),
      );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      for (final entry in classFiles.entries) {
        classesDir.childFile(entry.key).writeAsStringSync(entry.value);
      }

      final indexer = WorkspaceIndexer(
        sfdxWorkspaceLocator: SfdxWorkspaceLocator(
          fileSystem: fs,
          platform: platform,
        ),
        fileSystem: fs,
        platform: platform,
      );

      await indexer
          .index(
            InitializedParams([
              WorkspaceFolder(workspaceUri.toString(), 'repo'),
            ]),
            token: ProgressToken.string('test-token'),
          )
          .drain<void>();

      return indexer.getIndexLoader();
    }

    group('enums', () {
      test('indexes top level enums', () async {
        final repository = await indexAndCreateRepository(
          classFiles: {
            'Season.cls': 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          },
        );

        final result = await repository.getIndexedType('Season');

        expect(result, isA<IndexedEnum>());
        expect(result!.name, equals(DeclarationName('Season')));
      });

      test('indexes enum values', () async {
        final repository = await indexAndCreateRepository(
          classFiles: {
            'Season.cls': 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          },
        );

        final result = await repository.getIndexedType('Season') as IndexedEnum;

        expect(
          result.values.map((value) => value.name.value).toList(),
          equals(['SPRING', 'SUMMER', 'FALL', 'WINTER']),
        );
      });
    });
  });
}
