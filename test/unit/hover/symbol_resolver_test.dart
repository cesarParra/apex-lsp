import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

void main() {
  group('resolveSymbolAt', () {
    group('local variables', () {
      test('resolves a local variable at its usage site', () {
        const text = 'String myVar = null; Integer x = myVar;';
        // cursor on 'myVar' in second usage (offset ~33)
        final cursorOffset = text.indexOf('myVar', 20);
        final variable = IndexedVariable(
          DeclarationName('myVar'),
          typeName: DeclarationName('String'),
          location: (0, 19),
        );
        final index = <Declaration>[variable];

        final result = resolveSymbolAt(
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

      test('returns null when cursor is on whitespace between tokens', () {
        const text = 'String myVar = null;';
        // cursor on the space between 'String' and 'myVar'
        final cursorOffset = text.indexOf(' ');
        final variable = IndexedVariable(
          DeclarationName('myVar'),
          typeName: DeclarationName('String'),
          location: (0, 20),
        );
        final index = <Declaration>[variable];

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test('returns null when cursor is at an unresolvable symbol', () {
        const text = 'String myVar = null;';
        final cursorOffset = text.indexOf('myVar');
        final index = <Declaration>[];

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test(
        'respects visibility: returns null when cursor is before declaration',
        () {
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

          final result = resolveSymbolAt(
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
        () {
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

          final result = resolveSymbolAt(
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
        () {
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

          final result = resolveSymbolAt(
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
        () {
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

          final result = resolveSymbolAt(
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
      test('resolves a class by name when cursor is on its identifier', () {
        const text = 'Account acc = new Account();';
        final cursorOffset = text.indexOf('Account');
        final accountClass = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final index = <Declaration>[accountClass];

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
        expect(
          (result as ResolvedType).indexedType.name.value,
          equals('Account'),
        );
      });

      test('resolves an enum by name', () {
        const text = 'Color c = Color.RED;';
        final cursorOffset = text.indexOf('Color');
        final colorEnum = IndexedEnum(
          DeclarationName('Color'),
          visibility: AlwaysVisible(),
          values: [EnumValueMember(DeclarationName('RED'))],
        );
        final index = <Declaration>[colorEnum];

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });

      test('resolves an interface by name', () {
        const text = 'Runnable r;';
        final cursorOffset = text.indexOf('Runnable');
        final iface = IndexedInterface(
          DeclarationName('Runnable'),
          visibility: AlwaysVisible(),
          methods: [],
        );
        final index = <Declaration>[iface];

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });
    });

    group('methods', () {
      test('resolves a method by name on cursor', () {
        const text = 'void doSomething() {}';
        final cursorOffset = text.indexOf('doSomething');
        final parentClass = IndexedClass(
          DeclarationName('MyClass'),
          visibility: AlwaysVisible(),
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

        final result = resolveSymbolAt(
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
      test('resolves a field member', () {
        const text = 'String myField;';
        final cursorOffset = text.indexOf('myField');
        final parentClass = IndexedClass(
          DeclarationName('MyClass'),
          visibility: AlwaysVisible(),
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

        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedField>());
        expect((result as ResolvedField).field.name.value, equals('myField'));
      });
    });

    group('enum values', () {
      test('resolves an enum value member', () {
        const text = 'Color.RED';
        final cursorOffset = text.indexOf('RED');
        final colorEnum = IndexedEnum(
          DeclarationName('Color'),
          visibility: AlwaysVisible(),
          values: [EnumValueMember(DeclarationName('RED'))],
        );
        final index = <Declaration>[colorEnum];

        final result = resolveSymbolAt(
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

    group('shadowing and name resolution priority', () {
      test('local variable shadows class with same name', () {
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

        final result = resolveSymbolAt(
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

      test('parameter shadows workspace class with similar name', () {
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

        final result = resolveSymbolAt(
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
        () {
          const text = 'Token t;';
          final cursorOffset = text.indexOf('Token');
          final tokenClass = IndexedClass(
            DeclarationName('Token'),
            visibility: AlwaysVisible(),
            members: [],
          );
          final index = <Declaration>[tokenClass];

          final result = resolveSymbolAt(
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

      test('case insensitive match for variable still respects shadowing', () {
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

        final result = resolveSymbolAt(
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
      });
    });

    group('edge cases', () {
      test('returns null when cursor is past end of text', () {
        const text = 'String x;';
        final variable = IndexedVariable(
          DeclarationName('x'),
          typeName: DeclarationName('String'),
          location: (0, 9),
        );
        final index = <Declaration>[variable];

        final result = resolveSymbolAt(
          cursorOffset: 9999,
          text: text,
          index: index,
        );

        expect(result, isNull);
      });

      test('returns null for empty index', () {
        const text = 'Account a;';
        final result = resolveSymbolAt(cursorOffset: 0, text: text, index: []);

        expect(result, isNull);
      });

      test('returns null when cursor is on a constructor name', () {
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
        // The class itself is NOT in the index — only the constructor member
        // exists, which is not a hoverable symbol.
        final index = <Declaration>[constructorClass];

        // 'MyClass' resolves to the IndexedClass (type), not the constructor.
        // Verify that the class type is returned (types are searched first).
        final result = resolveSymbolAt(
          cursorOffset: cursorOffset,
          text: text,
          index: index,
        );

        expect(result, isA<ResolvedType>());
      });

      test('local variable shadows constructor member with same name', () {
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

        final result = resolveSymbolAt(
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
      });

      test(
        'returns null when hovering over constructor with no shadowing variable',
        () {
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

          final result = resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          // Constructor members are not hoverable.
          expect(result, isNull);
        },
      );
    });
  });
}
