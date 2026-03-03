import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/workspace_indexer/orphan_remover.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/fake_platform.dart';

void main() {
  late FileSystem fs;
  late FakeLspPlatform platform;
  late Directory workspaceRoot;
  late Directory apexIndexDir;
  late Directory sobjectIndexDir;

  setUp(() {
    fs = MemoryFileSystem();
    platform = FakeLspPlatform();

    workspaceRoot = fs.directory('/repo')..createSync();

    apexIndexDir = fs.directory(
      fs.path.join(
        workspaceRoot.path,
        indexRootFolderName,
        apexIndexFolderName,
      ),
    )..createSync(recursive: true);

    sobjectIndexDir = fs.directory(
      fs.path.join(
        workspaceRoot.path,
        indexRootFolderName,
        sobjectIndexFolderName,
      ),
    )..createSync(recursive: true);
  });

  group('deleteOrphanForFile', () {
    test('removes the JSON for a deleted .cls file', () async {
      apexIndexDir.childFile('Foo.json').writeAsStringSync('{}');

      await deleteOrphanForFile(
        fileSystem: fs,
        platform: platform,
        deletedFile: fs.file('/repo/force-app/main/default/classes/Foo.cls'),
        apexIndexDir: apexIndexDir,
        sobjectIndexDir: sobjectIndexDir,
      );

      expect(apexIndexDir.childFile('Foo.json').existsSync(), isFalse);
    });

    test(
      'does not remove other Apex JSON files when one class is deleted',
      () async {
        apexIndexDir.childFile('Foo.json').writeAsStringSync('{}');
        apexIndexDir.childFile('Bar.json').writeAsStringSync('{}');

        await deleteOrphanForFile(
          fileSystem: fs,
          platform: platform,
          deletedFile: fs.file('/repo/force-app/main/default/classes/Foo.cls'),
          apexIndexDir: apexIndexDir,
          sobjectIndexDir: sobjectIndexDir,
        );

        expect(apexIndexDir.childFile('Foo.json').existsSync(), isFalse);
        expect(apexIndexDir.childFile('Bar.json').existsSync(), isTrue);
      },
    );

    test('removes the JSON for a deleted .object-meta.xml file', () async {
      sobjectIndexDir.childFile('Account.json').writeAsStringSync('{}');

      await deleteOrphanForFile(
        fileSystem: fs,
        platform: platform,
        deletedFile: fs.file(
          '/repo/force-app/main/default/objects/Account/Account.object-meta.xml',
        ),
        apexIndexDir: apexIndexDir,
        sobjectIndexDir: sobjectIndexDir,
      );

      expect(sobjectIndexDir.childFile('Account.json').existsSync(), isFalse);
    });

    test(
      'reindexes the parent SObject when a .field-meta.xml is deleted',
      () async {
        // Simulate the on-disk state after the field file has been deleted:
        // the object dir and its meta file still exist, but the field is gone.
        final objectDir = fs.directory(
          '/repo/force-app/main/default/objects/Account',
        )..createSync(recursive: true);
        objectDir
            .childFile('Account.object-meta.xml')
            .writeAsStringSync(
              '<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">'
              '<label>Account</label>'
              '<pluralLabel>Accounts</pluralLabel>'
              '</CustomObject>',
            );

        // Pre-populate a stale index entry so we can verify it gets replaced.
        sobjectIndexDir
            .childFile('Account.json')
            .writeAsStringSync('{"stale":true}');

        await deleteOrphanForFile(
          fileSystem: fs,
          platform: platform,
          deletedFile: fs.file(
            '/repo/force-app/main/default/objects/Account/fields/Industry__c.field-meta.xml',
          ),
          apexIndexDir: apexIndexDir,
          sobjectIndexDir: sobjectIndexDir,
        );

        // The JSON must still exist (SObject itself was not deleted).
        expect(sobjectIndexDir.childFile('Account.json').existsSync(), isTrue);
        // And it must no longer be stale (it was re-indexed).
        final content = sobjectIndexDir
            .childFile('Account.json')
            .readAsStringSync();
        expect(content, isNot(contains('"stale":true')));
      },
    );

    test(
      'is a no-op for .field-meta.xml deletion when the object dir is missing',
      () async {
        // No object directory on disk, so nothing to re-index.
        await deleteOrphanForFile(
          fileSystem: fs,
          platform: platform,
          deletedFile: fs.file(
            '/repo/force-app/main/default/objects/Ghost/fields/Field__c.field-meta.xml',
          ),
          apexIndexDir: apexIndexDir,
          sobjectIndexDir: sobjectIndexDir,
        );

        // No crash and no stale JSON created.
        expect(sobjectIndexDir.listSync(), isEmpty);
      },
    );

    test('is a no-op for an unrecognized file extension', () async {
      apexIndexDir.childFile('Foo.json').writeAsStringSync('{}');

      await deleteOrphanForFile(
        fileSystem: fs,
        platform: platform,
        deletedFile: fs.file('/repo/README.md'),
        apexIndexDir: apexIndexDir,
        sobjectIndexDir: sobjectIndexDir,
      );

      expect(apexIndexDir.childFile('Foo.json').existsSync(), isTrue);
    });
  });
}
