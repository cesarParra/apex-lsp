import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('Workspace Completion', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: {},
      );
      client = createLspClient()..start();
      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    test('returns no completions when workspace has no classes', () async {
      final textWithPosition = extractCursorPosition('{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, hasNoCompletions);
    });
  });
}
