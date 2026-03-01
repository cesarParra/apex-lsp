import 'package:file/file.dart';

import 'package:apex_lsp/indexing/index_paths.dart';

/// Ensures the index root folder appears as an entry in the `.gitignore` file
/// at [workspaceRoot].
///
/// If no `.gitignore` exists it is created. If one already contains the entry
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
    await gitignoreFile.writeAsString(
      '$contents$separator$indexRootFolderName\n',
    );
  } else {
    await gitignoreFile.writeAsString('$indexRootFolderName\n');
  }
}

/// Returns true if [contents] already has the index root folder as a line entry.
bool _containsSfZedEntry(String contents) =>
    contents.split('\n').any((line) => line.trim() == indexRootFolderName);
