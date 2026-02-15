import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

import '../../support/cursor_utils.dart';

void main() {
  Future<CompletionList> complete(
    TextWithPosition textWithPosition, {
    required List<Declaration> index,
  }) {
    return onCompletion(
      text: textWithPosition.text,
      position: textWithPosition.position,
      index: index,
    );
  }

  group('enums', () {
    test('autocomplete enum types on empty file', () async {
      final enumType = IndexedEnum(DeclarationName('Foo'), values: []);
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocomplete enum types when typing a top level name', () async {
      final enumType = IndexedEnum(DeclarationName('Foo'), values: []);
      final completionList = await complete(
        extractCursorPosition('F{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocompletes all enum values', () async {
      final enumType = IndexedEnum(
        DeclarationName('Foo'),
        values: ['Bar'.enumValueMember(), 'Baz'.enumValueMember()],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'Bar')));
      expect(completionList.items, contains(CompletionItem(label: 'Baz')));
    });

    test('autocompletes all enum values by name', () async {
      final enumType = IndexedEnum(
        DeclarationName('Foo'),
        values: ['Bar'.enumValueMember(), 'Other'.enumValueMember()],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.B{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items, contains(CompletionItem(label: 'Bar')));
    });
  });

  group('variables', () {
    test('autocomplete variable names at top level', () async {
      final variable = IndexedVariable(
        DeclarationName('myVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myVar');
    });

    test('autocomplete variable names with prefix', () async {
      final variable = IndexedVariable(
        DeclarationName('myVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('my{cursor}'),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myVar');
    });

    test('mixed types and variables', () async {
      final enumType = IndexedEnum(DeclarationName('Foo'), values: []);
      final variable = IndexedVariable(
        DeclarationName('fooInstance'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('f{cursor}'),
        index: [enumType, variable],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'Foo')));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'fooInstance')),
      );
    });

    test('does not autocomplete variables declared after cursor', () async {
      // The variable is declared at bytes 20-40, but the cursor is at byte 5
      final variable = IndexedVariable(
        DeclarationName('laterVar'),
        typeName: DeclarationName('String'),
        location: (20, 40),
      );
      final completionList = await complete(
        extractCursorPosition('l{cursor}                                     '),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });
  });

  group('methods', () {
    test('autocomplete method names at top level', () async {
      final method = MethodDeclaration(
        DeclarationName('sampleMethod'),
        body: Block.empty(),
        isStatic: false,
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'sampleMethod');
    });

    test('autocomplete method names with a prefix', () async {
      final method = MethodDeclaration(
        DeclarationName('sampleMethod'),
        body: Block.empty(),
        isStatic: false,
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('sam{cursor}'),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'sampleMethod');
    });

    test('autocompletes methods declared after cursor', () async {
      final method = MethodDeclaration(
        DeclarationName('laterMethod'),
        body: Block.empty(),
        isStatic: false,
        location: (20, 40),
      );
      final completionList = await complete(
        extractCursorPosition('l{cursor}                                     '),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'laterMethod');
    });
  });

  group('method parameters', () {
    test('autocomplete parameter names', () async {
      final parameter = IndexedVariable(
        DeclarationName('paramVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test('autocomplete parameter names with prefix', () async {
      final parameter = IndexedVariable(
        DeclarationName('paramVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('par{cursor}'),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test('autocomplete members of a parameter typed as an interface', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
          MethodDeclaration(
            DeclarationName('saySomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final parameter = IndexedVariable(
        DeclarationName('paramVar'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('paramVar.{cursor}'),
        index: [interfaceType, parameter],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocomplete members of a parameter filtered by prefix', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
          MethodDeclaration(
            DeclarationName('saySomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final parameter = IndexedVariable(
        DeclarationName('paramVar'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('paramVar.do{cursor}'),
        index: [interfaceType, parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
    });

    test('parameter is completed when cursor is inside method body', () async {
      // Parameter at bytes 18-32, method body spans bytes 35-60
      final parameter = IndexedVariable(
        DeclarationName('paramVar'),
        typeName: DeclarationName('String'),
        location: (18, 32),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 60),
      );
      final completionList = await complete(
        // Cursor at byte 40, inside the method body
        extractCursorPosition(
          '                  Foo paramVar  {    p{cursor}                    }',
        ),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test(
      'parameter is not completed when cursor is outside method body',
      () async {
        // Parameter at bytes 18-32, method body spans bytes 35-60
        final parameter = IndexedVariable(
          DeclarationName('paramVar'),
          typeName: DeclarationName('String'),
          location: (18, 32),
          visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 60),
        );
        final completionList = await complete(
          extractCursorPosition(
            '                  Foo paramVar  {                           }  p{cursor}',
          ),
          index: [parameter],
        );

        expect(completionList.items, isEmpty);
      },
    );

    test(
      'variable inside method body is completed at cursor inside body',
      () async {
        // Variable at bytes 40-46, method body ends at byte 50
        final variable = IndexedVariable(
          DeclarationName('myTest'),
          typeName: DeclarationName('String'),
          location: (40, 46),
          visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
        );
        final completionList = await complete(
          // Cursor at byte 48, after the variable but inside the body
          extractCursorPosition(
            '                                        myTest  {cursor} }',
          ),
          index: [variable],
        );

        expect(completionList.items, hasLength(1));
        expect(completionList.items.first.label, 'myTest');
      },
    );

    test('variable inside method body is not completed outside body', () async {
      final variable = IndexedVariable(
        DeclarationName('myTest'),
        typeName: DeclarationName('String'),
        location: (40, 46),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
      );
      final completionList = await complete(
        // Cursor at byte 55, after the method body
        extractCursorPosition(
          '                                        myTest     }    m{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });
  });

  group('loop scoping', () {
    test('for loop init variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        DeclarationName('myIndex'),
        typeName: DeclarationName('Integer'),
        location: (5, 12),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 30),
      );
      final completionList = await complete(
        extractCursorPosition('     myIndex              }         my{cursor}'),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('for loop init variable is completed inside the for body', () async {
      final variable = IndexedVariable(
        DeclarationName('myIndex'),
        typeName: DeclarationName('Integer'),
        location: (5, 12),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        extractCursorPosition(
          '     myIndex        my{cursor}                  ',
        ),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myIndex');
    });

    test('enhanced for variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        DeclarationName('item'),
        typeName: DeclarationName('String'),
        location: (16, 20),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        // Cursor at byte 45, after the loop
        extractCursorPosition(
          'for (String item : items) {            }    i{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('while loop body variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        DeclarationName('loopVar'),
        typeName: DeclarationName('String'),
        location: (17, 24),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        // Cursor at byte 45, after the while loop
        extractCursorPosition(
          'while (true) {  loopVar                         }    l{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('nested block variable is not completed outside that block', () async {
      final innerVar = IndexedVariable(
        DeclarationName('innerVar'),
        typeName: DeclarationName('String'),
        location: (12, 20),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 30),
      );
      final outerVar = IndexedVariable(
        DeclarationName('outerVar'),
        typeName: DeclarationName('String'),
        location: (0, 8),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
      );
      final completionList = await complete(
        // Cursor at byte 35, after inner block but inside outer scope
        extractCursorPosition(
          'outerVar  { innerVar          }    {cursor}              ',
        ),
        index: [innerVar, outerVar],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'outerVar');
    });
  });

  group('interfaces', () {
    test('autocomplete interface types at top level', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [interfaceType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocompletes all interface methods via type name', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
          MethodDeclaration(
            DeclarationName('saySomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [interfaceType],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocompletes interface methods via variable', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
          MethodDeclaration(
            DeclarationName('saySomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final variable = IndexedVariable(
        DeclarationName('myVar'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myVar.{cursor}'),
        index: [interfaceType, variable],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocompletes interface methods filtered by prefix', () async {
      final interfaceType = IndexedInterface(
        DeclarationName('Foo'),
        methods: [
          MethodDeclaration(
            DeclarationName('doSomething'),
            body: Block.empty(),
            isStatic: false,
          ),
          MethodDeclaration(
            DeclarationName('saySomething'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final variable = IndexedVariable(
        DeclarationName('myVar'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myVar.do{cursor}'),
        index: [interfaceType, variable],
      );

      expect(completionList.items, hasLength(1));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
    });
  });

  group('classes', () {
    test('autocomplete classes types at top level', () async {
      final classType = IndexedClass(DeclarationName('Foo'));
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [classType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocomplete static class fields', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          FieldMember(DeclarationName('staticMember'), isStatic: true),
          FieldMember(DeclarationName('instanceMember'), isStatic: false),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('myFoo'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'staticMember');
    });

    test('autocomplete instance class fields', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          FieldMember(DeclarationName('staticMember'), isStatic: true),
          FieldMember(DeclarationName('instanceMember'), isStatic: false),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('myFoo'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myFoo.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'instanceMember');
    });

    test('autocomplete static class methods', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          MethodDeclaration(
            DeclarationName('staticMethod'),
            body: Block.empty(),
            isStatic: true,
          ),
          MethodDeclaration(
            DeclarationName('instanceMethod'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('myFoo'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'staticMethod');
    });

    test('autocomplete inner enums as static members', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedEnum(
            DeclarationName('Bar'),
            values: [
              'A'.enumValueMember(),
              'B'.enumValueMember(),
              'C'.enumValueMember(),
            ],
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [classType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Bar');
    });

    test('autocomplete inner interfaces as static members', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedInterface(
            DeclarationName('Bar'),
            methods: [
              MethodDeclaration(
                DeclarationName('doSomething'),
                body: Block.empty(),
                isStatic: false,
              ),
            ],
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [classType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Bar');
    });

    test('autocomplete inner interface methods via variable', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedInterface(
            DeclarationName('Bar'),
            methods: [
              MethodDeclaration(
                DeclarationName('m1'),
                body: Block.empty(),
                isStatic: false,
              ),
              MethodDeclaration(
                DeclarationName('m2'),
                body: Block.empty(),
                isStatic: false,
              ),
            ],
          ),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('sample'),
        typeName: DeclarationName('Foo.Bar'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('sample.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'm1')));
      expect(completionList.items, contains(CompletionItem(label: 'm2')));
    });

    test('autocomplete inner classes as static members', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedClass(
            DeclarationName('Bar'),
            members: [FieldMember(DeclarationName('name'), isStatic: false)],
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [classType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Bar');
    });

    test('autocomplete inner class members via variable', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedClass(
            DeclarationName('Bar'),
            members: [
              FieldMember(DeclarationName('name'), isStatic: false),
              MethodDeclaration(
                DeclarationName('doSomething'),
                body: Block.empty(),
                isStatic: false,
              ),
            ],
          ),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('sample'),
        typeName: DeclarationName('Foo.Bar'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('sample.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'name')));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
    });

    test('autocomplete inner enum values via qualified access', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          IndexedEnum(
            DeclarationName('Bar'),
            values: [
              'A'.enumValueMember(),
              'B'.enumValueMember(),
              'C'.enumValueMember(),
            ],
          ),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.Bar.{cursor}'),
        index: [classType],
      );

      expect(completionList.items, hasLength(3));
      expect(completionList.items, contains(CompletionItem(label: 'A')));
      expect(completionList.items, contains(CompletionItem(label: 'B')));
      expect(completionList.items, contains(CompletionItem(label: 'C')));
    });

    test(
      'marks list as incomplete with empty prefix and more than max items',
      () async {
        final types = List.generate(
          30,
          (i) => IndexedClass(DeclarationName('Type${i.toString().padLeft(2, '0')}')),
        );

        final completionList = await complete(
          extractCursorPosition('{cursor}'),
          index: types,
        );

        expect(completionList.isIncomplete, isTrue);
        expect(completionList.items, hasLength(maxCompletionItems));
      },
    );

    test('finds a specific type among more than 25 workspace types', () async {
      final types = List.generate(
        30,
        (i) => IndexedClass(DeclarationName('Type$i')),
      );
      final target = IndexedClass(DeclarationName('ZebraService'));

      final completionList = await complete(
        extractCursorPosition('Zeb{cursor}'),
        index: [...types, target],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'ZebraService');
    });

    test(
      'typing first letter finds type even with many other types',
      () async {
        final types = [
          for (final name in [
            'AccountService', 'AccountTrigger', 'AccountHelper',
            'BatchProcessor', 'BulkDataLoader',
            'ContactService', 'ContactTrigger', 'CaseManager',
            'DataFactory', 'DataMigration',
            'EmailService', 'EventHandler',
            'FieldMapper', 'FileUploader',
            'GroupManager', 'GlobalSettings',
            'HttpCallout', 'HistoryTracker',
            'IntegrationService', 'InvoiceGenerator',
            'JobScheduler', 'JsonParser',
            'KeyGenerator', 'KnowledgeService',
            'LeadConverter', 'LoggingService',
            'MetadataService', 'MockFactory',
            'NotificationService', 'NumberUtils',
            'OpportunityService', 'OrderProcessor',
          ])
            IndexedClass(DeclarationName(name)),
        ];

        final completionList = await complete(
          extractCursorPosition('N{cursor}'),
          index: types,
        );

        expect(completionList.items, hasLength(2));
        expect(
          completionList.items.map((item) => item.label).toList(),
          containsAll(['NotificationService', 'NumberUtils']),
        );
      },
    );

    test(
      'returns isIncomplete true on empty prefix with many types so '
      'client re-requests on each keystroke',
      () async {
        final types = List.generate(
          30,
          (i) => IndexedClass(DeclarationName('Class$i')),
        );

        // Empty prefix: client opens autocomplete popup
        final initial = await complete(
          extractCursorPosition('{cursor}'),
          index: types,
        );
        // Must be incomplete so client doesn't cache and filter locally
        expect(initial.isIncomplete, isTrue);

        // User types "Class2" — only 11 match (Class2, Class20..Class29)
        final filtered = await complete(
          extractCursorPosition('Class2{cursor}'),
          index: types,
        );
        expect(filtered.isIncomplete, isFalse);
        expect(filtered.items, hasLength(11));
        expect(
          filtered.items.map((item) => item.label),
          contains('Class29'),
        );
      },
    );

    test(
      'marks list as incomplete when filtered results exceed max items',
      () async {
        // 30 types all starting with "Type" — more than maxCompletionItems
        final types = List.generate(
          30,
          (i) => IndexedClass(DeclarationName('Type${i.toString().padLeft(2, '0')}')),
        );

        final completionList = await complete(
          extractCursorPosition('Type{cursor}'),
          index: types,
        );

        expect(completionList.isIncomplete, isTrue);
        expect(completionList.items, hasLength(maxCompletionItems));
      },
    );

    test(
      'narrows results when prefix becomes more specific',
      () async {
        // 30 types all starting with "Type"
        final types = List.generate(
          30,
          (i) => IndexedClass(DeclarationName('Type${i.toString().padLeft(2, '0')}')),
        );

        // Broad prefix: "Type" matches all 30, returns 25 (incomplete)
        final broad = await complete(
          extractCursorPosition('Type{cursor}'),
          index: types,
        );
        expect(broad.isIncomplete, isTrue);

        // Specific prefix: "Type2" matches Type20-Type29 (10 items)
        final specific = await complete(
          extractCursorPosition('Type2{cursor}'),
          index: types,
        );
        expect(specific.isIncomplete, isFalse);
        expect(specific.items, hasLength(10));
        expect(
          specific.items.map((item) => item.label),
          contains('Type29'),
        );
      },
    );

    test('autocomplete instance class methods', () async {
      final classType = IndexedClass(
        DeclarationName('Foo'),
        members: [
          MethodDeclaration(
            DeclarationName('staticMethod'),
            body: Block.empty(),
            isStatic: true,
          ),
          MethodDeclaration(
            DeclarationName('instanceMethod'),
            body: Block.empty(),
            isStatic: false,
          ),
        ],
      );
      final localVariable = IndexedVariable(
        DeclarationName('myFoo'),
        typeName: DeclarationName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myFoo.{cursor}'),
        index: [classType, localVariable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'instanceMethod');
    });
  });
}
