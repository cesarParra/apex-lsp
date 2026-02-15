import 'dart:convert';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

final class WorkspaceIndexer {
  WorkspaceIndexer({
    required SfdxWorkspaceLocator sfdxWorkspaceLocator,
    required FileSystem fileSystem,
    required LspPlatform platform,
  }) : _sfdxWorkspaceLocator = sfdxWorkspaceLocator,
       _fileSystem = fileSystem,
       _platform = platform;

  static const String indexFolderName = '.sf-zed';

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final FileSystem _fileSystem;
  final LspPlatform _platform;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = <Uri>[];

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

    if (uris.isEmpty) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(
          message: 'Indexing complete (no workspaces)',
        ),
      );
      return;
    }

    _workspaceRootUris = uris;

    // Load SFDX project configs (if present) and compute package directory roots.
    final packageDirectoryUris = await _sfdxWorkspaceLocator
        .packageDirectoryScopeForWorkspaces(uris);

    yield WorkDoneProgressParams(
      token: token,
      value: const WorkDoneProgressBegin(
        title: 'Indexing Apex files',
        message: 'Preparing workspace index…',
        cancellable: false,
      ),
    );

    yield* _indexInBackground(
      workspaceRoots: uris,
      packageDirectoryUris: packageDirectoryUris,
      token: token,
    );
  }

  IndexRepository getIndexLoader() {
    return IndexRepository(
      fileSystem: _fileSystem,
      platform: _platform,
      workspaceRootUris: _workspaceRootUris,
    );
  }

  Stream<WorkDoneProgressParams> _indexInBackground({
    required List<Uri> workspaceRoots,
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    try {
      // The current design keeps `_packageDirectoryUris` as a combined scope across
      // all workspace roots. For indexing, we do a best-effort association:
      // index each workspace using the package directories that are under it.
      for (final root in workspaceRoots) {
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

  /// Builds the index for a single workspace.
  ///
  /// [workspaceRoot] should be a `file://` URI.
  /// [packageDirectoryUris] are absolute directory URIs.
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

  /// Returns a best-effort relative path from [fromRoot] to [absolutePath].
  /// If the paths can’t be made relative (different roots), returns [absolutePath].
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
}

final class IndexRepository {
  IndexRepository({
    required FileSystem fileSystem,
    required LspPlatform platform,
    required List<Uri> workspaceRootUris,
  }) : _fileSystem = fileSystem,
       _platform = platform,
       _workspaceRootUris = workspaceRootUris;

  static const String indexFolderName = '.sf-zed';

  final FileSystem _fileSystem;
  final LspPlatform _platform;
  final List<Uri> _workspaceRootUris;

  Future<List<String>> getTypeNames() async {
    // TODO: Implement caching

    final typeNames = <String>[];
    for (final root in _workspaceRootUris) {
      final indexedtypesForWorkspace = await _loadIndexedTypesForWorkspace(
        root,
      );
      typeNames.addAll(indexedtypesForWorkspace.keys);
    }
    return typeNames;
  }

  Future<IndexedType?> getIndexedType(String typeName) async {
    if (typeName.isEmpty) return null;

    // TODO: Implement caching

    Map<String, IndexedType> indexedTypesByName = {};
    for (final root in _workspaceRootUris) {
      final indexedtypesForWorkspace = await _loadIndexedTypesForWorkspace(
        root,
      );
      indexedTypesByName.addAll(indexedtypesForWorkspace);
    }

    return indexedTypesByName[typeName.toLowerCase()];
  }

  Future<Map<String, IndexedType>> _loadIndexedTypesForWorkspace(
    Uri workspaceRoot,
  ) async {
    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexFolderName),
    );
    if (!indexDir.existsSync()) return {};

    Map<String, IndexedType> indexedTypesByName = {};
    for (final entity in indexDir.listSync(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final file = _fileSystem.file(entity.path);
        if (!await file.exists()) continue;

        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        final indexedType = _parseIndexedType(decoded);
        if (indexedType == null) continue;
        indexedTypesByName[indexedType.name.value.toLowerCase()] = indexedType;
      } catch (_) {
        // TODO: Ignoring malformed index entries for now.
      }
    }

    return indexedTypesByName;
  }

  IndexedType? _parseIndexedType(Object? decoded) {
    if (decoded is! Map) return null;
    final typeMirror = decoded['typeMirror'];
    if (typeMirror is! Map) return null;

    final typeMirrorJson = typeMirror as Map<String, dynamic>;

    IndexedEnum fromEnumMirror(apex_reflection.EnumMirror mirror) {
      return IndexedEnum(
        DeclarationName(mirror.name),
        values: mirror.values
            .map((value) => EnumValueMember(DeclarationName(value.name)))
            .toList(),
      );
    }

    IndexedInterface fromInterfaceMirror(
      apex_reflection.InterfaceMirror mirror,
    ) {
      // TODO: Parse and populate methods
      // TODO: Parse and populate super
      return IndexedInterface(
        DeclarationName(mirror.name),
        methods: [],
        superInterface: null,
      );
    }

    IndexedClass fromClassMirror(apex_reflection.ClassMirror mirror) {
      return IndexedClass(
        DeclarationName(mirror.name),
        members: [
          ...mirror.classes.map(fromClassMirror),
          ...mirror.enums.map(fromEnumMirror),
          ...mirror.interfaces.map(fromInterfaceMirror),
          ...mirror.fields.map(
            (field) => FieldMember(
              DeclarationName(field.name),
              isStatic: field.isStatic,
            ),
          ),
          ...mirror.properties.map(
            (property) => FieldMember(
              DeclarationName(property.name),
              isStatic: property.isStatic,
            ),
          ),
          ...mirror.methods.map(
            (method) => MethodDeclaration(
              DeclarationName(method.name),
              body: Block.empty(),
              isStatic: method.isStatic,
            ),
          ),
        ],
        superClass: null, // TODO: Parse and populate superclass
      );
    }

    return switch (typeMirrorJson['type_name']) {
      'enum' => fromEnumMirror(
        apex_reflection.EnumMirror.fromJson(typeMirrorJson),
      ),
      'class' => fromClassMirror(
        apex_reflection.ClassMirror.fromJson(typeMirrorJson),
      ),
      'interface' => fromInterfaceMirror(
        apex_reflection.InterfaceMirror.fromJson(typeMirrorJson),
      ),
      _ => null,
    };
  }
}

Future<List<String>> getMemberNamesByType(
  IndexedType source,
  MemberType type,
) async {
  List<String> enumMembers(IndexedEnum sourceEnum) {
    return switch (type) {
      .static =>
        sourceEnum.values.map((current) => current.name.value).toList(),
      .instance => [],
    };
  }

  List<String> interfaceMembers(IndexedInterface sourceInterface) {
    return switch (type) {
      .static => [],
      .instance =>
        sourceInterface.methods.map((current) => current.name.value).toList(),
    };
  }

  bool isStaticDeclaration(Declaration declaration) => switch (declaration) {
    FieldMember(:final isStatic) => isStatic,
    MethodDeclaration(:final isStatic) => isStatic,
    EnumValueMember() || IndexedType() || ConstructorDeclaration() => true,
    IndexedVariable() => false,
  };

  List<String> classMembers(IndexedClass sourceClass) {
    return switch (type) {
      .static =>
        sourceClass.members
            .where(isStaticDeclaration)
            .map((declaration) => declaration.name.value)
            .toList(),
      .instance =>
        sourceClass.members
            .where((declaration) => !isStaticDeclaration(declaration))
            .map((declaration) => declaration.name.value)
            .toList(),
    };
  }

  return switch (source) {
    IndexedEnum() => enumMembers(source),
    IndexedInterface() => interfaceMembers(source),
    IndexedClass() => classMembers(source),
  };
}

extension on apex_reflection.MemberModifiersAwareness {
  bool get isStatic =>
      memberModifiers.contains(apex_reflection.MemberModifier.static);
}
