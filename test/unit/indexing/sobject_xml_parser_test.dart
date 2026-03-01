import 'package:apex_lsp/indexing/sobject_xml_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseObjectMetaXml', () {
    test('parses label, pluralLabel, and description', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>Account</label>
  <pluralLabel>Accounts</pluralLabel>
  <description>Standard Account object</description>
</CustomObject>
''';

      final result = parseObjectMetaXml('Account', xml);

      expect(result.apiName, equals('Account'));
      expect(result.label, equals('Account'));
      expect(result.pluralLabel, equals('Accounts'));
      expect(result.description, equals('Standard Account object'));
    });

    test('returns null for optional fields when elements are absent', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
</CustomObject>
''';

      final result = parseObjectMetaXml('MyObj__c', xml);

      expect(result.apiName, equals('MyObj__c'));
      expect(result.label, isNull);
      expect(result.pluralLabel, isNull);
      expect(result.description, isNull);
    });

    test('uses apiName argument regardless of XML content', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>Something</label>
</CustomObject>
''';

      final result = parseObjectMetaXml('Opportunity', xml);

      expect(result.apiName, equals('Opportunity'));
    });

    test('starts with an empty fields list', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">
</CustomObject>
''';

      final result = parseObjectMetaXml('Account', xml);

      expect(result.fields, isEmpty);
    });

    test('handles a namespace variant without a namespace URI', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomObject>
  <label>Contact</label>
  <pluralLabel>Contacts</pluralLabel>
</CustomObject>
''';

      final result = parseObjectMetaXml('Contact', xml);

      expect(result.label, equals('Contact'));
      expect(result.pluralLabel, equals('Contacts'));
    });
  });

  group('parseFieldMetaXml', () {
    test('parses fullName, label, type, and description', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Industry__c</fullName>
  <label>Industry</label>
  <type>Picklist</type>
  <description>Industry classification</description>
</CustomField>
''';

      final result = parseFieldMetaXml(xml);

      expect(result, isNotNull);
      expect(result!.apiName, equals('Industry__c'));
      expect(result.label, equals('Industry'));
      expect(result.type, equals('Picklist'));
      expect(result.description, equals('Industry classification'));
    });

    test('returns null for optional fields when elements are absent', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <fullName>Simple__c</fullName>
</CustomField>
''';

      final result = parseFieldMetaXml(xml);

      expect(result, isNotNull);
      expect(result!.apiName, equals('Simple__c'));
      expect(result.label, isNull);
      expect(result.type, isNull);
      expect(result.description, isNull);
    });

    test('returns null when fullName element is missing', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
  <label>No Name</label>
</CustomField>
''';

      final result = parseFieldMetaXml(xml);

      expect(result, isNull);
    });

    test('returns null for empty XML string', () {
      final result = parseFieldMetaXml('');

      expect(result, isNull);
    });

    test('returns null for malformed XML', () {
      final result = parseFieldMetaXml('<CustomField><unclosed>');

      expect(result, isNull);
    });

    test('handles a namespace variant without a namespace URI', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<CustomField>
  <fullName>Name__c</fullName>
  <type>Text</type>
</CustomField>
''';

      final result = parseFieldMetaXml(xml);

      expect(result, isNotNull);
      expect(result!.apiName, equals('Name__c'));
      expect(result.type, equals('Text'));
    });
  });
}
