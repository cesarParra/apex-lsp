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
    show IndexRepository, IndexReadErrorLog;

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

  // Single long-lived repository shared across the server session.
  // Patched in place by reindexFile() and deleteOrphanForUri() so that
  // only the affected entry is reloaded rather than the whole index directory.
  // Null before index() has been called.
  IndexRepository? _indexRepository;

  Stream<WorkDoneProgressParams> index(
    InitializedParams params, {
    required ProgressToken token,
    IndexReadErrorLog? onError,
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
    _indexRepository = IndexRepository(
      fileSystem: _fileSystem,
      platform: _platform,
      workspaceRootUris: _workspaceRootUris,
      onError: onError,
    );

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

  /// Re-indexes the single file at [fileUri] using the appropriate indexer,
  /// then patches the in-memory cache so only the one affected entry is
  /// reloaded.
  Future<void> reindexFile(Uri fileUri) async {
    final root = _workspaceRootFor(fileUri);
    if (root == null) return;

    final rootPath = root.toFilePath(windows: _platform.isWindows);
    final rootDir = _fileSystem.directory(rootPath);

    final filePath = fileUri.toFilePath(windows: _platform.isWindows);
    final file = _fileSystem.file(filePath);
    final metadataType = file.metadataType;

    switch (metadataType) {
      case .apexClass:
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
        final stem = _fileSystem.path.basenameWithoutExtension(filePath);
        await _indexRepository?.upsertFromFile(
          Uri.file(_fileSystem.path.join(apexIndexDir.path, '$stem.json')),
          root,
        );
      case .sObject || .sObjectField:
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
        // For .object-meta.xml the object dir is the file's parent;
        // for .field-meta.xml it is one level higher (fields/ is a sibling).
        final objectDir = switch (metadataType) {
          .sObject => file.parent,
          _ => file.parent.parent,
        };
        final objectName = _fileSystem.path.basename(objectDir.path);
        await _indexRepository?.upsertSObjectFromFile(
          Uri.file(
            _fileSystem.path.join(sobjectIndexDir.path, '$objectName.json'),
          ),
          root,
        );
      case .unsupported:
        return;
    }
  }

  /// Removes or re-indexes the cached entry for a file that has been deleted
  /// from disk, then patches the in-memory cache so only the affected entry
  /// is evicted.
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

    final filePath = fileUri.toFilePath(windows: _platform.isWindows);
    final deletedFile = _fileSystem.file(filePath);
    final metadataType = deletedFile.metadataType;

    await deleteOrphanForFile(
      fileSystem: _fileSystem,
      platform: _platform,
      deletedFile: deletedFile,
      apexIndexDir: apexIndexDir,
      sobjectIndexDir: sobjectIndexDir,
    );

    switch (metadataType) {
      case .apexClass:
        final typeName = _fileSystem.path.basenameWithoutExtension(filePath);
        _indexRepository?.evict(typeName, root);
      case .sObject:
        final objectName = _fileSystem.path.basename(deletedFile.parent.path);
        _indexRepository?.evictSObject(objectName, root);
      case .sObjectField:
        // The orphan remover re-indexed the parent SObject; patch the cache.
        final objectName = _fileSystem.path.basename(
          deletedFile.parent.parent.path,
        );
        await _indexRepository?.upsertSObjectFromFile(
          Uri.file(
            _fileSystem.path.join(sobjectIndexDir.path, '$objectName.json'),
          ),
          root,
        );
      case .unsupported:
        return;
    }
  }

  /// Returns the workspace root that [fileUri] belongs to, or `null` if it
  /// does not belong to any known root.
  ///
  /// The root path is always compared with a trailing slash to prevent a root
  /// like `/repo` from matching a sibling path like `/repo-extra/foo.cls`.
  Uri? _workspaceRootFor(Uri fileUri) {
    final filePath = fileUri.path;
    return _workspaceRootUris.where((root) {
      final rootPath = root.path.endsWith('/') ? root.path : '${root.path}/';
      return filePath.startsWith(rootPath);
    }).firstOrNull;
  }

  /// Returns the long-lived [IndexRepository] for this session, or `null` if
  /// [index] has not yet been called.
  IndexRepository? getIndexLoader() => _indexRepository;

  Stream<WorkDoneProgressParams> _indexInBackground({
    required List<Uri> workspaceRoots,
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    try {
      for (final root in workspaceRoots) {
        final rootPath = root.toFilePath(windows: _platform.isWindows);

        final packageDirsForRoot = packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: _platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

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
