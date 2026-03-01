import 'dart:convert';
import 'dart:isolate';

import 'package:apex_lsp/indexing/workspace_indexer/indexer_utils.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

/// Top-level entry point for isolate execution.
///
/// Must be top-level so Dart can send it across isolate boundaries.
/// Returns the serialized typeMirror JSON, or throws on parse error.
Future<Map<String, Object?>> _reflectApexSource(String source) async {
  final response = apex_reflection.Reflection.reflect(source);
  if (response.error != null) throw response.error!.message;
  return response.typeMirror!.toJson();
}

typedef _ApexFile = ({File file, Uri workspaceRoot, Directory indexDir});

Future<void> runApexIndexer({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required Uri workspaceRoot,
  required Directory indexDir,
}) => runIndexer<_ApexFile>(
  fileSystem: fileSystem,
  platform: platform,
  packageDirectoryUris: packageDirectoryUris,
  indexDir: indexDir,
  recognize: (file) {
    if (!file.path.toLowerCase().endsWith('.cls')) return null;
    return (file: file, workspaceRoot: workspaceRoot, indexDir: indexDir);
  },
  isStale: (apexFile) => _isStale(
    fileSystem: fileSystem,
    clsFile: apexFile.file,
    indexDir: indexDir,
  ),
  index: (apexFile) => _indexSingle(
    fileSystem: fileSystem,
    platform: platform,
    apexFile: apexFile,
  ),
  nameOf: (apexFile) =>
      fileSystem.path.basenameWithoutExtension(apexFile.file.path),
);

Future<bool> _isStale({
  required FileSystem fileSystem,
  required File clsFile,
  required Directory indexDir,
}) async {
  final stem = fileSystem.path.basenameWithoutExtension(clsFile.path);
  final jsonFile = fileSystem.file(
    fileSystem.path.join(indexDir.path, '$stem.json'),
  );
  if (!await jsonFile.exists()) return true;
  final clsModified = await clsFile.lastModified();
  final jsonModified = await jsonFile.lastModified();
  return clsModified.isAfter(jsonModified);
}

Future<void> _indexSingle({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required _ApexFile apexFile,
}) async {
  try {
    final source = await apexFile.file.readAsString();
    final typeMirrorJson = await Isolate.run(() => _reflectApexSource(source));

    final className = typeMirrorJson['name'] as String;
    final relativePath = _safeRelativePath(
      platform: platform,
      fromRoot: apexFile.workspaceRoot,
      absolutePath: apexFile.file.path,
    );

    final payload = <String, Object?>{
      'schemaVersion': 1,
      'className': className,
      'source': <String, Object?>{
        'uri': Uri.file(apexFile.file.path).toString(),
        'relativePath': relativePath,
      },
      'typeMirror': typeMirrorJson,
    };

    final outPath = fileSystem.path.join(
      apexFile.indexDir.path,
      '$className.json',
    );
    await fileSystem
        .file(outPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  } catch (_) {
    // Silently skip files that fail to reflect or write.
  }
}

String _safeRelativePath({
  required LspPlatform platform,
  required Uri fromRoot,
  required String absolutePath,
}) {
  final rootPath = fromRoot.toFilePath(windows: platform.isWindows);
  if (absolutePath.startsWith(rootPath)) {
    var rel = absolutePath.substring(rootPath.length);
    if (rel.startsWith(platform.pathSeparator)) rel = rel.substring(1);
    return rel;
  }
  return absolutePath;
}
