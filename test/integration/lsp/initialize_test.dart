import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('During initialization, the server', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      client = await createInitializedClient();
      workspace = client.workspace!;
    });

    tearDown(() async {
      await client.dispose();
    });

    test('provides its name', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result.serverInfo?.name, equals('apex-lsp'));
    });

    test('provides its version', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result.serverInfo?.version, isNotNull);
    });

    test('provides completions', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result, hasCapability('completionProvider'));
    });

    test('provides hover', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result, hasCapability('hoverProvider'));
    });

    test('provides textDocumentSync', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result, hasCapability('textDocumentSync'));
    });

    test(
      'advertises save notifications in textDocumentSync capabilities',
      () async {
        final result = await client.initialize(
          workspaceUri: workspace.uri,
          waitForIndexing: false,
        );

        final sync = result.capabilities.textDocumentSync;
        expect(sync.change, equals(1));
        expect(sync.save, isTrue);
      },
    );

    test('receives indexing updates after initialization', () async {
      // Success without timeout proves indexing works -- waitForIndexing
      // waits for the $/progress end notification.
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      expect(result, hasCapability('completionProvider'));
    });
  });

  group('when interacting before initialization', () {
    test(
      'the server fails with error response when request sent before initialize',
      () async {
        final result = createLspClient();
        final client = result.client..start();
        final response = await client.sendRawRequest(
          method: 'textDocument/completion',
          params: {
            'textDocument': {'uri': 'file:///does/not/matter'},
            'position': {'line': 0, 'character': 0},
          },
        );

        expect(response, isLspError(-32002));
        expect(response, isLspErrorWithMessage('Server not initialized'));

        await client.dispose();
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });

  group('.gitignore management', () {
    late TestWorkspace workspace;
    late LspClient client;
    late MemoryFileSystem fileSystem;

    setUp(() async {
      final result = createLspClient();
      client = result.client..start();
      fileSystem = result.fileSystem;
      workspace = await createTestWorkspace(fileSystem: fileSystem);
    });

    tearDown(() async {
      await client.dispose();
    });

    test('adds .sf-zed to .gitignore when file exists without it', () async {
      final gitignore = fileSystem.file(
        '${workspace.directory.path}/.gitignore',
      );
      await gitignore.writeAsString('node_modules/\n*.log\n');

      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      final contents = await gitignore.readAsString();
      expect(contents, contains('.sf-zed'));
    });

    test('does not duplicate .sf-zed if already in .gitignore', () async {
      final gitignore = fileSystem.file(
        '${workspace.directory.path}/.gitignore',
      );
      await gitignore.writeAsString('node_modules/\n.sf-zed\n');

      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      final contents = await gitignore.readAsString();
      final occurrences = '.sf-zed'.allMatches(contents).length;
      expect(occurrences, equals(1));
    });

    test('creates .gitignore with .sf-zed when no .gitignore exists', () async {
      final gitignore = fileSystem.file(
        '${workspace.directory.path}/.gitignore',
      );
      expect(await gitignore.exists(), isFalse);

      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      expect(await gitignore.exists(), isTrue);
      final contents = await gitignore.readAsString();
      expect(contents, contains('.sf-zed'));
    });
  });
}
