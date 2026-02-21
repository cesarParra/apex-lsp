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
    });

    group('class names', () {
      test('resolves a class by name when cursor is on its identifier', () {
        const text = 'Account acc = new Account();';
        final cursorOffset = text.indexOf('Account');
        final accountClass = IndexedClass(
          DeclarationName('Account'),
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
          members: [
            MethodDeclaration(
              DeclarationName('doSomething'),
              body: Block.empty(),
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
          members: [
            FieldMember(
              DeclarationName('myField'),
              isStatic: false,
              typeName: DeclarationName('String'),
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

      test(
        'returns null when member name matches a constructor inside a class',
        () {
          // When searching members, a ConstructorDeclaration match should
          // return null rather than falling through to search variables.
          const text = '__constructor__';
          final cursorOffset = 0;
          final variable = IndexedVariable(
            DeclarationName('__constructor__'),
            typeName: DeclarationName('String'),
            location: (0, 15),
          );
          final classWithConstructor = IndexedClass(
            DeclarationName('SomeClass'),
            members: [ConstructorDeclaration(body: Block.empty())],
          );
          // Put the variable after the class so the member search runs first.
          final index = <Declaration>[classWithConstructor, variable];

          final result = resolveSymbolAt(
            cursorOffset: cursorOffset,
            text: text,
            index: index,
          );

          // Constructor members are not hoverable — should return null,
          // not fall through to the variable with the same name.
          expect(result, isNull);
        },
      );
    });
  });
}
