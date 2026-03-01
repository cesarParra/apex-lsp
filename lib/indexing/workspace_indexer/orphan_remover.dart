import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

/// Handles the index side-effects of a file deletion.
///
/// - `.cls`             → deletes `apexIndexDir/<stem>.json`
/// - `.object-meta.xml` → deletes `sobjectIndexDir/<objectName>.json`
/// - `.field-meta.xml`  → re-indexes the parent SObject so the remaining
///   fields are reflected; no-op if the object directory no longer exists
/// - anything else      → no-op
Future<void> deleteOrphanForFile({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required Uri deletedFileUri,
  required Directory apexIndexDir,
  required Directory sobjectIndexDir,
}) async {
  final path = deletedFileUri.toFilePath(windows: platform.isWindows);
  final lowerPath = path.toLowerCase();

  if (lowerPath.endsWith('.cls')) {
    final stem = fileSystem.path.basenameWithoutExtension(path);
    await _deleteIfExists(apexIndexDir.childFile('$stem.json'));
  } else if (lowerPath.endsWith('.object-meta.xml')) {
    final basename = fileSystem.path.basename(path);
    final objectName = basename.replaceFirst('.object-meta.xml', '');
    await _deleteIfExists(sobjectIndexDir.childFile('$objectName.json'));
  } else if (lowerPath.endsWith('.field-meta.xml')) {
    // Path: .../objects/Account/fields/SomeField.field-meta.xml
    // parent = fields/,  parent.parent = Account/
    final fieldsDir = fileSystem.path.dirname(path);
    final objectDirPath = fileSystem.path.dirname(fieldsDir);
    final objectDir = fileSystem.directory(objectDirPath);

    // The field is gone but the SObject itself still exists — re-index it so
    // the remaining fields are reflected in the cache.
    if (!await objectDir.exists()) return;

    final objectName = fileSystem.path.basename(objectDirPath);
    final objectMetaFile = fileSystem.file(
      fileSystem.path.join(objectDirPath, '$objectName.object-meta.xml'),
    );
    await reindexSObjectFile(
      fileSystem: fileSystem,
      platform: platform,
      file: objectMetaFile,
      indexDir: sobjectIndexDir,
    );
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}
