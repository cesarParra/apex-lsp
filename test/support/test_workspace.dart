import 'dart:io';

typedef ClassFile = ({String name, String source});

/// A temporary SFDX workspace for integration tests.
final class TestWorkspace {
  final Directory directory;

  TestWorkspace(this.directory);

  Uri get uri => Uri.directory(directory.path);

  String get classesPath =>
      '${directory.path}/force-app/main/default/classes';
}

/// Creates a temporary SFDX workspace with the given Apex class files.
///
/// The workspace includes an `sfdx-project.json` copied from fixtures
/// and the standard `force-app/main/default/classes` directory.
Future<TestWorkspace> createTestWorkspace({
  List<ClassFile> classFiles = const [],
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
