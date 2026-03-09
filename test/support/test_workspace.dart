import 'dart:io' as io;

import 'package:file/file.dart';

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
/// The workspace includes an `sfdx-project.json`, the standard
/// `force-app/main/default/classes` directory, and optionally
/// `force-app/main/default/objects/<ObjectName>/` directories.
///
/// All files are written into the provided [fileSystem], using a fixed
/// `/workspace` root path.
Future<TestWorkspace> createTestWorkspace({
  required FileSystem fileSystem,
  List<ClassFile> classFiles = const [],
  List<SObjectFile> objectFiles = const [],
}) async {
  final directory = fileSystem.directory('/workspace');
  await directory.create(recursive: true);

  final sfdxProject = fileSystem.file('${directory.path}/sfdx-project.json');
  await sfdxProject.writeAsString('''
    {
      "name": "apex-lsp-it",
      "packageDirectories": [
        { "path": "force-app", "default": true }
      ],
      "sourceApiVersion": "65.0"
    }
    ''');

  final classesDir = fileSystem.directory(
    '${directory.path}/force-app/main/default/classes',
  );
  await classesDir.create(recursive: true);

  for (final classFile in classFiles) {
    final file = fileSystem.file('${classesDir.path}/${classFile.name}');
    await file.writeAsString(classFile.source);
  }

  for (final objectFile in objectFiles) {
    final objectDir = fileSystem.directory(
      '${directory.path}/force-app/main/default/objects/${objectFile.objectName}',
    );
    await objectDir.create(recursive: true);

    final objectMetaFile = fileSystem.file(
      '${objectDir.path}/${objectFile.objectName}.object-meta.xml',
    );
    await objectMetaFile.writeAsString(objectFile.objectMetaXml);

    if (objectFile.fields.isNotEmpty) {
      final fieldsDir = fileSystem.directory('${objectDir.path}/fields');
      await fieldsDir.create();

      for (final field in objectFile.fields) {
        final fieldFile = fileSystem.file(
          '${fieldsDir.path}/${field.name}.field-meta.xml',
        );
        await fieldFile.writeAsString(field.xml);
      }
    }
  }

  return TestWorkspace(directory);
}

/// Reads a fixture file relative to `test/fixtures/`.
Future<String> readFixture(String relativePath) {
  return io.File('test/fixtures/$relativePath').readAsString();
}
