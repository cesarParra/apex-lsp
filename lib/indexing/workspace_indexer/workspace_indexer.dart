import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/apex_indexer.dart'
    show reindexApexFile, runApexIndexer;
import 'package:apex_lsp/indexing/workspace_indexer/index_repository.dart';
import 'package:apex_lsp/indexing/workspace_indexer/orphan_remover.dart';
import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart'
    show reindexSObjectFile, runSObjectIndexer;
import 'package:apex_lsp/indexing/workspace_indexer/utils.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

export 'package:apex_lsp/indexing/workspace_indexer/index_repository.dart'
    show IndexRepository;

final class WorkspaceIndexer {
  WorkspaceIndexer({
    required SfdxWorkspaceLocator sfdxWorkspaceLocator,
    required FileSystem fileSystem,
    required LspPlatform platform,
  }) : _sfdxWorkspaceLocator = sfdxWorkspaceLocator,
       _fileSystem = fileSystem,
       _platform = platform;

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final FileSystem _fileSystem;
  final LspPlatform _platform;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = <Uri>[];

  // Package directory URIs per workspace root, populated during index().
  // Required by reindexFile() to locate the correct index directories.
  Map<Uri, List<Uri>> _packageDirectoryUrisByRoot = {};

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
        title: 'Initializing Apex LSP',
        message: 'Building index…',
        cancellable: false,
      ),
    );

    yield* _indexInBackground(
      workspaceRoots: uris,
      packageDirectoryUris: packageDirectoryUris,
      token: token,
    );
  }

  /// Re-indexes the single file at [fileUri] using the appropriate indexer.
  ///
  /// Routes based on file extension:
  /// - `.cls` → [reindexApexFile]
  /// - `.object-meta.xml` or `.field-meta.xml` → [reindexSObjectFile]
  /// - anything else → no-op
  ///
  /// If [fileUri] does not belong to any known workspace root, this is a no-op.
  Future<void> reindexFile(Uri fileUri) async {
    final root = _workspaceRootFor(fileUri);
    if (root == null) return;

    final rootPath = root.toFilePath(windows: _platform.isWindows);
    final rootDir = _fileSystem.directory(rootPath);

    final filePath = fileUri.toFilePath(windows: _platform.isWindows);
    final file = _fileSystem.file(filePath);

    switch (file.metadataType) {
      case ApexClassType():
        final apexIndexDir = _fileSystem.directory(
          _fileSystem.path.join(
            rootDir.path,
            indexRootFolderName,
            apexIndexFolderName,
          ),
        );
        await reindexApexFile(
          fileSystem: _fileSystem,
          platform: _platform,
          workspaceRoot: root,
          file: file,
          indexDir: apexIndexDir,
        );
      case SObjectType() || SObjectFieldType():
        final sobjectIndexDir = _fileSystem.directory(
          _fileSystem.path.join(
            rootDir.path,
            indexRootFolderName,
            sobjectIndexFolderName,
          ),
        );
        await reindexSObjectFile(
          fileSystem: _fileSystem,
          platform: _platform,
          file: file,
          indexDir: sobjectIndexDir,
        );
      default:
        return;
    }
  }

  /// Removes or re-indexes the cached entry for a file that has been deleted
  /// from disk.
  ///
  /// Delegates to [deleteOrphanForFile], which routes based on the URI path:
  /// - `.cls`             → deletes the corresponding Apex JSON
  /// - `.object-meta.xml` → deletes the corresponding SObject JSON
  /// - `.field-meta.xml`  → re-indexes the parent SObject
  /// - anything else      → no-op
  ///
  /// If [fileUri] does not belong to any known workspace root, this is a no-op.
  Future<void> deleteOrphanForUri(Uri fileUri) async {
    final root = _workspaceRootFor(fileUri);
    if (root == null) return;

    final rootPath = root.toFilePath(windows: _platform.isWindows);
    final apexIndexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexRootFolderName, apexIndexFolderName),
    );
    final sobjectIndexDir = _fileSystem.directory(
      _fileSystem.path.join(
        rootPath,
        indexRootFolderName,
        sobjectIndexFolderName,
      ),
    );

    await deleteOrphanForFile(
      fileSystem: _fileSystem,
      platform: _platform,
      deletedFileUri: fileUri,
      apexIndexDir: apexIndexDir,
      sobjectIndexDir: sobjectIndexDir,
    );
  }

  /// Returns the workspace root that [fileUri] belongs to, or `null` if it
  /// does not belong to any known root.
  Uri? _workspaceRootFor(Uri fileUri) => _workspaceRootUris
      .where((root) => fileUri.path.startsWith(root.path))
      .firstOrNull;

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
      _packageDirectoryUrisByRoot = {};
      for (final root in workspaceRoots) {
        final rootPath = root.toFilePath(windows: _platform.isWindows);

        final packageDirsForRoot = packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: _platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        _packageDirectoryUrisByRoot[root] = packageDirsForRoot;

        await _indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
        );
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

  Future<void> _indexWorkspace({
    required Uri workspaceRoot,
    required List<Uri> packageDirectoryUris,
  }) async {
    final workspaceRootPath = workspaceRoot.toFilePath(
      windows: _platform.isWindows,
    );
    final workspaceRootDir = _fileSystem.directory(workspaceRootPath);

    final apexIndexDir = _fileSystem.directory(
      _fileSystem.path.join(
        workspaceRootDir.path,
        indexRootFolderName,
        apexIndexFolderName,
      ),
    );
    if (!await apexIndexDir.exists()) {
      await apexIndexDir.create(recursive: true);
    }

    final sobjectIndexDir = _fileSystem.directory(
      _fileSystem.path.join(
        workspaceRootDir.path,
        indexRootFolderName,
        sobjectIndexFolderName,
      ),
    );
    if (!await sobjectIndexDir.exists()) {
      await sobjectIndexDir.create(recursive: true);
    }

    await Future.wait([
      runApexIndexer(
        fileSystem: _fileSystem,
        platform: _platform,
        packageDirectoryUris: packageDirectoryUris,
        workspaceRoot: workspaceRoot,
        indexDir: apexIndexDir,
      ),
      runSObjectIndexer(
        fileSystem: _fileSystem,
        platform: _platform,
        packageDirectoryUris: packageDirectoryUris,
        indexDir: sobjectIndexDir,
      ),
    ]);
  }
}
