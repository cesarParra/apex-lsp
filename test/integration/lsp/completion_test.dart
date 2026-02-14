import 'package:test/test.dart';

import '../../support/cursor_utils.dart';
import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('LSP Completion', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: {
          'Foo.cls': '''
public class Foo {
  public static void hello() {}
}''',
          'Season.cls': 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          'Greeter.cls': '''
public interface Greeter {
  String greet();
  void sayGoodbye();
}''',
        },
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

    test('completes local variables', () async {
      final textWithPosition = extractCursorPosition('''
String myVariable = 'hello';
my{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('myVariable'));
    });

    test('completes locally declared enums', () async {
      final textWithPosition = extractCursorPosition('''
public enum Color { RED, GREEN, BLUE }
{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletions(['Color']));
    });

    group('classes', () {
      group('referencing a class from outside', () {
        test('completes locally declared classes', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {}
      {cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletions(['Animal']));
        });

        test('completes static class fields', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String instanceVar;
        static String staticVar;
      }
      Animal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('staticVar'));
          expect(completions, doesNotContainCompletion('instanceVar'));
        });

        test('completes instance class fields', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String instanceVar;
        static String staticVar;
      }
      Animal sampleAnimal;
      sampleAnimal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('instanceVar'));
          expect(completions, doesNotContainCompletion('staticVar'));
        });

        test('completes static class methods', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String instanceMethod() {}
        static String staticMethod() {};
      }
      Animal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('staticMethod'));
          expect(completions, doesNotContainCompletion('instanceMethod'));
        });

        test('completes instance class methods', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String instanceMethod() {}
        static String staticMethod() {};
      }
      Animal sampleAnimal;
      sampleAnimal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('instanceMethod'));
          expect(completions, doesNotContainCompletion('staticMethod'));
        });

        test('completes inner enums as static members', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public Enum Status { ACTIVE, INACTIVE }
      }
      Animal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('Status'));
        });

        test('completes inner enum values via qualified access', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public Enum Status { ACTIVE, INACTIVE }
      }
      Animal.Status.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('ACTIVE'));
          expect(completions, containsCompletion('INACTIVE'));
        });

        test('completes inner interface methods via variable', () async {
          final textWithPosition = extractCursorPosition('''
      public class Foo {
        public interface Bar {
          String m1();
          void m2();
        }
      }
      Foo.Bar sample;
      sample.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('m1'));
          expect(completions, containsCompletion('m2'));
        });

        test('completes inner classes as static members', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public class Leg {
          String name;
        }
      }
      Animal.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('Leg'));
        });

        test('completes inner class members via variable', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public class Leg {
          String name;
          void move() {}
        }
      }
      Animal.Leg sample;
      sample.{cursor}''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('name'));
          expect(completions, containsCompletion('move'));
        });
      });

      group('references from within a class', () {
        test('completes fields from the top level of the class', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String instanceVar;
        static String staticVar;
        {cursor}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('staticVar'));
          expect(completions, containsCompletion('instanceVar'));
        });

        test('completes methods from the top level of the class', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        String fooMethod() {};
        {cursor}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('fooMethod'));
        });

        test('completes from static initializer', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        static {
          {cursor}
        }

        static String fooMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('fooMethod'));
        });

        test('completes from static initializer - for loops', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        static {
          for (Integer myIndex; {cursor})
        }

        static String fooMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('myIndex'));
        });

        test('completes members from constructors', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public Animal() {
          {cursor}
        }

        static String fooMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('fooMethod'));
        });

        test('completes received arguments from constructors', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public Animal(String myArg) {
          {cursor}
        }

        static String fooMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('myArg'));
        });

        test('completes local declarations in constructors', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public Animal(String myArg) {
          String somethingDeclaredInBlock;
          {cursor}
        }

        static String fooMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('somethingDeclaredInBlock'));
        });

        test('completes members from methods', () async {
          final textWithPosition = extractCursorPosition('''
      public class Animal  {
        public String foo() {
          {cursor}
        }

        String barMethod() {}
      }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('barMethod'));
        });

        test('completes received arguments from methods', () async {
          final textWithPosition = extractCursorPosition('''
        public class Animal  {
          public String foo(String myArg) {
            {cursor}
          }
        }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('myArg'));
        });

        test('completes local declarations in methods', () async {
          final textWithPosition = extractCursorPosition('''
        public class Animal  {
          public void foo(String myArg) {
            String somethingDeclaredInBlock;
            {cursor}
          }
        }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('somethingDeclaredInBlock'));
        });

        test('completes `this` references', () async {
          final textWithPosition = extractCursorPosition('''
        public class Animal  {
          public void bar() {}
          public void foo(String myArg) {
            this.{cursor};
          }
        }''');
          final document = Document.withText(textWithPosition.text);
          await client.openDocument(document);

          final completions = await client.completion(
            uri: document.uri,
            line: textWithPosition.position.line,
            character: textWithPosition.position.character,
          );

          expect(completions, containsCompletion('bar'));
        });
      });
    });

    test('completes enum values via dot access', () async {
      final textWithPosition = extractCursorPosition('''
public enum Season { SPRING, SUMMER, FALL, WINTER }
Season.{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        containsCompletions(['SPRING', 'SUMMER', 'FALL', 'WINTER']),
      );
    });

    test('completes interface methods via dot access', () async {
      final textWithPosition = extractCursorPosition('''
public interface Greeter {
  String greet();
  void sayGoodbye();
}
Greeter g;
g.{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletions(['greet', 'sayGoodbye']));
    });

    test('returns empty completions for empty context', () async {
      const text = '';
      final document = Document.withText(text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: 0,
        character: 0,
      );

      expect(completions, hasNoCompletions);
    });

    test('completions update after document change', () async {
      const documentUri = 'file:///test/anon.apex';
      final initialTextWithPosition = extractCursorPosition('''
String firstName = 'a';
fir{cursor}''');
      await client.openDocument(
        Document(uri: documentUri, text: initialTextWithPosition.text),
      );

      final first = await client.completion(
        uri: documentUri,
        line: initialTextWithPosition.position.line,
        character: initialTextWithPosition.position.character,
      );
      expect(first, containsCompletion('firstName'));

      final updatedTextWithPosition = extractCursorPosition('''
Integer count = 0;
cou{cursor}''');
      await client.changeDocument(
        Document(uri: documentUri, text: updatedTextWithPosition.text),
      );

      final second = await client.completion(
        uri: documentUri,
        line: updatedTextWithPosition.position.line,
        character: updatedTextWithPosition.position.character,
      );
      expect(second, containsCompletion('count'));
    });
  });
}
