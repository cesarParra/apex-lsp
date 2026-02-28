import 'dart:io';

typedef ClassFile = ({String name, String source});

typedef SObjectFile = ({
  String objectName,
  String objectMetaXml,
  List<({String name, String xml})> fields,
});

/// A temporary SFDX workspace for integration tests.
final class TestWorkspace {
  final Directory directory;

  TestWorkspace(this.directory);

  Uri get uri => Uri.directory(directory.path);

  String get classesPath => '${directory.path}/force-app/main/default/classes';

  String get objectsPath => '${directory.path}/force-app/main/default/objects';
}

/// Creates a temporary SFDX workspace with the given Apex class files and
/// SObject metadata files.
///
/// The workspace includes an `sfdx-project.json` copied from fixtures,
/// the standard `force-app/main/default/classes` directory, and optionally
/// `force-app/main/default/objects/<ObjectName>/` directories.
Future<TestWorkspace> createTestWorkspace({
  List<ClassFile> classFiles = const [],
  List<SObjectFile> objectFiles = const [],
}) async {
  final directory = await Directory.systemTemp.createTemp('apex-lsp-it-');

  final sfdxProject = File('${directory.path}/sfdx-project.json');
  await sfdxProject.writeAsString(
    await readFixture('initialize_and_completion/sfdx-project.json'),
  );

  final classesDir = Directory(
    '${directory.path}/force-app/main/default/classes',
  );
  await classesDir.create(recursive: true);

  for (final classFile in classFiles) {
    final file = File('${classesDir.path}/${classFile.name}');
    await file.writeAsString(classFile.source);
  }

  for (final objectFile in objectFiles) {
    final objectDir = Directory(
      '${directory.path}/force-app/main/default/objects/${objectFile.objectName}',
    );
    await objectDir.create(recursive: true);

    final objectMetaFile = File(
      '${objectDir.path}/${objectFile.objectName}.object-meta.xml',
    );
    await objectMetaFile.writeAsString(objectFile.objectMetaXml);

    if (objectFile.fields.isNotEmpty) {
      final fieldsDir = Directory('${objectDir.path}/fields');
      await fieldsDir.create();

      for (final field in objectFile.fields) {
        final fieldFile = File(
          '${fieldsDir.path}/${field.name}.field-meta.xml',
        );
        await fieldFile.writeAsString(field.xml);
      }
    }
  }

  return TestWorkspace(directory);
}

/// Deletes a temporary test workspace.
Future<void> deleteTestWorkspace(TestWorkspace workspace) async {
  await workspace.directory.delete(recursive: true);
}

/// Reads a fixture file relative to `test/fixtures/`.
Future<String> readFixture(String relativePath) {
  return File('test/fixtures/$relativePath').readAsString();
}
