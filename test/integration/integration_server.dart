import 'dart:io';

import 'package:apex_lsp/cancellation_tracker.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/documents/open_documents.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/workspace_indexer/workspace_indexer.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:apex_lsp/message_reader.dart';
import 'package:apex_lsp/server.dart';
import 'package:file/memory.dart';

import '../support/fake_platform.dart';
import '../support/lsp_client.dart';
import '../support/lsp_test_harness.dart';
import '../support/test_workspace.dart';

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
  MemoryFileSystem fileSystem,
});

IntegrationData createIntegrationData({MemoryFileSystem? fileSystem}) {
  final input = InMemoryLspInput(sync: true);
  final sink = InMemoryByteSink();
  final fs = fileSystem ?? MemoryFileSystem();
  final platform = FakeLspPlatform();
  final integrationServer = Server(
    output: LspOut(output: sink),
    reader: MessageReader(input.stream),
    exitFn: (code) => throw _ExitCalled(code),
    openDocuments: OpenDocuments(),
    localIndexer: LocalIndexer(bindings: _bindings),
    workspaceIndexer: WorkspaceIndexer(
      sfdxWorkspaceLocator: SfdxWorkspaceLocator(
        fileSystem: fs,
        platform: platform,
      ),
      fileSystem: fs,
      platform: platform,
    ),
    cancellationTracker: CancellationTracker(),
    fileSystem: fs,
    platform: platform,
  );
  return (server: integrationServer, sink: sink, input: input, fileSystem: fs);
}

// TODO: Remove this endpoint
({LspClient client, MemoryFileSystem fileSystem}) createLspClient({
  MemoryFileSystem? fileSystem,
}) {
  final (:server, :sink, :input, fileSystem: fs) = createIntegrationData(
    fileSystem: fileSystem,
  );
  return (
    client: LspClient(sink: sink, input: input, server: server),
    fileSystem: fs,
  );
}

Future<LspClient> createInitializedClient({
  MemoryFileSystem? fileSystem,
  List<ClassFile> classFiles = const [],
  List<SObjectFile> objectFiles = const [],
  TestWorkspace? workspace,
}) async {
  final (:server, :sink, :input, fileSystem: fs) = createIntegrationData(
    fileSystem: fileSystem,
  );

  final resolvedWorkspace =
      workspace ??
      await createTestWorkspace(
        fileSystem: fs,
        classFiles: classFiles,
        objectFiles: objectFiles,
      );
  final client = LspClient(
    sink: sink,
    input: input,
    server: server,
    workspace: resolvedWorkspace,
  )..start();
  await client.initialize(waitForIndexing: true);
  return client;
}
