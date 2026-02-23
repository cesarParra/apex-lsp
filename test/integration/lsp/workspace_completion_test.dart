import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

import '../../support/completion_matchers.dart';
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
      workspace = await createTestWorkspace();
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

    test(
      'returns no declaration completions when workspace has no classes',
      () async {
        final textWithPosition = extractCursorPosition('{cursor}');
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final completions = await client.completion(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(completions, containsCompletion('if'));
      },
    );
  });

  group('Workspace Completion with indexed types', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          (
            name: 'Season.cls',
            source: 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          ),
        ],
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

    test('completes workspace enum name at top level', () async {
      final textWithPosition = extractCursorPosition('Sea{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('Season'));
    });

    test('completes workspace enum values via dot access', () async {
      final textWithPosition = extractCursorPosition('Season.{cursor}');
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
  });

  group('Workspace Completion with indexed interfaces', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          (
            name: 'Greeter.cls',
            source:
                'public interface Greeter { String greet(); void sayGoodbye(); }',
          ),
        ],
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

    test('completes workspace interface name at top level', () async {
      final textWithPosition = extractCursorPosition('Gre{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('Greeter'));
    });

    test(
      'completes workspace interface methods via variable dot access',
      () async {
        final textWithPosition = extractCursorPosition('''
Greeter myVar;
myVar.{cursor}''');
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final completions = await client.completion(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(completions, containsCompletions(['greet', 'sayGoodbye']));
      },
    );
  });

  group('Workspace Completion with indexed classes', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          (
            name: 'Animal.cls',
            source: '''
public class Animal {
  String instanceVar;
  static String staticVar;
  String instanceMethod() {}
  static String staticMethod() {}
  public Enum Status { ACTIVE, INACTIVE }
  public interface Walkable { void walk(); String pace(); }
  public class Leg { String name; void move() {} }
}''',
          ),
        ],
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

    test('completes workspace class name at top level', () async {
      final textWithPosition = extractCursorPosition('Ani{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('Animal'));
    });

    test('completes static class fields', () async {
      final textWithPosition = extractCursorPosition('Animal.{cursor}');
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
      final textWithPosition = extractCursorPosition('Animal.{cursor}');
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
      final textWithPosition = extractCursorPosition('Animal.{cursor}');
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
      final textWithPosition = extractCursorPosition('Animal.Status.{cursor}');
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
Animal.Walkable sample;
sample.{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('walk'));
      expect(completions, containsCompletion('pace'));
    });

    test('completes inner classes as static members', () async {
      final textWithPosition = extractCursorPosition('Animal.{cursor}');
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

  group('Workspace Completion with many indexed types', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          for (var i = 0; i < 30; i++)
            (
              name: 'Class${i.toString().padLeft(2, '0')}.cls',
              source: 'public class Class${i.toString().padLeft(2, '0')} {}',
            ),
        ],
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

    test('finds type not in initial top 25 after narrowing prefix', () async {
      final textWithPosition = extractCursorPosition('Class2{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(completions, containsCompletion('Class29'));
    });
  });

  group('Workspace Completion kind and detail', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: [
          (
            name: 'Season.cls',
            source: 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          ),
          (
            name: 'Greeter.cls',
            source:
                'public interface Greeter { String greet(); void sayGoodbye(); }',
          ),
          (
            name: 'Animal.cls',
            source: '''
public class Animal {
  String name;
  static Integer count;
  void speak() {}
}''',
          ),
        ],
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

    test('workspace class has classKind and "Class" detail', () async {
      final textWithPosition = extractCursorPosition('Ani{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        completionWith(
          label: 'Animal',
          kind: CompletionItemKind.classKind,
          detail: 'Class',
        ),
      );
    });

    test('workspace enum has enumKind and "Enum" detail', () async {
      final textWithPosition = extractCursorPosition('Sea{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        completionWith(
          label: 'Season',
          kind: CompletionItemKind.enumKind,
          detail: 'Enum',
        ),
      );
    });

    test(
      'workspace interface has interfaceKind and "Interface" detail',
      () async {
        final textWithPosition = extractCursorPosition('Gre{cursor}');
        final document = Document.withText(textWithPosition.text);
        await client.openDocument(document);

        final completions = await client.completion(
          uri: document.uri,
          line: textWithPosition.position.line,
          character: textWithPosition.position.character,
        );

        expect(
          completions,
          completionWith(
            label: 'Greeter',
            kind: CompletionItemKind.interfaceKind,
            detail: 'Interface',
          ),
        );
      },
    );

    test('workspace enum values have enumMember kind', () async {
      final textWithPosition = extractCursorPosition('Season.{cursor}');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        completionWith(
          label: 'SPRING',
          kind: CompletionItemKind.enumMember,
          detail: 'Season',
        ),
      );
    });

    test('workspace instance field has field kind and type detail', () async {
      final textWithPosition = extractCursorPosition('''
Animal a;
a.{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        completionWith(
          label: 'name',
          kind: CompletionItemKind.field,
          detail: 'String',
        ),
      );
    });

    test('workspace instance method has method kind', () async {
      final textWithPosition = extractCursorPosition('''
Animal a;
a.{cursor}''');
      final document = Document.withText(textWithPosition.text);
      await client.openDocument(document);

      final completions = await client.completion(
        uri: document.uri,
        line: textWithPosition.position.line,
        character: textWithPosition.position.character,
      );

      expect(
        completions,
        completionWithKind('speak', CompletionItemKind.method),
      );
      expect(
        completions,
        completionWithLabelDetails(
          label: 'speak',
          detail: '()',
          description: 'void',
        ),
      );
    });
  });
}
