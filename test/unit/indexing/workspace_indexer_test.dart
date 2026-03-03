import 'dart:convert';

import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/apex_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer/workspace_indexer.dart';
import 'package:apex_lsp/message.dart';

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
  group('WorkspaceIndexer', () {
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
      workspaceRoot
          .childFile('sfdx-project.json')
          .writeAsStringSync(
            jsonEncode({
              'packageDirectories': [
                {'path': 'force-app', 'default': true},
              ],
            }),
          );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);
      classesDir
          .childFile('Foo.cls')
          .writeAsStringSync('public class Foo { public void hello(){} }');

      final token = ProgressToken.string('test-token');
      final progressEvents = await indexer
          .index(
            InitializedParams([
              WorkspaceFolder(workspaceUri.toString(), 'repo'),
            ]),
            token: token,
          )
          .toList();

      expect(progressEvents, hasLength(2));
      expect(
        (progressEvents.first.value as WorkDoneProgressBegin).title,
        equals('Initializing Apex LSP'),
      );
      expect(
        (progressEvents.last.value as WorkDoneProgressEnd).message,
        equals('Indexing complete'),
      );

      final indexDir = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName);
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

    test('indexes multiple files in parallel', () async {
      workspaceRoot
          .childFile('sfdx-project.json')
          .writeAsStringSync(
            jsonEncode({
              'packageDirectories': [
                {'path': 'force-app', 'default': true},
              ],
            }),
          );

      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      final classDefinitions = [
        ('Alpha.cls', 'public class Alpha {}'),
        ('Beta.cls', 'public class Beta {}'),
        ('Gamma.cls', 'public class Gamma {}'),
        ('Delta.cls', 'public class Delta {}'),
        ('Epsilon.cls', 'public class Epsilon {}'),
      ];

      for (final (fileName, source) in classDefinitions) {
        classesDir.childFile(fileName).writeAsStringSync(source);
      }

      await indexer
          .index(
            InitializedParams([
              WorkspaceFolder(workspaceUri.toString(), 'repo'),
            ]),
            token: ProgressToken.string('test-token'),
          )
          .drain<void>();

      final indexDir = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName);
      expect(indexDir.existsSync(), isTrue);

      for (final (fileName, _) in classDefinitions) {
        final className = fileName.replaceAll('.cls', '');
        final metadataFile = indexDir.childFile('$className.json');
        expect(
          metadataFile.existsSync(),
          isTrue,
          reason: '$className.json should have been indexed',
        );
        expect(
          jsonDecode(metadataFile.readAsStringSync())['className'],
          equals(className),
        );
      }
    });

    test('skips indexing if no workspace folders provided', () async {
      final events = await indexer
          .index(
            InitializedParams(null),
            token: ProgressToken.string('test-token'),
          )
          .toList();
      expect(events, isEmpty);
    });
  });

  group('incremental indexing', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late WorkspaceIndexer indexer;
    late Directory workspaceRoot;
    late Uri workspaceUri;
    late Directory classesDir;

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
    });

    Future<void> runIndex() => indexer
        .index(
          InitializedParams([WorkspaceFolder(workspaceUri.toString(), 'repo')]),
          token: ProgressToken.string('test-token'),
        )
        .drain<void>();

    test('does not delete the index directory on re-index', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');

      await runIndex();

      final indexDir = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName);
      expect(indexDir.existsSync(), isTrue);

      indexDir.childFile('_sentinel.txt').writeAsStringSync('keep me');

      await runIndex();

      expect(indexDir.childFile('_sentinel.txt').existsSync(), isTrue);
    });

    test('skips re-indexing a file whose .json is up to date', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');

      await runIndex();

      final jsonFile = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName)
          .childFile('Foo.json');
      final firstModified = jsonFile.lastModifiedSync();

      await runIndex();

      expect(jsonFile.lastModifiedSync(), equals(firstModified));
    });

    test('re-indexes a file whose .cls is newer than its .json', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');

      await runIndex();

      final jsonFile = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName)
          .childFile('Foo.json');
      final firstModified = jsonFile.lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      classesDir
          .childFile('Foo.cls')
          .writeAsStringSync('public class Foo { public void newMethod() {} }');

      await runIndex();

      expect(jsonFile.lastModifiedSync().isAfter(firstModified), isTrue);
    });

    test('removes orphaned .json files with no matching .cls', () async {
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');
      classesDir.childFile('Bar.cls').writeAsStringSync('public class Bar {}');

      await runIndex();

      final indexDir = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName);
      expect(indexDir.childFile('Foo.json').existsSync(), isTrue);
      expect(indexDir.childFile('Bar.json').existsSync(), isTrue);

      classesDir.childFile('Bar.cls').deleteSync();

      await runIndex();

      expect(indexDir.childFile('Foo.json').existsSync(), isTrue);
      expect(indexDir.childFile('Bar.json').existsSync(), isFalse);
    });

    test(
      'only re-indexes stale files, leaving fresh .json files untouched',
      () async {
        classesDir
            .childFile('Foo.cls')
            .writeAsStringSync('public class Foo {}');
        classesDir
            .childFile('Bar.cls')
            .writeAsStringSync('public class Bar {}');

        await runIndex();

        final indexDir = workspaceRoot
            .childDirectory(indexRootFolderName)
            .childDirectory(apexIndexFolderName);
        final fooModified = indexDir.childFile('Foo.json').lastModifiedSync();
        final barModified = indexDir.childFile('Bar.json').lastModifiedSync();

        await Future<void>.delayed(const Duration(milliseconds: 10));
        classesDir
            .childFile('Bar.cls')
            .writeAsStringSync('public class Bar { public String name; }');

        await runIndex();

        expect(
          indexDir.childFile('Foo.json').lastModifiedSync(),
          equals(fooModified),
          reason: 'Foo.json should not be re-indexed',
        );
        expect(
          indexDir
              .childFile('Bar.json')
              .lastModifiedSync()
              .isAfter(barModified),
          isTrue,
          reason: 'Bar.json should have been re-indexed',
        );
      },
    );
  });

  group('reindexApexFile', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late Directory workspaceRoot;
    late Directory apexIndexDir;
    late Directory classesDir;

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

      classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);
    });

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

  group('reindexSObjectFile', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late Directory sobjectIndexDir;
    late Directory objectsDir;

    setUp(() {
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();

      final workspaceRoot = fs.directory('/repo')..createSync();

      sobjectIndexDir = fs.directory(
        fs.path.join(
          workspaceRoot.path,
          indexRootFolderName,
          sobjectIndexFolderName,
        ),
      )..createSync(recursive: true);

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

    group('from object-meta.xml', () {
      test('writes a JSON file when the object-meta.xml is saved', () async {
        final objectDir = createObjectDir('Account');

        await reindexSObjectFile(
          fileSystem: fs,
          platform: platform,
          file: objectDir.childFile('Account.object-meta.xml'),
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

          await reindexSObjectFile(
            fileSystem: fs,
            platform: platform,
            file: objectDir.childFile('Account.object-meta.xml'),
            indexDir: sobjectIndexDir,
          );

          final json =
              jsonDecode(
                    sobjectIndexDir
                        .childFile('Account.json')
                        .readAsStringSync(),
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

    group('from field-meta.xml', () {
      test(
        're-indexes the parent SObject when a field file is saved',
        () async {
          final objectDir = createObjectDir(
            'Account',
            fields: {'Industry__c': _industryFieldXml},
          );

          await reindexSObjectFile(
            fileSystem: fs,
            platform: platform,
            file: objectDir
                .childDirectory('fields')
                .childFile('Industry__c.field-meta.xml'),
            indexDir: sobjectIndexDir,
          );

          expect(
            sobjectIndexDir.childFile('Account.json').existsSync(),
            isTrue,
          );
        },
      );

      test('updated field content appears in the re-indexed JSON', () async {
        final objectDir = createObjectDir(
          'Account',
          fields: {'Industry__c': _industryFieldXml},
        );

        await reindexSObjectFile(
          fileSystem: fs,
          platform: platform,
          file: objectDir
              .childDirectory('fields')
              .childFile('Industry__c.field-meta.xml'),
          indexDir: sobjectIndexDir,
        );

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
  });
}
