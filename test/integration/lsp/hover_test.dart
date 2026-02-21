import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('LSP Hover', () {
    late TestWorkspace workspace;
    late LspClient client;
    late InitializeResult initResult;

    setUp(() async {
      workspace = await createTestWorkspace();
      client = createLspClient()..start();
      initResult = await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    group('hoverProvider capability', () {
      test('server advertises hoverProvider in capabilities', () {
        expect(initResult, hasCapability('hoverProvider'));
      });
    });

    group('User Story 2.1 — local variables', () {
      test('hover over variable name shows its type', () async {
        // Place {cursor} inside the variable name so the position is derived
        // directly from the marker rather than being hard-coded.
        final textWithPosition = extractCursorPosition(
          'String my{cursor}Variable = null;',
        );
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('String'));
        expect(hoverResult, contains('myVariable'));
      });
    });

    group('User Story 2.2 — methods', () {
      test('hover over method name shows return type and parameters', () async {
        const source = '''
public class MyClass {
  public void doWork(String input) {}
}
''';
        final document = Document.withText(source);
        await client.openDocument(document);

        // 'doWork' starts at line 1, character 14
        final hoverResult = await client.hover(
          uri: document.uri,
          line: 1,
          character: 14,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('doWork'));
        expect(hoverResult, contains('void'));
        expect(hoverResult, contains('String'));
        expect(hoverResult, contains('input'));
      });
    });

    group('User Story 2.3 — class names', () {
      test('hover over class name shows class declaration summary', () async {
        const source = '''
public class Account {}
Account a;
''';
        final document = Document.withText(source);
        await client.openDocument(document);

        // 'Account' on line 0, character 13
        final hoverResult = await client.hover(
          uri: document.uri,
          line: 0,
          character: 13,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('class'));
        expect(hoverResult, contains('Account'));
      });

      test('hover over enum name shows enum declaration', () async {
        const source = '''
public enum Status { ACTIVE, INACTIVE }
Status s;
''';
        final document = Document.withText(source);
        await client.openDocument(document);

        // 'Status' on line 0, character 12
        final hoverResult = await client.hover(
          uri: document.uri,
          line: 0,
          character: 12,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('enum'));
        expect(hoverResult, contains('Status'));
      });
    });

    group('User Story 2.4 — workspace symbols', () {
      test('hover over workspace class shows same content as local', () async {
        final ws = await createTestWorkspace(
          classFiles: [
            (
              name: 'Customer.cls',
              source: 'public class Customer { public String name; }',
            ),
          ],
        );
        final c = createLspClient()..start();
        await c.initialize(workspaceUri: ws.uri, waitForIndexing: true);

        const source = 'Customer cust;';
        final document = Document.withText(source);
        await c.openDocument(document);

        // 'Customer' starts at offset 0, line 0
        final hoverResult = await c.hover(
          uri: document.uri,
          line: 0,
          character: 0,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('Customer'));

        await c.dispose();
        await deleteTestWorkspace(ws);
      });
    });

    group('User Story 2.5 — unresolvable symbols', () {
      test('hovering over unknown symbol returns null, not an error', () async {
        const source = 'UnknownType x;';
        final document = Document.withText(source);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: 0,
          character: 0,
        );

        // Should be null (no hover), not an exception
        expect(hoverResult, isNull);
      });

      test('hovering on a document that is not open returns null', () async {
        final hoverResult = await client.hover(
          uri: 'file:///not/opened.cls',
          line: 0,
          character: 0,
        );

        expect(hoverResult, isNull);
      });
    });
  });
}
