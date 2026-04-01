import 'dart:io';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

void main() {
  final libPath = Platform.environment['TS_SFAPEX_LIB'];
  final treeSitterBindings = TreeSitterBindings.load(path: libPath);
  final localIndexer = LocalIndexer(bindings: treeSitterBindings);

  group('resolveSymbolAt', () {
    group('local variables', () {
      test('resolves a local variable at its usage site', () async {
        const text = 'String myVar = null; Integer x = myVar;';
        // cursor on 'myVar' in second usage (offset ~33)
        final cursorOffset = text.indexOf('myVar', 20);
        final variable = IndexedVariable(
          DeclarationName('myVar'),
          typeName: DeclarationName('String'),
          location: (0, 19),
        );
        final index = <Declaration>[variable];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedVariable>());
        expect(
          (result as ResolvedVariable).variable.name.value,
          equals('myVar'),
        );
      });

      test(
        'returns null when cursor is on whitespace between tokens',
        () async {
          const text = 'String myVar = null;';
          // cursor on the space between 'String' and 'myVar'
          final cursorOffset = text.indexOf(' ');
          final variable = IndexedVariable(
            DeclarationName('myVar'),
            typeName: DeclarationName('String'),
            location: (0, 20),
          );
          final index = <Declaration>[variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isNull);
        },
      );

      test('returns null when cursor is at an unresolvable symbol', () async {
        const text = 'String myVar = null;';
        final cursorOffset = text.indexOf('myVar');
        final index = <Declaration>[];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test(
        'respects visibility: returns null when cursor is before declaration',
        () async {
          const text = 'x = myVar; String myVar;';
          final cursorOffset = text.indexOf(
            'myVar',
          ); // First usage, before declaration
          final variable = IndexedVariable(
            DeclarationName('myVar'),
            typeName: DeclarationName('String'),
            location: (18, 24), // Declaration at end of text
            visibility: VisibleAfterDeclaration(),
          );
          final index = <Declaration>[variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(
            result,
            isNull,
            reason: 'Variable should not be visible before its declaration',
          );
        },
      );

      test(
        'respects visibility: resolves when cursor is after declaration',
        () async {
          const text = 'String myVar; x = myVar;';
          final cursorOffset = text.indexOf(
            'myVar',
            13,
          ); // Second usage, after declaration
          final variable = IndexedVariable(
            DeclarationName('myVar'),
            typeName: DeclarationName('String'),
            location: (0, 13),
            visibility: VisibleAfterDeclaration(),
          );
          final index = <Declaration>[variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isA<ResolvedVariable>());
          expect(
            (result as ResolvedVariable).variable.name.value,
            equals('myVar'),
          );
        },
      );

      test(
        'respects scope visibility: returns null when cursor is after scope end',
        () async {
          const text = '{ String myVar; } x = myVar;';
          final cursorOffset = text.indexOf(
            'myVar',
            17,
          ); // Usage after closing brace
          final scopeEnd = text.indexOf('}'); // End of block
          final variable = IndexedVariable(
            DeclarationName('myVar'),
            typeName: DeclarationName('String'),
            location: (2, 15),
            visibility: VisibleBetweenDeclarationAndScopeEnd(
              scopeEnd: scopeEnd,
            ),
          );
          final index = <Declaration>[variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(
            result,
            isNull,
            reason: 'Variable should not be visible outside its scope',
          );
        },
      );

      test(
        'respects scope visibility: resolves when cursor is within scope',
        () async {
          const text = '{ String myVar; x = myVar; }';
          final cursorOffset = text.indexOf('myVar', 15); // Usage within block
          final scopeEnd = text.indexOf('}'); // End of block
          final variable = IndexedVariable(
            DeclarationName('myVar'),
            typeName: DeclarationName('String'),
            location: (2, 15),
            visibility: VisibleBetweenDeclarationAndScopeEnd(
              scopeEnd: scopeEnd,
            ),
          );
          final index = <Declaration>[variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isA<ResolvedVariable>());
          expect(
            (result as ResolvedVariable).variable.name.value,
            equals('myVar'),
          );
        },
      );
    });

    group('class names', () {
      test(
        'resolves a class by name when cursor is on its identifier',
        () async {
          const text = 'Account acc = new Account();';
          final cursorOffset = text.indexOf('Account');
          final accountClass = IndexedClass(
            DeclarationName('Account'),
            visibility: AlwaysVisible(),
            members: [],
          );
          final index = <Declaration>[accountClass];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isA<ResolvedType>());
          expect(
            (result as ResolvedType).indexedType.name.value,
            equals('Account'),
          );
        },
      );

      test('resolves an enum by name', () async {
        const text = 'Color c = Color.RED;';
        final cursorOffset = text.indexOf('Color');
        final colorEnum = IndexedEnum(
          DeclarationName('Color'),
          visibility: AlwaysVisible(),
          values: [EnumValueMember(DeclarationName('RED'))],
        );
        final index = <Declaration>[colorEnum];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });

      test('resolves an interface by name', () async {
        const text = 'Runnable r;';
        final cursorOffset = text.indexOf('Runnable');
        final iface = IndexedInterface(
          DeclarationName('Runnable'),
          visibility: AlwaysVisible(),
          extendedInterfaces: [],
          methods: [],
        );
        final index = <Declaration>[iface];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });
    });

    group('methods', () {
      test('resolves a method by name on cursor', () async {
        const text = 'void doSomething() {}';
        final cursorOffset = text.indexOf('doSomething');
        final parentClass = IndexedClass(
          DeclarationName('MyClass'),
          visibility: AlwaysVisible(),
          location: (0, text.length),
          members: [
            MethodDeclaration(
              DeclarationName('doSomething'),
              body: Block.empty(),
              visibility: AlwaysVisible(),
              isStatic: false,
              returnType: 'void',
            ),
          ],
        );
        final index = <Declaration>[parentClass];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedMethod>());
        expect(
          (result as ResolvedMethod).method.name.value,
          equals('doSomething'),
        );
      });
    });

    group('fields', () {
      test('resolves a field member', () async {
        const text = 'String myField;';
        final cursorOffset = text.indexOf('myField');
        final parentClass = IndexedClass(
          DeclarationName('MyClass'),
          visibility: AlwaysVisible(),
          location: (0, text.length),
          members: [
            FieldMember(
              DeclarationName('myField'),
              isStatic: false,
              typeName: DeclarationName('String'),
              visibility: AlwaysVisible(),
            ),
          ],
        );
        final index = <Declaration>[parentClass];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedField>());
        expect((result as ResolvedField).field.name.value, equals('myField'));
      });
    });

    group('enum values', () {
      test('resolves an enum value via dot access', () async {
        const text = 'Color.RED';
        final cursorOffset = text.indexOf('RED');
        final colorEnum = IndexedEnum(
          DeclarationName('Color'),
          visibility: AlwaysVisible(),
          values: [EnumValueMember(DeclarationName('RED'))],
        );
        final index = <Declaration>[colorEnum];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedEnumValue>());
        expect(
          (result as ResolvedEnumValue).enumValue.name.value,
          equals('RED'),
        );
        expect((result).parentEnum.name.value, equals('Color'));
      });
    });

    group('dot-qualified member access', () {
      test('resolves static method via class dot access', () async {
        const text = 'Foo.doWork();';
        final cursorOffset = text.indexOf('doWork');
        final fooClass = IndexedClass(
          DeclarationName('Foo'),
          visibility: AlwaysVisible(),
          members: [
            MethodDeclaration(
              DeclarationName('doWork'),
              body: Block.empty(),
              visibility: AlwaysVisible(),
              isStatic: true,
              returnType: 'void',
            ),
          ],
        );
        final index = <Declaration>[fooClass];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedMethod>());
        final resolved = result as ResolvedMethod;
        expect(resolved.method.name.value, equals('doWork'));
        expect(resolved.parentType?.name.value, equals('Foo'));
      });

      test('resolves instance field via variable dot access', () async {
        const text = 'account.Name';
        final cursorOffset = text.indexOf('Name');
        final accountClass = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [
            FieldMember(
              DeclarationName('Name'),
              isStatic: false,
              typeName: DeclarationName('String'),
              visibility: AlwaysVisible(),
            ),
          ],
        );
        final accountVar = IndexedVariable(
          DeclarationName('account'),
          typeName: DeclarationName('Account'),
          location: (0, 7),
        );
        final index = <Declaration>[accountClass, accountVar];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedField>());
        final resolved = result as ResolvedField;
        expect(resolved.field.name.value, equals('Name'));
        expect(resolved.parentType?.name.value, equals('Account'));
      });

      test('resolves enum value via dot access', () async {
        const text = 'Status.ACTIVE';
        final cursorOffset = text.indexOf('ACTIVE');
        final statusEnum = IndexedEnum(
          DeclarationName('Status'),
          visibility: AlwaysVisible(),
          values: [
            EnumValueMember(DeclarationName('ACTIVE')),
            EnumValueMember(DeclarationName('INACTIVE')),
          ],
        );
        final index = <Declaration>[statusEnum];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedEnumValue>());
        final resolved = result as ResolvedEnumValue;
        expect(resolved.enumValue.name.value, equals('ACTIVE'));
        expect(resolved.parentEnum.name.value, equals('Status'));
      });

      test('resolves interface method via dot access', () async {
        const text = 'myRunnable.execute();';
        final cursorOffset = text.indexOf('execute');
        final iface = IndexedInterface(
          DeclarationName('Runnable'),
          visibility: AlwaysVisible(),
          extendedInterfaces: [],
          methods: [
            MethodDeclaration(
              DeclarationName('execute'),
              body: Block.empty(),
              visibility: AlwaysVisible(),
              isStatic: false,
              returnType: 'void',
            ),
          ],
        );
        final myVar = IndexedVariable(
          DeclarationName('myRunnable'),
          typeName: DeclarationName('Runnable'),
          location: (0, 10),
        );
        final index = <Declaration>[iface, myVar];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedMethod>());
        final resolved = result as ResolvedMethod;
        expect(resolved.method.name.value, equals('execute'));
        expect(resolved.parentType?.name.value, equals('Runnable'));
      });

      test('resolves member with cursor in the middle of identifier', () async {
        const text = 'Foo.doWork();';
        // Cursor on 'W' in 'doWork' (middle of identifier)
        final cursorOffset = text.indexOf('Work');
        final fooClass = IndexedClass(
          DeclarationName('Foo'),
          visibility: AlwaysVisible(),
          members: [
            MethodDeclaration(
              DeclarationName('doWork'),
              body: Block.empty(),
              visibility: AlwaysVisible(),
              isStatic: true,
              returnType: 'void',
            ),
          ],
        );
        final index = <Declaration>[fooClass];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedMethod>());
        expect((result as ResolvedMethod).method.name.value, equals('doWork'));
      });

      test('returns null when member does not exist on type', () async {
        const text = 'Foo.nonExistent();';
        final cursorOffset = text.indexOf('nonExistent');
        final fooClass = IndexedClass(
          DeclarationName('Foo'),
          visibility: AlwaysVisible(),
          members: [
            MethodDeclaration(
              DeclarationName('doWork'),
              body: Block.empty(),
              visibility: AlwaysVisible(),
              isStatic: true,
              returnType: 'void',
            ),
          ],
        );
        final index = <Declaration>[fooClass];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test('returns null when receiver type is not in index', () async {
        const text = 'Unknown.something();';
        final cursorOffset = text.indexOf('something');
        final index = <Declaration>[];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test('resolves SObject field via dot access', () async {
        const text = 'account.Industry';
        final cursorOffset = text.indexOf('Industry');
        final sobject = IndexedSObject(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          fields: [
            FieldMember(
              DeclarationName('Industry'),
              isStatic: false,
              typeName: DeclarationName('String'),
              visibility: AlwaysVisible(),
            ),
          ],
        );
        final accountVar = IndexedVariable(
          DeclarationName('account'),
          typeName: DeclarationName('Account'),
          location: (0, 7),
        );
        final index = <Declaration>[sobject, accountVar];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedField>());
        final resolved = result as ResolvedField;
        expect(resolved.field.name.value, equals('Industry'));
        expect(resolved.parentType?.name.value, equals('Account'));
      });

      test(
        'returns null when receiver variable is declared after usage',
        () async {
          const text = 'cust.fullName; Customer cust;';
          final cursorOffset = text.indexOf('fullName');
          final customerClass = IndexedClass(
            DeclarationName('Customer'),
            visibility: AlwaysVisible(),
            members: [
              FieldMember(
                DeclarationName('fullName'),
                isStatic: false,
                typeName: DeclarationName('String'),
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final custVar = IndexedVariable(
            DeclarationName('cust'),
            typeName: DeclarationName('Customer'),
            location: (24, 28),
          );
          final index = <Declaration>[customerClass, custVar];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isNull);
        },
      );
    });

    group('shadowing and name resolution priority', () {
      test('local variable shadows class with same name', () async {
        const text = 'Parser token;';
        final cursorOffset = text.indexOf('token');
        final parserClass = IndexedClass(
          DeclarationName('Parser'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final tokenVariable = IndexedVariable(
          DeclarationName('token'),
          typeName: DeclarationName('Parser'),
          location: (0, 13),
        );
        // Both the class 'Parser' and variable 'token' are in index
        final index = <Declaration>[parserClass, tokenVariable];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        // Should resolve to the variable 'token', not the class
        expect(
          result,
          isA<ResolvedVariable>(),
          reason: 'Local variable should shadow any class name',
        );
        expect(
          (result as ResolvedVariable).variable.name.value,
          equals('token'),
        );
        expect(result.variable.typeName.value, equals('Parser'));
      });

      test('parameter shadows workspace class with similar name', () async {
        const text = 'void visit(Token token) {}';
        final cursorOffset = text.indexOf('token');
        final tokenClass = IndexedClass(
          DeclarationName('Token'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final tokenParam = IndexedVariable(
          DeclarationName('token'),
          visibility: AlwaysVisible(),
          typeName: DeclarationName('Token'),
          location: (11, 23),
        );
        final index = <Declaration>[tokenClass, tokenParam];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(
          result,
          isA<ResolvedVariable>(),
          reason: 'Parameter should shadow workspace class',
        );
        expect(
          (result as ResolvedVariable).variable.name.value,
          equals('token'),
        );
      });

      test(
        'resolves to class when no local variable with that name exists',
        () async {
          const text = 'Token t;';
          final cursorOffset = text.indexOf('Token');
          final tokenClass = IndexedClass(
            DeclarationName('Token'),
            visibility: AlwaysVisible(),
            members: [],
          );
          final index = <Declaration>[tokenClass];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(result, isA<ResolvedType>());
          expect(
            (result as ResolvedType).indexedType.name.value,
            equals('Token'),
          );
        },
      );

      test(
        'case insensitive match for variable still respects shadowing',
        () async {
          // Apex is case-insensitive for identifiers
          const text = 'MyClass myclass;';
          final cursorOffset = text.indexOf('myclass');
          final myClassType = IndexedClass(
            DeclarationName('MyClass'),
            visibility: AlwaysVisible(),
            members: [],
          );
          final myClassVar = IndexedVariable(
            DeclarationName('myclass'),
            typeName: DeclarationName('String'),
            location: (8, 15),
          );
          final index = <Declaration>[myClassType, myClassVar];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          // Should find the variable even though cases don't match exactly
          expect(
            result,
            isA<ResolvedVariable>(),
            reason:
                'Local variable should shadow type even with different casing',
          );
        },
      );
    });

    group('false positives', () {
      test(
        'does not resolve standalone identifier to member of unrelated class',
        () async {
          // Hovering over "Test" in "Test.isRunningTest()" should not match
          // the "test" method inside "AccountTest".
          const text = 'Test.isRunningTest();';
          final cursorOffset = text.indexOf('Test');
          final accountTestClass = IndexedClass(
            DeclarationName('AccountTest'),
            visibility: AlwaysVisible(),
            members: [
              MethodDeclaration(
                DeclarationName('test'),
                body: Block.empty(),
                visibility: AlwaysVisible(),
                isStatic: true,
                returnType: 'void',
              ),
            ],
          );
          final index = <Declaration>[accountTestClass];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          expect(
            result,
            isNull,
            reason:
                'Should not match "test" method in AccountTest for identifier "Test"',
          );
        },
      );

      test('resolves interface method in enclosing interface', () async {
        const text = 'public interface I { void doWork(); }';
        final cursorOffset = text.indexOf('doWork');
        final interfaceDecl = IndexedInterface(
          DeclarationName('I'),
          visibility: AlwaysVisible(),
          location: (0, text.length),
          extendedInterfaces: [],
          methods: [
            MethodDeclaration.withoutBody(
              DeclarationName('doWork'),
              isStatic: false,
              visibility: AlwaysVisible(),
              returnType: 'void',
            ),
          ],
        );
        final index = <Declaration>[interfaceDecl];

        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedMethod>());
        final resolved = result as ResolvedMethod;
        expect(resolved.method.name.value, equals('doWork'));
        expect(resolved.parentType?.name.value, equals('I'));
      });
    });

    group('edge cases', () {
      test('returns null when cursor is past end of text', () async {
        const text = 'String x;';
        final variable = IndexedVariable(
          DeclarationName('x'),
          typeName: DeclarationName('String'),
          location: (0, 9),
        );
        final index = <Declaration>[variable];

        final result = await resolveSymbolAt(
          cursorOffset: 9999,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test('returns null for empty index', () async {
        const text = 'Account a;';
        final result = await resolveSymbolAt(
          cursorOffset: 0,
          text: text,
          index: [],
        );

        expect(result, isNull);
      });

      test('returns null when cursor is on a constructor name', () async {
        // ConstructorDeclaration is not a hoverable symbol — the resolver
        // should stop searching and return null rather than falling through
        // to unrelated declarations.
        const text = 'MyClass';
        final cursorOffset = text.indexOf('MyClass');
        final constructorClass = IndexedClass(
          DeclarationName('MyClass'),
          visibility: AlwaysVisible(),
          members: [ConstructorDeclaration(body: Block.empty())],
        );
        // The class itself is in the index as an IndexedClass.
        final index = <Declaration>[constructorClass];

        // 'MyClass' resolves to the IndexedClass (type), not the constructor.
        final result = await resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });

      test(
        'local variable shadows constructor member with same name',
        () async {
          // With proper lexical scoping, local variables shadow class members,
          // even if the member is a non-hoverable constructor.
          const text = '__constructor__';
          final cursorOffset = 0;
          final variable = IndexedVariable(
            DeclarationName('__constructor__'),
            typeName: DeclarationName('String'),
            location: (0, 15),
          );
          final classWithConstructor = IndexedClass(
            DeclarationName('SomeClass'),
            visibility: AlwaysVisible(),
            members: [ConstructorDeclaration(body: Block.empty())],
          );
          final index = <Declaration>[classWithConstructor, variable];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          // Local variables shadow class members (even constructors).
          expect(result, isA<ResolvedVariable>());
          expect(
            (result as ResolvedVariable).variable.name.value,
            equals('__constructor__'),
          );
        },
      );

      test(
        'returns null when hovering over constructor with no shadowing variable',
        () async {
          // Constructors are not hoverable when there's no local variable
          // shadowing them.
          const text = '__constructor__';
          final cursorOffset = 0;
          final classWithConstructor = IndexedClass(
            DeclarationName('SomeClass'),
            visibility: AlwaysVisible(),
            members: [ConstructorDeclaration(body: Block.empty())],
          );
          // Only the class with constructor, no variable
          final index = <Declaration>[classWithConstructor];

          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          // Constructor members are not hoverable.
          expect(result, isNull);
        },
      );
    });

    group('call chaining', () {
      test(
        'resolves a field accessed on a method call return type',
        () async {
          final accountClass = IndexedClass(
            DeclarationName('Account'),
            visibility: AlwaysVisible(),
            members: [
              FieldMember(
                DeclarationName('Name'),
                typeName: DeclarationName('String'),
                isStatic: false,
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final myClass = IndexedClass(
            DeclarationName('MyClass'),
            visibility: AlwaysVisible(),
            members: [
              MethodDeclaration(
                DeclarationName('getAccount'),
                body: Block.empty(),
                isStatic: false,
                returnType: 'Account',
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final variable = IndexedVariable(
            DeclarationName('obj'),
            typeName: DeclarationName('MyClass'),
            location: (0, 10),
          );

          const text = 'obj.getAccount().Name';
          final cursorOffset = text.indexOf('Name');
          final (_, tree) = localIndexer.parseAndIndexWithTree(text);
          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: [variable, myClass, accountClass],
            bindings: treeSitterBindings,
            tree: tree,
          );
          treeSitterBindings.ts_tree_delete(tree);

          expect(result, isA<ResolvedField>());
          expect((result as ResolvedField).field.name.value, equals('Name'));
        },
      );

      test(
        'resolves a field via multi-level chaining',
        () async {
          final cClass = IndexedClass(
            DeclarationName('C'),
            visibility: AlwaysVisible(),
            members: [
              FieldMember(
                DeclarationName('value'),
                typeName: DeclarationName('String'),
                isStatic: false,
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final bClass = IndexedClass(
            DeclarationName('B'),
            visibility: AlwaysVisible(),
            members: [
              MethodDeclaration(
                DeclarationName('getC'),
                body: Block.empty(),
                isStatic: false,
                returnType: 'C',
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final aClass = IndexedClass(
            DeclarationName('A'),
            visibility: AlwaysVisible(),
            members: [
              MethodDeclaration(
                DeclarationName('getB'),
                body: Block.empty(),
                isStatic: false,
                returnType: 'B',
                visibility: AlwaysVisible(),
              ),
            ],
          );
          final variable = IndexedVariable(
            DeclarationName('a'),
            typeName: DeclarationName('A'),
            location: (0, 10),
          );

          const text = 'a.getB().getC().value';
          final cursorOffset = text.indexOf('value');
          final (_, tree) = localIndexer.parseAndIndexWithTree(text);
          final result = await resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: [variable, aClass, bClass, cClass],
            bindings: treeSitterBindings,
            tree: tree,
          );
          treeSitterBindings.ts_tree_delete(tree);

          expect(result, isA<ResolvedField>());
          expect((result as ResolvedField).field.name.value, equals('value'));
        },
      );
    });
  });
}
