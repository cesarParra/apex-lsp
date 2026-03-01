import 'dart:io' show Platform;

import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

/// Shared pipeline for all workspace indexers.
///
/// Drives the four-step collect → filter-stale → index-in-parallel →
/// remove-orphans pipeline. Domain-specific behaviour is injected via callbacks:
///
/// - [recognize]: inspects a [File] found during the recursive walk and returns
///   a typed item [T] to include, or `null` to skip it.
/// - [isStale]: returns `true` when the item's cached JSON is out of date.
/// - [index]: writes (or re-writes) the JSON for one item.
/// - [nameOf]: returns the logical name used to detect orphaned JSON files
///   (compared case-insensitively against the file stems in [indexDir]).
Future<void> runIndexer<T>({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required Directory indexDir,
  required T? Function(File) recognize,
  required Future<bool> Function(T) isStale,
  required Future<void> Function(T) index,
  required String Function(T) nameOf,
}) async {
  final items = await _collect(
    fileSystem: fileSystem,
    platform: platform,
    packageDirectoryUris: packageDirectoryUris,
    recognize: recognize,
  );
  final stale = await _filterStale(items: items, isStale: isStale);
  await _indexInParallel(items: stale, index: index);
  await _removeOrphans(
    fileSystem: fileSystem,
    items: items,
    indexDir: indexDir,
    nameOf: nameOf,
  );
}

Future<List<T>> _collect<T>({
  required FileSystem fileSystem,
  required LspPlatform platform,
  required List<Uri> packageDirectoryUris,
  required T? Function(File) recognize,
}) async {
  final items = <T>[];

  for (final pkgDirUri in packageDirectoryUris) {
    final pkgDirPath = pkgDirUri.toFilePath(windows: platform.isWindows);
    final pkgDir = fileSystem.directory(pkgDirPath);

    if (!await pkgDir.exists()) continue;

    await for (final entity in pkgDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final item = recognize(entity);
      if (item != null) items.add(item);
    }
  }

  return items;
}

Future<List<T>> _filterStale<T>({
  required List<T> items,
  required Future<bool> Function(T) isStale,
}) async {
  final stale = <T>[];
  for (final item in items) {
    if (await isStale(item)) stale.add(item);
  }
  return stale;
}

Future<void> _indexInParallel<T>({
  required List<T> items,
  required Future<void> Function(T) index,
}) async {
  final batchSize = Platform.numberOfProcessors;
  for (var offset = 0; offset < items.length; offset += batchSize) {
    final batch = items.skip(offset).take(batchSize).toList();
    await Future.wait(batch.map(index));
  }
}

Future<void> _removeOrphans<T>({
  required FileSystem fileSystem,
  required List<T> items,
  required Directory indexDir,
  required String Function(T) nameOf,
}) async {
  final knownNames = items.map((i) => nameOf(i).toLowerCase()).toSet();

  await for (final entity in indexDir.list()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    final stem = fileSystem.path
        .basenameWithoutExtension(entity.path)
        .toLowerCase();
    if (!knownNames.contains(stem)) await entity.delete();
  }
}
