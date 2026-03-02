import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart';
import 'package:apex_lsp/indexing/workspace_indexer/utils.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

/// Handles the index side-effects of a file deletion.
///
/// [deletedFile] is the source file that was removed from disk. Its
/// [MetadataType] determines which index entry to drop or re-index.
Future<void> deleteOrphanForFile({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required File deletedFile,
  required Directory apexIndexDir,
  required Directory sobjectIndexDir,
}) async {
  switch (deletedFile.metadataType) {
    case ApexClassType():
      final stem = fileSystem.path.basenameWithoutExtension(deletedFile.path);
      await _deleteIfExists(apexIndexDir.childFile('$stem.json'));
    case SObjectType():
      // The object name equals the basename of the parent directory.
      // e.g. Account/Account.object-meta.xml → parent = Account/ → "Account"
      final objectName = fileSystem.path.basename(deletedFile.parent.path);
      await _deleteIfExists(sobjectIndexDir.childFile('$objectName.json'));
    case SObjectFieldType():
      // Path: .../objects/Account/fields/SomeField.field-meta.xml
      // parent = fields/,  parent.parent = Account/
      final objectDir = deletedFile.parent.parent;

      // The field is gone but the SObject itself still exists, so re-index it
      // so the remaining fields are reflected in the cache.
      if (!await objectDir.exists()) return;

      final objectName = fileSystem.path.basename(objectDir.path);
      await reindexSObjectFile(
        fileSystem: fileSystem,
        platform: platform,
        file: objectDir.childFile('$objectName.object-meta.xml'),
        indexDir: sobjectIndexDir,
      );
    case UnsupportedType():
      return;
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
