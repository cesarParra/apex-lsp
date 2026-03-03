import 'dart:convert';

import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/workspace_indexer/apex_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/fake_platform.dart';

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

const _ratingFieldXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Rating__c</fullName>
  <label>Rating</label>
  <type>Text</type>
</CustomField>
''';

void main() {
  late FileSystem fs;
  late FakeLspPlatform platform;
  late Directory workspaceRoot;
  late Directory apexIndexDir;
  late Directory sobjectIndexDir;
  late Directory classesDir;
  late Directory objectsDir;

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

    classesDir = fs.directory('/repo/force-app/main/default/classes')
      ..createSync(recursive: true);

    objectsDir = fs.directory('/repo/force-app/main/default/objects')
      ..createSync(recursive: true);
  });

  Directory createObjectDir(
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

    return dir;
  }

  group('reindexApexFile', () {
    test('writes a JSON file for a saved .cls file', () async {
      final clsFile = classesDir.childFile('Foo.cls')
        ..writeAsStringSync('public class Foo {}');

      await reindexApexFile(
        fileSystem: fs,
        platform: platform,
        workspaceRoot: Uri.directory(workspaceRoot.path),
        file: clsFile,
        indexDir: apexIndexDir,
      );

      expect(apexIndexDir.childFile('Foo.json').existsSync(), isTrue);
    });

    test('updates the JSON when the .cls content changes', () async {
      final clsFile = classesDir.childFile('Foo.cls')
        ..writeAsStringSync('public class Foo {}');

      await reindexApexFile(
        fileSystem: fs,
        platform: platform,
        workspaceRoot: Uri.directory(workspaceRoot.path),
        file: clsFile,
        indexDir: apexIndexDir,
      );

      final firstModified = apexIndexDir
          .childFile('Foo.json')
          .lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      clsFile.writeAsStringSync(
        'public class Foo { public void newMethod() {} }',
      );

      await reindexApexFile(
        fileSystem: fs,
        platform: platform,
        workspaceRoot: Uri.directory(workspaceRoot.path),
        file: clsFile,
        indexDir: apexIndexDir,
      );

      expect(
        apexIndexDir
            .childFile('Foo.json')
            .lastModifiedSync()
            .isAfter(firstModified),
        isTrue,
      );
    });

    test('does not touch other JSON files in the index directory', () async {
      // A JSON for a sibling class must survive a re-index of Foo.
      apexIndexDir.childFile('Bar.json').writeAsStringSync('{}');

      final clsFile = classesDir.childFile('Foo.cls')
        ..writeAsStringSync('public class Foo {}');

      await reindexApexFile(
        fileSystem: fs,
        platform: platform,
        workspaceRoot: Uri.directory(workspaceRoot.path),
        file: clsFile,
        indexDir: apexIndexDir,
      );

      expect(apexIndexDir.childFile('Foo.json').existsSync(), isTrue);
      expect(apexIndexDir.childFile('Bar.json').existsSync(), isTrue);
    });
  });

  group('reindexSObjectFile from object-meta.xml', () {
    test('writes a JSON file when the object-meta.xml is saved', () async {
      final objectDir = createObjectDir('Account');
      final objectMetaFile = objectDir.childFile('Account.object-meta.xml');

      await reindexSObjectFile(
        fileSystem: fs,
        platform: platform,
        file: objectMetaFile,
        indexDir: sobjectIndexDir,
      );

      expect(sobjectIndexDir.childFile('Account.json').existsSync(), isTrue);
    });

    test(
      'JSON reflects the field metadata from the object directory',
      () async {
        final objectDir = createObjectDir(
          'Account',
          fields: {'Industry__c': _industryFieldXml},
        );
        final objectMetaFile = objectDir.childFile('Account.object-meta.xml');

        await reindexSObjectFile(
          fileSystem: fs,
          platform: platform,
          file: objectMetaFile,
          indexDir: sobjectIndexDir,
        );

        final json =
            jsonDecode(
                  sobjectIndexDir.childFile('Account.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final fields =
            (json['objectMetadata'] as Map<String, dynamic>)['fields']
                as List<dynamic>;

        expect(fields, hasLength(1));
        expect(
          (fields.first as Map<String, dynamic>)['apiName'],
          'Industry__c',
        );
      },
    );

    test('does not touch other JSON files in the index directory', () async {
      sobjectIndexDir.childFile('Contact.json').writeAsStringSync('{}');

      final objectDir = createObjectDir('Account');
      await reindexSObjectFile(
        fileSystem: fs,
        platform: platform,
        file: objectDir.childFile('Account.object-meta.xml'),
        indexDir: sobjectIndexDir,
      );

      expect(sobjectIndexDir.childFile('Account.json').existsSync(), isTrue);
      expect(sobjectIndexDir.childFile('Contact.json').existsSync(), isTrue);
    });
  });

  group('reindexSObjectFile from field-meta.xml', () {
    test('re-indexes the parent SObject when a field file is saved', () async {
      final objectDir = createObjectDir(
        'Account',
        fields: {'Industry__c': _industryFieldXml},
      );
      final fieldFile = objectDir
          .childDirectory('fields')
          .childFile('Industry__c.field-meta.xml');

      await reindexSObjectFile(
        fileSystem: fs,
        platform: platform,
        file: fieldFile,
        indexDir: sobjectIndexDir,
      );

      expect(sobjectIndexDir.childFile('Account.json').existsSync(), isTrue);
    });

    test('updated field content appears in the re-indexed JSON', () async {
      final objectDir = createObjectDir(
        'Account',
        fields: {'Industry__c': _industryFieldXml},
      );

      // Seed initial JSON via the first field.
      await reindexSObjectFile(
        fileSystem: fs,
        platform: platform,
        file: objectDir
            .childDirectory('fields')
            .childFile('Industry__c.field-meta.xml'),
        indexDir: sobjectIndexDir,
      );

      // Add a second field and simulate saving it.
      objectDir
          .childDirectory('fields')
          .childFile('Rating__c.field-meta.xml')
          .writeAsStringSync(_ratingFieldXml);

      await reindexSObjectFile(
        fileSystem: fs,
        platform: platform,
        file: objectDir
            .childDirectory('fields')
            .childFile('Rating__c.field-meta.xml'),
        indexDir: sobjectIndexDir,
      );

      final json =
          jsonDecode(
                sobjectIndexDir.childFile('Account.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final fields =
          (json['objectMetadata'] as Map<String, dynamic>)['fields']
              as List<dynamic>;

      final apiNames = fields
          .cast<Map<String, dynamic>>()
          .map((f) => f['apiName'])
          .toSet();
      expect(apiNames, containsAll(['Industry__c', 'Rating__c']));
    });
  });
}
