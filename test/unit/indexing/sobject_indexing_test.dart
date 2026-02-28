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
  FakeLspPlatform({this.isWindows = false, this.pathSeparator = '/'});

  @override
  final bool isWindows;

  @override
  final String pathSeparator;
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
  late WorkspaceIndexer indexer;
  late Directory workspaceRoot;
  late Uri workspaceUri;
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

    objectsDir = fs.directory('/repo/force-app/main/default/objects')
      ..createSync(recursive: true);
  });

  Future<void> runIndex() => indexer
      .index(
        InitializedParams([WorkspaceFolder(workspaceUri.toString(), 'repo')]),
        token: ProgressToken.string('test-token'),
      )
      .drain<void>();

  Directory sobjectIndexDir() => workspaceRoot
      .childDirectory(indexRootFolderName)
      .childDirectory(sobjectIndexFolderName);

  void createObjectDir(
    String objectName, {
    String objectXml = _accountObjectXml,
    Map<String, String> fields = const {},
  }) {
    final dir = objectsDir.childDirectory(objectName)..createSync();
    dir.childFile('$objectName.object-meta.xml').writeAsStringSync(objectXml);

    if (fields.isNotEmpty) {
      final fieldsDir = dir.childDirectory('fields')..createSync();
      for (final entry in fields.entries) {
        fieldsDir
            .childFile('${entry.key}.field-meta.xml')
            .writeAsStringSync(entry.value);
      }
    }
  }

  group('SObject indexer', () {
    test(
      'writes a JSON file to .sf-zed/sobjects/ for a discovered object',
      () async {
        createObjectDir('Account');

        await runIndex();

        expect(sobjectIndexDir().existsSync(), isTrue);
        expect(
          sobjectIndexDir().childFile('Account.json').existsSync(),
          isTrue,
        );
      },
    );

    test('JSON contains correct schema fields', () async {
      createObjectDir('Account', fields: {'Industry__c': _industryFieldXml});

      await runIndex();

      final json =
          jsonDecode(
                sobjectIndexDir().childFile('Account.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(json['schemaVersion'], equals(1));
      expect(json['objectApiName'], equals('Account'));
      expect(json['source'], isA<Map<String, dynamic>>());
      expect(json['objectMetadata'], isA<Map<String, dynamic>>());
    });

    test('objectMetadata contains parsed object-level fields', () async {
      createObjectDir('Account');

      await runIndex();

      final json =
          jsonDecode(
                sobjectIndexDir().childFile('Account.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      final metadata = json['objectMetadata'] as Map<String, dynamic>;
      expect(metadata['apiName'], equals('Account'));
      expect(metadata['label'], equals('Account'));
      expect(metadata['pluralLabel'], equals('Accounts'));
    });

    test('objectMetadata contains parsed field metadata', () async {
      createObjectDir('Account', fields: {'Industry__c': _industryFieldXml});

      await runIndex();

      final json =
          jsonDecode(
                sobjectIndexDir().childFile('Account.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      final metadata = json['objectMetadata'] as Map<String, dynamic>;
      final fields = metadata['fields'] as List<dynamic>;
      expect(fields, hasLength(1));

      final field = fields.first as Map<String, dynamic>;
      expect(field['apiName'], equals('Industry__c'));
      expect(field['label'], equals('Industry'));
      expect(field['type'], equals('Picklist'));
    });

    test('indexes multiple fields from the fields/ subdirectory', () async {
      createObjectDir(
        'Account',
        fields: {
          'Industry__c': _industryFieldXml,
          'Rating__c': _ratingFieldXml,
        },
      );

      await runIndex();

      final json =
          jsonDecode(
                sobjectIndexDir().childFile('Account.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final metadata = json['objectMetadata'] as Map<String, dynamic>;
      final fields = metadata['fields'] as List<dynamic>;

      expect(fields, hasLength(2));
      final apiNames = fields
          .cast<Map<String, dynamic>>()
          .map((f) => f['apiName'])
          .toSet();
      expect(apiNames, containsAll(['Industry__c', 'Rating__c']));
    });

    test('skips directory that has no object-meta.xml file', () async {
      // Create a directory without the required object-meta.xml.
      objectsDir.childDirectory('NoMeta').createSync();

      await runIndex();

      expect(sobjectIndexDir().childFile('NoMeta.json').existsSync(), isFalse);
    });

    test('skips re-indexing when JSON is newer than all XML files', () async {
      createObjectDir('Account');
      await runIndex();

      final jsonFile = sobjectIndexDir().childFile('Account.json');
      final firstModified = jsonFile.lastModifiedSync();

      await runIndex();

      expect(jsonFile.lastModifiedSync(), equals(firstModified));
    });

    test('re-indexes when a field file is newer than the JSON', () async {
      createObjectDir('Account', fields: {'Industry__c': _industryFieldXml});
      await runIndex();

      final jsonFile = sobjectIndexDir().childFile('Account.json');
      final firstModified = jsonFile.lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      objectsDir
          .childDirectory('Account')
          .childDirectory('fields')
          .childFile('Industry__c.field-meta.xml')
          .writeAsStringSync(_ratingFieldXml);

      await runIndex();

      expect(jsonFile.lastModifiedSync().isAfter(firstModified), isTrue);
    });

    test('removes orphaned JSON when object directory is deleted', () async {
      createObjectDir('Account');
      createObjectDir('Contact');
      await runIndex();

      expect(sobjectIndexDir().childFile('Account.json').existsSync(), isTrue);
      expect(sobjectIndexDir().childFile('Contact.json').existsSync(), isTrue);

      objectsDir.childDirectory('Contact').deleteSync(recursive: true);
      await runIndex();

      expect(sobjectIndexDir().childFile('Account.json').existsSync(), isTrue);
      expect(sobjectIndexDir().childFile('Contact.json').existsSync(), isFalse);
    });

    test('indexes both Apex classes and SObjects in the same run', () async {
      final classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);
      classesDir.childFile('Foo.cls').writeAsStringSync('public class Foo {}');
      createObjectDir('Account');

      await runIndex();

      final apexIndexDir = workspaceRoot
          .childDirectory(indexRootFolderName)
          .childDirectory(apexIndexFolderName);
      expect(apexIndexDir.childFile('Foo.json').existsSync(), isTrue);
      expect(sobjectIndexDir().childFile('Account.json').existsSync(), isTrue);
    });
  });
}
