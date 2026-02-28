import 'package:apex_lsp/indexing/index_paths.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/apex_indexer.dart'
    show runApexIndexer;
import 'package:apex_lsp/indexing/workspace_indexer/index_repository.dart';
import 'package:apex_lsp/indexing/workspace_indexer/sobject_indexer.dart'
    show runSObjectIndexer;
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';

export 'package:apex_lsp/indexing/workspace_indexer/index_repository.dart'
    show IndexRepository, IndexRepositoryLog;

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
        message: 'Indexing…',
        cancellable: false,
      ),
    );

    yield* _indexInBackground(
      workspaceRoots: uris,
      packageDirectoryUris: packageDirectoryUris,
      token: token,
    );
  }

  IndexRepository getIndexLoader({IndexRepositoryLog? log}) {
    return IndexRepository(
      fileSystem: _fileSystem,
      platform: _platform,
      workspaceRootUris: _workspaceRootUris,
      log: log,
    );
  }

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
