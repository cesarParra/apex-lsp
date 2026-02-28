import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

void main() {
  group('getBodyDeclarations', () {
    test('returns empty list for null', () {
      expect(getBodyDeclarations(null), isEmpty);
    });

    test('returns empty list for FieldMember', () {
      final field = FieldMember(
        DeclarationName('myField'),
        isStatic: false,
        visibility: AlwaysVisible(),
      );
      expect(getBodyDeclarations(field), isEmpty);
    });

    test('returns body declarations for MethodDeclaration', () {
      final variable = IndexedVariable(
        DeclarationName('localVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final method = MethodDeclaration(
        DeclarationName('myMethod'),
        body: Block(declarations: [variable]),
        isStatic: false,
        visibility: AlwaysVisible(),
      );

      final result = getBodyDeclarations(method);

      expect(result, hasLength(1));
      expect(result.first, same(variable));
    });

    test('returns body declarations for ConstructorDeclaration', () {
      final variable = IndexedVariable(
        DeclarationName('param'),
        typeName: DeclarationName('Integer'),
        location: (0, 10),
      );
      final constructor = ConstructorDeclaration(
        body: Block(declarations: [variable]),
      );

      final result = getBodyDeclarations(constructor);

      expect(result, hasLength(1));
      expect(result.first, same(variable));
    });

    test('returns getter body declarations for PropertyDeclaration', () {
      final variable = IndexedVariable(
        DeclarationName('localVar'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final property = PropertyDeclaration(
        DeclarationName('MyProp'),
        isStatic: false,
        visibility: AlwaysVisible(),
        getterBody: Block(declarations: [variable]),
      );

      final result = getBodyDeclarations(property);

      expect(result, contains(variable));
    });

    test('returns setter body declarations for PropertyDeclaration', () {
      final variable = IndexedVariable(
        DeclarationName('transformed'),
        typeName: DeclarationName('String'),
        location: (0, 10),
      );
      final property = PropertyDeclaration(
        DeclarationName('MyProp'),
        isStatic: false,
        visibility: AlwaysVisible(),
        setterBody: Block(declarations: [variable]),
      );

      final result = getBodyDeclarations(property);

      expect(result, contains(variable));
    });

    test(
      'returns both getter and setter body declarations for PropertyDeclaration',
      () {
        final getterVar = IndexedVariable(
          DeclarationName('getLocal'),
          typeName: DeclarationName('String'),
          location: (0, 10),
        );
        final setterVar = IndexedVariable(
          DeclarationName('setLocal'),
          typeName: DeclarationName('String'),
          location: (20, 30),
        );
        final property = PropertyDeclaration(
          DeclarationName('MyProp'),
          isStatic: false,
          visibility: AlwaysVisible(),
          getterBody: Block(declarations: [getterVar]),
          setterBody: Block(declarations: [setterVar]),
        );

        final result = getBodyDeclarations(property);

        expect(result, contains(getterVar));
        expect(result, contains(setterVar));
      },
    );

    test(
      'returns empty for PropertyDeclaration with auto-property (no bodies)',
      () {
        final property = PropertyDeclaration(
          DeclarationName('MyProp'),
          isStatic: false,
          visibility: AlwaysVisible(),
        );

        expect(getBodyDeclarations(property), isEmpty);
      },
    );
  });
}
