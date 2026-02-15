import 'dart:convert';

import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/indexer.dart';
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
    late ApexIndexer indexer;
    late Directory workspaceRoot;
    late Uri workspaceUri;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      indexer = ApexIndexer(fileSystem: fs, platform: platform);

      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);
    });

    test('indexes Apex files and generates metadata', () async {
      // 1. Setup workspace structure
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

      // 2. Run indexing
      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'repo'),
      ]);

      final token = ProgressToken.string('test-token');
      final progressEvents = await indexer.index(params, token: token).toList();

      // 3. Verify progress notifications
      expect(progressEvents, isNotEmpty);
      expect(
        (progressEvents.first.value as WorkDoneProgressBegin).title,
        equals('Indexing Apex files'),
      );
      expect(
        (progressEvents.last.value as WorkDoneProgressEnd).message,
        equals('Indexing complete'),
      );

      // 4. Verify generated metadata
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

    test(
      'loadWorkspaceClassInfo returns cached mirror after indexing',
      () async {
        // 1. Setup workspace structure
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
        fooFile.writeAsStringSync('public class Foo {}');

        // 2. Run indexing
        await indexer
            .index(
              InitializedParams([
                WorkspaceFolder(workspaceUri.toString(), 'repo'),
              ]),
              token: ProgressToken.string('test-token'),
            )
            .drain<void>();

        // 3. Verify lookup
        final mirror = await indexer.getIndexedClassInfo('Foo');
        expect(mirror, isNotNull);
        expect(mirror!.typeMirror.name, equals('Foo'));

        // Verify it's in the indexed class names set
        expect(indexer.indexedClassNames.contains('Foo'), isTrue);
      },
    );

    test('handles multiple workspace roots', () async {
      final root2 = fs.directory('/repo2')..createSync();
      final uri2 = Uri.directory(root2.path);

      // Create index folders in both
      for (final root in [workspaceRoot, root2]) {
        root.childDirectory('.sf-zed').createSync();
        final sfdx = root.childFile('sfdx-project.json');
        sfdx.writeAsStringSync(
          jsonEncode({
            'packageDirectories': [
              {'path': 'src'},
            ],
          }),
        );
      }

      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'r1'),
        WorkspaceFolder(uri2.toString(), 'r2'),
      ]);

      await indexer
          .index(params, token: ProgressToken.string('test-token'))
          .drain<void>();

      // Verify both are tracked
      // We check this indirectly via indexedClassNames which scans all roots
      workspaceRoot.childDirectory('.sf-zed').childFile('A.json').createSync();
      root2.childDirectory('.sf-zed').childFile('B.json').createSync();

      expect(indexer.indexedClassNames, containsAll(['A', 'B']));
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

      final indexer = Indexer(
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
