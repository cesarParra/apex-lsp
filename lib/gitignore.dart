import 'package:file/file.dart';

/// Ensures `.sf-zed` appears as an entry in the `.gitignore` file at
/// [workspaceRoot].
///
/// If no `.gitignore` exists it is created. If one already contains `.sf-zed`
/// (as a standalone line) it is left untouched.
Future<void> ensureSfZedIgnored(
  Directory workspaceRoot,
  FileSystem fileSystem,
) async {
  final gitignorePath = fileSystem.path.join(workspaceRoot.path, '.gitignore');
  final gitignoreFile = fileSystem.file(gitignorePath);

  if (await gitignoreFile.exists()) {
    final contents = await gitignoreFile.readAsString();
    if (_containsSfZedEntry(contents)) return;
    final separator = contents.endsWith('\n') ? '' : '\n';
    await gitignoreFile.writeAsString('$contents$separator.sf-zed\n');
  } else {
    await gitignoreFile.writeAsString('.sf-zed\n');
  }
}

/// Returns true if [contents] already has a `.sf-zed` line entry.
bool _containsSfZedEntry(String contents) =>
    contents.split('\n').any((line) => line.trim() == '.sf-zed');
