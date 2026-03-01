import 'dart:convert';

import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

final class FakeLspPlatform implements LspPlatform {
  @override
  final bool isWindows = false;

  @override
  final String pathSeparator = '/';
}

const _accountObjectXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>Account</label>
  <pluralLabel>Accounts</pluralLabel>
</CustomObject>
''';

const _industryFieldXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Industry__c</fullName>
  <label>Industry</label>
  <type>Picklist</type>
</CustomField>
''';

void main() {
  late FileSystem fs;
  late FakeLspPlatform platform;
  late WorkspaceIndexer indexer;
  late Directory workspaceRoot;
  late Uri workspaceUri;
  late Directory classesDir;
  late Directory objectsDir;

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

    workspaceRoot
        .childFile('sfdx-project.json')
        .writeAsStringSync(
          jsonEncode({
            'packageDirectories': [
              {'path': 'force-app', 'default': true},
            ],
          }),
        );

    classesDir = fs.directory('/repo/force-app/main/default/classes')
      ..createSync(recursive: true);

    objectsDir = fs.directory('/repo/force-app/main/default/objects')
      ..createSync(recursive: true);
  });

  Future<void> runIndex() => indexer
      .index(
        InitializedParams([WorkspaceFolder(workspaceUri.toString(), 'repo')]),
        token: ProgressToken.string('test-token'),
      )
      .drain<void>();

  Directory apexIndexDir() => workspaceRoot
      .childDirectory(indexRootFolderName)
      .childDirectory(apexIndexFolderName);

  Directory sobjectIndexDir() => workspaceRoot
      .childDirectory(indexRootFolderName)
      .childDirectory(sobjectIndexFolderName);

  void createObjectDir(
    String objectName, {
    Map<String, String> fields = const {},
  }) {
    final dir = objectsDir.childDirectory(objectName)..createSync();
    dir
        .childFile('$objectName.object-meta.xml')
        .writeAsStringSync(_accountObjectXml);
    if (fields.isNotEmpty) {
      final fieldsDir = dir.childDirectory('fields')..createSync();
      for (final entry in fields.entries) {
        fieldsDir
            .childFile('${entry.key}.field-meta.xml')
            .writeAsStringSync(entry.value);
      }
    }
  }

  group('WorkspaceIndexer.reindexFile', () {
    test('re-indexes a saved .cls file', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');
      await runIndex();

      final jsonFile = apexIndexDir().childFile('Foo.json');
      final firstModified = jsonFile.lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      classesDir
          .childFile('Foo.cls')
          .writeAsStringSync('public class Foo { public void newMethod() {} }');

      await indexer.reindexFile(
        Uri.file('/repo/force-app/main/default/classes/Foo.cls'),
      );

      expect(jsonFile.lastModifiedSync().isAfter(firstModified), isTrue);
    });

    test('re-indexes a saved .object-meta.xml file', () async {
      createObjectDir('Account');
      await runIndex();

      final jsonFile = sobjectIndexDir().childFile('Account.json');
      final firstModified = jsonFile.lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Touch the object meta file to simulate a save.
      objectsDir
          .childDirectory('Account')
          .childFile('Account.object-meta.xml')
          .writeAsStringSync(_accountObjectXml);

      await indexer.reindexFile(
        Uri.file(
          '/repo/force-app/main/default/objects/Account/Account.object-meta.xml',
        ),
      );

      expect(jsonFile.lastModifiedSync().isAfter(firstModified), isTrue);
    });

    test(
      're-indexes the parent SObject when a .field-meta.xml is saved',
      () async {
        createObjectDir('Account', fields: {'Industry__c': _industryFieldXml});
        await runIndex();

        final jsonFile = sobjectIndexDir().childFile('Account.json');
        final firstModified = jsonFile.lastModifiedSync();

        await Future<void>.delayed(const Duration(milliseconds: 10));
        objectsDir
            .childDirectory('Account')
            .childDirectory('fields')
            .childFile('Industry__c.field-meta.xml')
            .writeAsStringSync(_industryFieldXml);

        await indexer.reindexFile(
          Uri.file(
            '/repo/force-app/main/default/objects/Account/fields/Industry__c.field-meta.xml',
          ),
        );

        expect(jsonFile.lastModifiedSync().isAfter(firstModified), isTrue);
      },
    );

    test('is a no-op for a file outside all known workspace roots', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');
      await runIndex();

      final jsonFile = apexIndexDir().childFile('Foo.json');
      final firstModified = jsonFile.lastModifiedSync();

      // File belongs to a completely different workspace.
      await indexer.reindexFile(
        Uri.file('/other-repo/force-app/main/default/classes/Foo.cls'),
      );

      expect(jsonFile.lastModifiedSync(), equals(firstModified));
    });

    test('is a no-op for an unrecognized file extension', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');
      await runIndex();

      final jsonFile = apexIndexDir().childFile('Foo.json');
      final firstModified = jsonFile.lastModifiedSync();

      await indexer.reindexFile(
        Uri.file('/repo/force-app/main/default/classes/README.md'),
      );

      expect(jsonFile.lastModifiedSync(), equals(firstModified));
    });
  });
}
