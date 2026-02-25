import 'package:apex_lsp/hover/hover_formatter.dart';
import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

void main() {
  group('formatHover', () {
    group('ResolvedVariable', () {
      test('shows type and name', () {
        final variable = IndexedVariable(
          DeclarationName('myVar'),
          typeName: DeclarationName('String'),
          location: (0, 15),
        );
        final resolved = ResolvedVariable(variable);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('String'));
        expect(hover.contents.value, contains('myVar'));
      });

      test('uses markdown kind', () {
        final variable = IndexedVariable(
          DeclarationName('count'),
          typeName: DeclarationName('Integer'),
          location: (0, 15),
        );
        final resolved = ResolvedVariable(variable);

        final hover = formatHover(resolved);

        expect(hover.contents.kind, equals(MarkupKind.markdown));
      });
    });

    group('ResolvedType - class', () {
      test('shows class keyword and name', () {
        final cls = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final resolved = ResolvedType(cls);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('class'));
        expect(hover.contents.value, contains('Account'));
      });

      test('shows superclass when present', () {
        final cls = IndexedClass(
          DeclarationName('SalesOrder'),
          visibility: AlwaysVisible(),
          superClass: 'Order',
          members: [],
        );
        final resolved = ResolvedType(cls);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('extends'));
        expect(hover.contents.value, contains('Order'));
      });

      test('does not show extends clause when no superclass', () {
        final cls = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final resolved = ResolvedType(cls);

        final hover = formatHover(resolved);

        expect(hover.contents.value, isNot(contains('extends')));
      });
    });

    group('ResolvedType - enum', () {
      test('shows enum keyword and name', () {
        final enm = IndexedEnum(
          DeclarationName('Status'),
          values: [EnumValueMember(DeclarationName('ACTIVE'))],
        );
        final resolved = ResolvedType(enm);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('enum'));
        expect(hover.contents.value, contains('Status'));
      });
    });

    group('ResolvedType - interface', () {
      test('shows interface keyword and name', () {
        final iface = IndexedInterface(
          DeclarationName('Runnable'),
          visibility: AlwaysVisible(),
          methods: [],
        );
        final resolved = ResolvedType(iface);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('interface'));
        expect(hover.contents.value, contains('Runnable'));
      });
    });

    group('ResolvedMethod', () {
      test('shows return type, name, and parameters', () {
        final method = MethodDeclaration(
          DeclarationName('setName'),
          body: Block.empty(),
          visibility: AlwaysVisible(),
          isStatic: false,
          returnType: 'void',
          parameters: [(type: 'String', name: 'name')],
        );
        final resolved = ResolvedMethod(method);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('void'));
        expect(hover.contents.value, contains('setName'));
        expect(hover.contents.value, contains('String'));
        expect(hover.contents.value, contains('name'));
      });

      test('shows parent type when present', () {
        final parentClass = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final method = MethodDeclaration(
          DeclarationName('getName'),
          body: Block.empty(),
          visibility: AlwaysVisible(),
          isStatic: false,
          returnType: 'String',
        );
        final resolved = ResolvedMethod(method, parentType: parentClass);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('Account'));
      });

      test('shows static modifier for static methods', () {
        final method = MethodDeclaration(
          DeclarationName('create'),
          body: Block.empty(),
          visibility: AlwaysVisible(),
          isStatic: true,
          returnType: 'Account',
        );
        final resolved = ResolvedMethod(method);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('static'));
      });

      test('handles method with no parameters', () {
        final method = MethodDeclaration(
          DeclarationName('doWork'),
          body: Block.empty(),
          visibility: AlwaysVisible(),
          isStatic: false,
          returnType: 'void',
        );
        final resolved = ResolvedMethod(method);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('doWork'));
        expect(hover.contents.value, contains('()'));
      });
    });

    group('ResolvedField', () {
      test('shows type and field name', () {
        final field = FieldMember(
          DeclarationName('status'),
          isStatic: false,
          typeName: DeclarationName('String'),
          visibility: AlwaysVisible(),
        );
        final resolved = ResolvedField(field);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('String'));
        expect(hover.contents.value, contains('status'));
      });

      test('shows static modifier for static fields', () {
        final field = FieldMember(
          DeclarationName('MAX_SIZE'),
          isStatic: true,
          typeName: DeclarationName('Integer'),
          visibility: AlwaysVisible(),
        );
        final resolved = ResolvedField(field);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('static'));
      });

      test('shows parent type when present', () {
        final parentClass = IndexedClass(
          DeclarationName('Account'),
          visibility: AlwaysVisible(),
          members: [],
        );
        final field = FieldMember(
          DeclarationName('name'),
          isStatic: false,
          typeName: DeclarationName('String'),
          visibility: AlwaysVisible(),
        );
        final resolved = ResolvedField(field, parentType: parentClass);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('Account'));
      });
    });

    group('ResolvedEnumValue', () {
      test('shows parent enum name and value name', () {
        final parentEnum = IndexedEnum(
          DeclarationName('Color'),
          values: [EnumValueMember(DeclarationName('RED'))],
        );
        final enumValue = EnumValueMember(DeclarationName('RED'));
        final resolved = ResolvedEnumValue(enumValue, parentEnum: parentEnum);

        final hover = formatHover(resolved);

        expect(hover.contents.value, contains('Color'));
        expect(hover.contents.value, contains('RED'));
      });
    });
  });
}
