import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_client.dart';
import '../integration_server.dart';

void main() {
  group('When hovering', () {
    group('over local declarations', () {
      late LspClient client;

      setUp(() async {
        client = await createInitializedClient();
      });

      tearDown(() async {
        await client.dispose();
      });

      test('a variable name shows its type', () async {
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

      test('a local variable in method body shows type', () async {
        const source = '''
      public class TestClass {
        public void setIsInListLiteral() {
          String myLocalString;
          System.debug(myLoca{cursor}lString);
        }
      }
      ''';

        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(
          hoverResult,
          isNotNull,
          reason: 'Should resolve local variable within method',
        );
        expect(hoverResult, contains('String'));
        expect(hoverResult, contains('myLocalString'));
      });

      test('hover before declaration returns null', () async {
        const source = '''
        public class TestClass {
          public void test() {
            x = my{cursor}Var;
            String myVar;
          }
        }
        ''';

        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(
          hoverResult,
          isNull,
          reason: 'Variable should not be visible before declaration',
        );
      });

      test('hover outside scope returns null', () async {
        const source = '''
        public class TestClass {
          public void test() {
            {
              String scopedVar;
            }
            x = scoped{cursor}Var;
          }
        }
        ''';

        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(
          hoverResult,
          isNull,
          reason: 'Variable should not be visible outside its scope',
        );
      });

      test('hover over method name shows return type and parameters', () async {
        const source = '''
public class MyClass {
  public void do{cursor}Work(String input) {}
}
''';
        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('doWork'));
        expect(hoverResult, contains('void'));
        expect(hoverResult, contains('String'));
        expect(hoverResult, contains('input'));
      });

      test('hover over class name shows class declaration summary', () async {
        const source = '''
public class Acco{cursor}unt {}
Account a;
''';
        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('class'));
        expect(hoverResult, contains('Account'));
      });

      test('hover over enum name shows enum declaration', () async {
        const source = '''
public enum Sta{cursor}tus { ACTIVE, INACTIVE }
Status s;
''';
        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('enum'));
        expect(hoverResult, contains('Status'));
      });
    });

    group('over workspace declarations', () {
      test('hover over workspace class shows same content as local', () async {
        final client = await createInitializedClient(
          classFiles: [
            (
              name: 'Customer.cls',
              source: 'public class Customer { public String name; }',
            ),
          ],
        );

        final textWithPosition = extractCursorPosition(
          '{cursor}Customer cust;',
        );
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(hoverResult, contains('Customer'));

        await client.dispose();
      });
    });

    group('shadowing', () {
      test('parameter shadows workspace class with similar name', () async {
        final client = await createInitializedClient(
          classFiles: [(name: 'Token.cls', source: 'public class Token { }')],
        );

        const source = '''
public class Parser {
  public virtual Object visit(Parser {cursor}token) {}
}
''';
        final textWithPosition = extractCursorPosition(source);
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final hoverResult = await client.hover(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(hoverResult, isNotNull);
        expect(
          hoverResult,
          contains('Parser'),
          reason: 'Should show parameter type Parser',
        );
        expect(
          hoverResult,
          contains('token'),
          reason: 'Should show parameter name token',
        );
        expect(
          hoverResult,
          isNot(contains('class Token')),
          reason: 'Should not resolve to workspace Token class',
        );

        await client.dispose();
      });

      //   test(
      //     'local variable with same name as workspace class resolves to variable',
      //     () async {
      //       final result = createLspClient();
      //       final c = result.client..start();
      //       final ws = await createTestWorkspace(
      //         fileSystem: result.fileSystem,
      //         classFiles: [
      //           (name: 'Account.cls', source: 'public class Account { }'),
      //         ],
      //       );
      //       await c.initialize(workspaceUri: ws.uri, waitForIndexing: true);

      //       const source = '''
      // public class TestClass {
      //   public void test() {
      //     String account;
      //     System.debug(account);
      //   }
      // }
      // ''';
      //       final document = Document.withText(source);
      //       await c.openDocument(document);

      //       // Hover over 'account' variable usage (line 3)
      //       final hoverResult = await c.hover(
      //         uri: document.uri,
      //         line: 3,
      //         character: 18,
      //       );

      //       expect(hoverResult, isNotNull);
      //       expect(
      //         hoverResult,
      //         contains('String'),
      //         reason: 'Should show variable type String',
      //       );
      //       expect(
      //         hoverResult,
      //         contains('account'),
      //         reason: 'Should show variable name',
      //       );
      //       expect(
      //         hoverResult,
      //         isNot(contains('class Account')),
      //         reason: 'Should not resolve to workspace Account class',
      //       );

      //       await c.dispose();
      //     },
      //   );
    });

    // group('unresolvable symbols', () {
    //   test('hovering over unknown symbol returns null, not an error', () async {
    //     const source = 'UnknownType x;';
    //     final document = Document.withText(source);
    //     await client.openDocument(document);

    //     final hoverResult = await client.hover(
    //       uri: document.uri,
    //       line: 0,
    //       character: 0,
    //     );

    //     // Should be null (no hover), not an exception
    //     expect(hoverResult, isNull);
    //   });

    //   test('hovering on a document that is not open returns null', () async {
    //     final hoverResult = await client.hover(
    //       uri: 'file:///not/opened.cls',
    //       line: 0,
    //       character: 0,
    //     );

    //     expect(hoverResult, isNull);
    //   });
    // });
  });
}
