import 'dart:io';

import 'package:test/test.dart';

import '../../support/test_workspace.dart';

void main() {
  group('createTestWorkspace with SObject files', () {
    late TestWorkspace workspace;

    setUp(() async {
      workspace = await createTestWorkspace(
        objectFiles: [
          (
            objectName: 'Account',
            objectMetaXml: '''<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>Account</label>
</CustomObject>''',
            fields: [
              (
                name: 'Industry__c',
                xml: '''<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Industry__c</fullName>
  <label>Industry</label>
  <type>Picklist</type>
</CustomField>''',
              ),
            ],
          ),
        ],
      );
    });

    tearDown(() async => deleteTestWorkspace(workspace));

    test('creates object meta xml file', () {
      final objectMetaFile = File(
        '${workspace.objectsPath}/Account/Account.object-meta.xml',
      );
      expect(objectMetaFile.existsSync(), isTrue);
    });

    test('creates field meta xml file', () {
      final fieldFile = File(
        '${workspace.objectsPath}/Account/fields/Industry__c.field-meta.xml',
      );
      expect(fieldFile.existsSync(), isTrue);
    });

    test('objectsPath points to the objects directory', () {
      final objectsDir = Directory(workspace.objectsPath);
      expect(objectsDir.existsSync(), isTrue);
    });
  });
}
