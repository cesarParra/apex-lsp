import 'dart:async';
import 'dart:convert';

import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

import '../message.dart';

/// Base wrapper for Apex type mirrors from the reflection API.
///
/// Provides a sealed hierarchy for type-safe handling of different Apex
/// type kinds (classes, enums, interfaces) returned from the reflection parser.
///
/// See also:
///  * [ClassMirrorWrapper], for class type mirrors.
///  * [EnumMirrorWrapper], for enum type mirrors.
///  * [InterfaceMirrorWrapper], for interface type mirrors.
sealed class TypeMirrorWrapper<T extends apex_reflection.TypeMirror> {
  const TypeMirrorWrapper(this.typeMirror);

  final T typeMirror;
}

/// Wrapper for Apex class type mirrors.
final class ClassMirrorWrapper
    extends TypeMirrorWrapper<apex_reflection.ClassMirror> {
  const ClassMirrorWrapper(super.typeMirror);
}

/// Wrapper for Apex enum type mirrors.
final class EnumMirrorWrapper
    extends TypeMirrorWrapper<apex_reflection.EnumMirror> {
  const EnumMirrorWrapper(super.typeMirror);
}

/// Wrapper for Apex interface type mirrors.
final class InterfaceMirrorWrapper
    extends TypeMirrorWrapper<apex_reflection.InterfaceMirror> {
  const InterfaceMirrorWrapper(super.typeMirror);
}

/// Indexes Apex workspace files and maintains completion metadata.
///
/// This indexer scans Salesforce DX projects for `.cls` files, parses them
/// using the `apex_reflection` library, and generates JSON metadata files
/// stored in a `.sf-zed` directory at each workspace root. The metadata
/// enables fast completion suggestions without re-parsing files.
///
/// **Key features:**
/// - Discovers SFDX package directories automatically
/// - Parses Apex classes, enums, and interfaces
/// - Writes structured JSON metadata for quick lookup
/// - Maintains in-memory cache of indexed class names
/// - Reports progress during indexing via LSP progress notifications
///
/// **Index structure:**
/// ```
/// <workspace-root>/.sf-zed/
///   ├── ClassName1.json
///   ├── ClassName2.json
///   └── ...
/// ```
///
/// Example:
/// ```dart
/// final indexer = ApexIndexer(
///   fileSystem: LocalFileSystem(),
///   platform: LspPlatform(),
/// );
/// await for (final progress in indexer.index(params, token: token)) {
///   output.progress(params: progress);
/// }
/// ```
///
/// See also:
///  * [SfdxWorkspaceLocator], which discovers SFDX project directories.
///  * [LocalIndexer], which indexes the currently open file.
final class ApexIndexer {
  ApexIndexer({required FileSystem fileSystem, required LspPlatform platform})
    : _sfdxWorkspaceLocator = SfdxWorkspaceLocator(
        fileSystem: fileSystem,
        platform: platform,
      ),
      _fileSystem = fileSystem,
      _platform = platform;

  /// Name of the hidden directory where index files are stored.
  static const String indexFolderName = '.sf-zed';

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final FileSystem _fileSystem;
  final LspPlatform _platform;

  /// Workspace root URIs discovered during initialization.
  List<Uri> _workspaceRootUris = <Uri>[];

  /// In-memory set of all indexed class names across workspaces.
  ///
  /// Loaded lazily on first access from the `.sf-zed` directories.
  final Set<String> _indexedClassNames = <String>{};

  /// Whether the class names have been loaded from disk.
  bool _indexedClassNamesLoaded = false;

  /// Returns the set of all indexed class names.
  ///
  /// Ensures the class names are loaded from disk on first access.
  Set<String> get indexedClassNames {
    _ensureIndexedClassNamesLoaded();
    return _indexedClassNames;
  }

  /// Cache of loaded type mirrors by class name.
  final _indexedClassByNameCache = <String, TypeMirrorWrapper>{};

  /// Set of class names confirmed to not exist in any workspace.
  final Set<String> _workspaceClassNotFound = <String>{};

  /// Indexes all Apex files in the workspace and reports progress.
  ///
  /// Discovers workspace folders from [params], locates SFDX package directories,
  /// and indexes all `.cls` files found. Progress is reported via LSP work-done
  /// progress notifications using the provided [token].
  ///
  /// - [params]: Initialization parameters containing workspace folders.
  /// - [token]: Progress token for reporting indexing status.
  ///
  /// Yields [WorkDoneProgressParams] as indexing progresses, including:
  /// - Begin event when indexing starts
  /// - Report events with percentage complete
  /// - End event when indexing finishes or fails
  ///
  /// Example:
  /// ```dart
  /// await for (final progress in indexer.index(params, token: token)) {
  ///   output.progress(params: progress);
  /// }
  /// ```
  Stream<WorkDoneProgressParams> index(
    InitializedParams params, {
    required ProgressToken token,
  }) async* {
    final folders = params.workspaceFolders;
    if (folders == null || folders.isEmpty) return;

    final uris = <Uri>[];
    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri != null) uris.add(uri);
    }
    _workspaceRootUris = uris;
    _resetCachesForReindex();

    // Load SFDX project configs (if present) and compute package directory roots.
    final packageDirectoryUris = await _sfdxWorkspaceLocator
        .packageDirectoryScopeForWorkspaces(_workspaceRootUris);

    yield WorkDoneProgressParams(
      token: token,
      value: const WorkDoneProgressBegin(
        title: 'Indexing Apex files',
        message: 'Preparing workspace index…',
        cancellable: false,
      ),
    );

    yield* _indexInBackground(
      packageDirectoryUris: packageDirectoryUris,
      token: token,
    );
  }

  Stream<WorkDoneProgressParams> _indexInBackground({
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    if (_workspaceRootUris.isEmpty) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(
          message: 'Indexing complete (no workspaces)',
        ),
      );
      return;
    }

    try {
      // The current design keeps `_packageDirectoryUris` as a combined scope across
      // all workspace roots. For indexing, we do a best-effort association:
      // index each workspace using the package directories that are under it.
      for (final root in _workspaceRootUris) {
        final rootPath = root.toFilePath(windows: _platform.isWindows);

        final packageDirsForRoot = packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: _platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        yield* _indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
          token: token,
        );

        // Class names are loaded lazily on demand.
      }

      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(message: 'Indexing complete'),
      );
    } catch (e) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(message: 'Indexing failed'),
      );
    }
  }

  void _resetCachesForReindex() {
    _indexedClassNamesLoaded = false;
    _indexedClassNames.clear();
    _indexedClassByNameCache.clear();
    _workspaceClassNotFound.clear();
  }

  /// Ensures indexed class names are loaded from disk.
  ///
  /// Lazily loads class names from all workspace `.sf-zed` directories
  /// on first access. Subsequent calls are no-ops.
  void _ensureIndexedClassNamesLoaded() {
    if (_indexedClassNamesLoaded) return;

    if (_workspaceRootUris.isEmpty) {
      _indexedClassNamesLoaded = true;
      return;
    }

    for (final root in _workspaceRootUris) {
      _loadIndexedClassNamesForWorkspace(root);
    }

    _indexedClassNamesLoaded = true;
  }

  /// Loads indexed class names from a single workspace's `.sf-zed` directory.
  ///
  /// Scans the index directory for JSON files and extracts class names from
  /// the file names (e.g., `Account.json` → `Account`).
  ///
  /// - [workspaceRoot]: The workspace root URI to load from.
  void _loadIndexedClassNamesForWorkspace(Uri workspaceRoot) {
    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexFolderName),
    );
    if (!indexDir.existsSync()) return;

    for (final entity in indexDir.listSync(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final fileName = _fileSystem.path.basename(entity.path);
        if (!fileName.toLowerCase().endsWith('.json')) continue;

        final className = fileName.substring(0, fileName.length - 5);
        if (className.isEmpty) continue;

        _indexedClassNames.add(className);
      } catch (_) {
        // Ignore malformed index entries for now.
      }
    }
  }

  /// Retrieves detailed type information for an indexed class.
  ///
  /// Searches all workspaces for the class metadata file and returns the
  /// parsed type mirror. Results are cached to avoid repeated disk reads.
  ///
  /// - [className]: The name of the class to look up.
  ///
  /// Returns the type mirror wrapper, or `null` if the class is not found
  /// in any workspace or if the metadata file cannot be parsed.
  ///
  /// Example:
  /// ```dart
  /// final classInfo = await indexer.getIndexedClassInfo('Account');
  /// if (classInfo case ClassMirrorWrapper(:final typeMirror)) {
  ///   print('Found class: ${typeMirror.name}');
  /// }
  /// ```
  Future<TypeMirrorWrapper?> getIndexedClassInfo(String className) async {
    if (className.isEmpty) return null;

    final cached = _indexedClassByNameCache[className];
    if (cached != null) return cached;

    if (_workspaceClassNotFound.contains(className)) return null;

    for (final root in _workspaceRootUris) {
      final info = await _tryLoadWorkspaceClassInfoForRoot(root, className);
      if (info != null) {
        _indexedClassByNameCache[className] = info;
        return info;
      }
    }

    _workspaceClassNotFound.add(className);
    return null;
  }

  Future<TypeMirrorWrapper?> _tryLoadWorkspaceClassInfoForRoot(
    Uri workspaceRoot,
    String className,
  ) async {
    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDirPath = _fileSystem.path.join(rootPath, indexFolderName);
    final filePath = _fileSystem.path.join(indexDirPath, '$className.json');
    final file = _fileSystem.file(filePath);

    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      return _parseIndexedClassInfo(decoded);
    } catch (e) {
      return null;
    }
  }

  TypeMirrorWrapper? _parseIndexedClassInfo(Object? decoded) {
    if (decoded is! Map) return null;
    final typeMirror = decoded['typeMirror'];
    if (typeMirror is! Map) return null;

    final typeMirrorJson = typeMirror as Map<String, dynamic>;

    return switch (typeMirrorJson['type_name']) {
      'enum' => EnumMirrorWrapper(
        apex_reflection.EnumMirror.fromJson(typeMirrorJson),
      ),
      'class' => ClassMirrorWrapper(
        apex_reflection.ClassMirror.fromJson(typeMirrorJson),
      ),
      'interface' => InterfaceMirrorWrapper(
        apex_reflection.InterfaceMirror.fromJson(typeMirrorJson),
      ),
      _ => null,
    };
  }

  /// Builds the index for a single workspace.
  ///
  /// Creates the `.sf-zed` directory, indexes all Apex files in the workspace's
  /// package directories, and writes JSON metadata files for each type.
  ///
  /// - [workspaceRoot]: The workspace root as a `file://` URI.
  /// - [packageDirectoryUris]: Absolute URIs of package directories to index.
  /// - [token]: Progress token for reporting indexing status.
  ///
  /// The existing index directory is deleted and recreated to ensure freshness.
  Stream<WorkDoneProgressParams> _indexWorkspace({
    required Uri workspaceRoot,
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    final workspaceRootPath = workspaceRoot.toFilePath(
      windows: _platform.isWindows,
    );
    final workspaceRootDir = _fileSystem.directory(workspaceRootPath);

    // Ensure `.sf-zed` is created under the actual on-disk workspace directory.
    final indexDirPath = _fileSystem.path.join(
      workspaceRootDir.path,
      indexFolderName,
    );
    final indexDir = _fileSystem.directory(indexDirPath);

    // At the moment, we always recreate the index from scratch.
    if (await indexDir.exists()) {
      await indexDir.delete(recursive: true);
    }

    await indexDir.create(recursive: true);

    // Compute total files up-front so we can report accurate progress as we go.
    final totalFiles = await _countApexFilesToIndex(packageDirectoryUris);

    var processedFiles = 0;
    var lastReportedPercent = -1;

    for (final pkgDirUri in packageDirectoryUris) {
      yield* _indexPackageDirectory(
        pkgDirUri,
        workspaceRoot,
        indexDir,
        totalFiles: totalFiles,
        processedFiles: processedFiles,
        lastReportedPercent: lastReportedPercent,
        token: token,
      );
    }

    // Ensure we end on 100% if there was anything to do.
    if (totalFiles > 0 && lastReportedPercent < 100) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressReport(percentage: 100),
      );
    }
  }

  Stream<WorkDoneProgressParams> _indexPackageDirectory(
    Uri pkgDirUri,
    Uri workspaceRoot,
    Directory indexDir, {
    required int totalFiles,
    required int processedFiles,
    required int lastReportedPercent,
    required ProgressToken token,
  }) async* {
    final pkgDirPath = pkgDirUri.toFilePath(windows: _platform.isWindows);
    final pkgDir = _fileSystem.directory(pkgDirPath);

    final exists = await pkgDir.exists();

    if (!exists) {
      return;
    }

    await for (final entity in pkgDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      if (!entity.path.toLowerCase().endsWith('.cls')) {
        continue;
      }

      final result = await _indexSingleFile(
        workspaceRoot: workspaceRoot,
        indexDir: indexDir,
        apexFile: entity,
      );

      switch (result) {
        case Success(:final value):
          processedFiles++;

          if (totalFiles > 0) {
            final percent = ((processedFiles * 100) / totalFiles).floor();
            // Notify every 1% increase based on total file count.
            if (percent >= 1 &&
                percent <= 100 &&
                percent > lastReportedPercent) {
              lastReportedPercent = percent;
              yield WorkDoneProgressParams(
                token: token,
                value: WorkDoneProgressReport(
                  percentage: percent,
                  message: value,
                  cancellable: false,
                ),
              );
            }
          }
        case Failure():
          // Ignoring indexing issues for now.
          break;
      }
    }
  }

  Future<Result<String>> _indexSingleFile({
    required Uri workspaceRoot,
    required Directory indexDir,
    required File apexFile,
  }) async {
    try {
      final source = await apexFile.readAsString();
      final reflectionResponse = apex_reflection.Reflection.reflect(source);

      if (reflectionResponse.error != null) {
        return Failure(reflectionResponse.error!.message);
      }

      final className = reflectionResponse.typeMirror!.name;

      final outPath = _fileSystem.path.join(indexDir.path, '$className.json');
      final outFile = _fileSystem.file(outPath);

      final relativePath = _safeRelativePath(
        fromRoot: workspaceRoot,
        absolutePath: apexFile.path,
      );

      // TODO: This can be a standalone object rather than using maps
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'className': className,
        'source': <String, Object?>{
          'uri': Uri.file(apexFile.path).toString(),
          'relativePath': relativePath,
        },
        'typeMirror': reflectionResponse.typeMirror!.toJson(),
      };

      await outFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      return Success(reflectionResponse.typeMirror!.name);
    } catch (e) {
      return Failure('Failed to index ${apexFile.path}: $e');
    }
  }

  /// Computes a relative path from a workspace root to an absolute file path.
  ///
  /// Attempts to create a relative path from [fromRoot] to [absolutePath].
  /// If the paths are on different roots or cannot be made relative, returns
  /// the [absolutePath] unchanged.
  ///
  /// - [fromRoot]: The workspace root URI to compute relative to.
  /// - [absolutePath]: The absolute file path to make relative.
  ///
  /// Returns the relative path with leading path separator removed, or the
  /// original [absolutePath] if it cannot be made relative.
  String _safeRelativePath({
    required Uri fromRoot,
    required String absolutePath,
  }) {
    final rootPath = fromRoot.toFilePath(windows: _platform.isWindows);
    if (absolutePath.startsWith(rootPath)) {
      var rel = absolutePath.substring(rootPath.length);
      if (rel.startsWith(_platform.pathSeparator)) {
        rel = rel.substring(1);
      }
      return rel;
    }
    return absolutePath;
  }

  /// Counts the total number of Apex files to index across all package directories.
  ///
  /// Used to calculate accurate progress percentages during indexing.
  ///
  /// - [packageDirectoryUris]: The package directories to scan.
  ///
  /// Returns the total count of `.cls` files found.
  Future<int> _countApexFilesToIndex(List<Uri> packageDirectoryUris) async {
    var total = 0;

    for (final pkgDirUri in packageDirectoryUris) {
      final pkgDirPath = pkgDirUri.toFilePath(windows: _platform.isWindows);
      final pkgDir = _fileSystem.directory(pkgDirPath);

      if (!await pkgDir.exists()) {
        continue;
      }

      await for (final entity in pkgDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.cls')) continue;
        total++;
      }
    }

    return total;
  }
}
