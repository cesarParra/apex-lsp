import 'dart:io';

import 'package:apex_lsp/version.dart';
import 'package:test/test.dart';

import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('LSP Initialization', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          (
            name: 'Foo.cls',
            source: await readFixture('initialize_and_completion/Foo.cls'),
          ),
        ],
      );
      client = createLspClient()..start();
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    test('client can initialize', () async {
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: false,
      );

      expect(result, hasCapability('completionProvider'));
      expect(result, hasCapability('textDocumentSync'));
      expect(result.serverInfo, isNotNull);
      expect(result.serverInfo?.version, equals(packageVersion));
    });

    test(
      'fails with error response when request sent before initialize',
      () async {
        final response = await client.sendRawRequest(
          method: 'textDocument/completion',
          params: {
            'textDocument': {'uri': 'file:///does/not/matter'},
            'position': {'line': 0, 'character': 0},
          },
        );

        expect(response, isLspError(-32002));
        expect(response, isLspErrorWithMessage('Server not initialized'));
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test('receives indexing updates after initialization', () async {
      // Success without timeout proves indexing works — waitForIndexing
      // waits for the $/progress end notification.
      final result = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      expect(result, hasCapability('completionProvider'));
    });
  });

  group('.gitignore management', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace();
      client = createLspClient()..start();
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    test('adds .sf-zed to .gitignore when file exists without it', () async {
      final gitignore = File('${workspace.directory.path}/.gitignore');
      await gitignore.writeAsString('node_modules/\n*.log\n');

      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );

      final contents = await gitignore.readAsString();
      expect(contents, contains('.sf-zed'));
    });

    test('does not duplicate .sf-zed if already in .gitignore', () async {
      final gitignore = File('${workspace.directory.path}/.gitignore');
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
      final gitignore = File('${workspace.directory.path}/.gitignore');
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
