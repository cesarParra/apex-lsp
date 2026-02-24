import 'dart:io';

import 'package:apex_lsp/cancellation_tracker.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:apex_lsp/server.dart';
import 'package:file/local.dart';

import '../support/lsp_client.dart';
import '../support/lsp_test_harness.dart';

final _libPath = Platform.environment['TS_SFAPEX_LIB'];

final _bindings = TreeSitterBindings.load(path: _libPath);

final class _ExitCalled implements Exception {
  _ExitCalled(this.code);
  final int code;

  @override
  String toString() => '_ExitCalled(code=$code)';
}

typedef IntegrationData = ({
  Server server,
  InMemoryByteSink sink,
  InMemoryLspInput input,
});

IntegrationData createIntegrationData() {
  final input = InMemoryLspInput(sync: true);
  final sink = InMemoryByteSink();
  final fileSystem = LocalFileSystem();
  final platform = FakeLspPlatform();
  final integrationServer = Server(
    output: LspOut(output: sink),
    reader: MessageReader(input.stream),
    exitFn: (code) => throw _ExitCalled(code),
    openDocuments: OpenDocuments(),
    localIndexer: LocalIndexer(bindings: _bindings),
    workspaceIndexer: WorkspaceIndexer(
      sfdxWorkspaceLocator: SfdxWorkspaceLocator(
        fileSystem: fileSystem,
        platform: platform,
      ),
      fileSystem: fileSystem,
      platform: platform,
    ),
    cancellationTracker: CancellationTracker(),
    fileSystem: fileSystem,
    platform: platform,
  );
  return (server: integrationServer, sink: sink, input: input);
}

LspClient createLspClient() {
  final (:server, :sink, :input) = createIntegrationData();
  return LspClient(sink: sink, input: input, server: server);
}
