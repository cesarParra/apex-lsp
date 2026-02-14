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
        classFiles: {
          'Foo.cls': await readFixture(
            'initialize_and_completion/Foo.cls',
          ),
        },
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
}
