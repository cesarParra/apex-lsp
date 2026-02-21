import 'dart:async';
import 'dart:io';
import 'dart:io' as io;

import 'package:apex_lsp/cancellation_tracker.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:apex_lsp/server.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/local.dart';

/// Apex Language Server Protocol (LSP) server over stdio.
Future<void> main(List<String> args) async {
  final fileSystem = LocalFileSystem();
  String resolveFromCurrentDirectory(String location) {
    final scriptDir = fileSystem.path.dirname(io.Platform.script.toFilePath());
    return fileSystem.path.join(scriptDir, location);
  }

  final bindings = TreeSitterBindings.load(
    pathResolver: resolveFromCurrentDirectory,
    path: io.Platform.environment['TS_SFAPEX_LIB'],
  );

  final server = Server(
    output: LspOut(output: StdoutByteSink(io.stdout)),
    reader: MessageReader(stdin),
    exitFn: io.exit,
    openDocuments: OpenDocuments(),
    localIndexer: LocalIndexer(bindings: bindings),
    workspaceIndexer: WorkspaceIndexer(
      sfdxWorkspaceLocator: SfdxWorkspaceLocator(
        fileSystem: fileSystem,
        platform: DartIoLspPlatform(),
      ),
      fileSystem: fileSystem,
      platform: DartIoLspPlatform(),
    ),
    cancellationTracker: CancellationTracker(),
  );

  try {
    await server.run();
  } catch (e, st) {
    await server.logMessage(.error, 'Fatal error: $e\n$st');
    exitCode = 1;
  }
}
