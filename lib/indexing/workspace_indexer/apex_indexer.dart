import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';

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
}) async {
  final files = await _collect(
    fileSystem: fileSystem,
    platform: platform,
    packageDirectoryUris: packageDirectoryUris,
    workspaceRoot: workspaceRoot,
    indexDir: indexDir,
  );
  final stale = await _filterStale(
    fileSystem: fileSystem,
    files: files,
    indexDir: indexDir,
  );
  await _indexInParallel(
    fileSystem: fileSystem,
    platform: platform,
    files: stale,
  );
  await _removeOrphans(
    fileSystem: fileSystem,
    sourceFiles: files,
    indexDir: indexDir,
  );
}

Future<List<_ApexFile>> _collect({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required Uri workspaceRoot,
  required Directory indexDir,
}) async {
  final files = <_ApexFile>[];

  for (final pkgDirUri in packageDirectoryUris) {
    final pkgDirPath = pkgDirUri.toFilePath(windows: platform.isWindows);
    final pkgDir = fileSystem.directory(pkgDirPath);

    if (!await pkgDir.exists()) continue;

    await for (final entity in pkgDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.cls')) continue;
      files.add((
        file: entity,
        workspaceRoot: workspaceRoot,
        indexDir: indexDir,
      ));
    }
  }

  return files;
}

Future<List<_ApexFile>> _filterStale({
  required FileSystem fileSystem,
  required List<_ApexFile> files,
  required Directory indexDir,
}) async {
  final stale = <_ApexFile>[];
  for (final file in files) {
    if (await _isStale(
      fileSystem: fileSystem,
      clsFile: file.file,
      indexDir: indexDir,
    )) {
      stale.add(file);
    }
  }
  return stale;
}

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

Future<void> _indexInParallel({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<_ApexFile> files,
}) async {
  final batchSize = Platform.numberOfProcessors;
  for (var offset = 0; offset < files.length; offset += batchSize) {
    final batch = files.skip(offset).take(batchSize).toList();
    await Future.wait(
      batch.map(
        (f) => _indexSingle(
          fileSystem: fileSystem,
          platform: platform,
          apexFile: f,
        ),
      ),
    );
  }
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

Future<void> _removeOrphans({
  required FileSystem fileSystem,
  required List<_ApexFile> sourceFiles,
  required Directory indexDir,
}) async {
  final knownStems = sourceFiles
      .map(
        (f) =>
            fileSystem.path.basenameWithoutExtension(f.file.path).toLowerCase(),
      )
      .toSet();

  await for (final entity in indexDir.list()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final stem = fileSystem.path
        .basenameWithoutExtension(entity.path)
        .toLowerCase();
    if (!knownStems.contains(stem)) await entity.delete();
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
