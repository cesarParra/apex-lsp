import 'package:apex_lsp/hover/symbol_resolver.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';

/// Formats a [ResolvedSymbol] into an LSP [Hover] response with markdown content.
///
/// Each symbol variant produces a concise, idiomatic Apex-style signature:
/// - Variables: `Type name`
/// - Classes: `class Name` or `class Name extends Super`
/// - Enums: `enum Name`
/// - Interfaces: `interface Name`
/// - Methods: `[static] ReturnType name(ParamType paramName, ...)` with
///   optional parent type context
/// - Fields: `[static] Type name` with optional parent type context
/// - Enum values: `EnumName.VALUE`
Hover formatHover(ResolvedSymbol symbol) {
  final markdown = switch (symbol) {
    ResolvedVariable(:final variable) => _formatVariable(variable),
    ResolvedType(:final indexedType) => _formatType(indexedType),
    ResolvedMethod(:final method, :final parentType) => _formatMethod(
      method,
      parentType: parentType,
    ),
    ResolvedField(:final field, :final parentType) => _formatField(
      field,
      parentType: parentType,
    ),
    ResolvedEnumValue(:final enumValue, :final parentEnum) => _formatEnumValue(
      enumValue,
      parentEnum: parentEnum,
    ),
  };

  return Hover(
    contents: MarkupContent(
      kind: MarkupKind.markdown,
      value: '```apex\n$markdown\n```',
    ),
  );
}

String _formatVariable(IndexedVariable variable) =>
    '${variable.typeName.value} ${variable.name.value}';

String _formatType(IndexedType type) => switch (type) {
  IndexedClass(:final superClass) =>
    superClass != null
        ? 'class ${type.name.value} extends $superClass'
        : 'class ${type.name.value}',
  IndexedEnum() => 'enum ${type.name.value}',
  IndexedInterface() => 'interface ${type.name.value}',
  IndexedSObject() => 'SObject ${type.name.value}',
};

String _formatMethod(MethodDeclaration method, {IndexedType? parentType}) {
  final staticPrefix = method.isStatic ? 'static ' : '';
  final returnType = method.returnType != null ? '${method.returnType} ' : '';
  final params = method.parameters.map((p) => '${p.type} ${p.name}').join(', ');
  final signature = '$staticPrefix$returnType${method.name.value}($params)';

  if (parentType != null) {
    return '// in ${parentType.name.value}\n$signature';
  }
  return signature;
}

String _formatField(FieldMember field, {IndexedType? parentType}) {
  final staticPrefix = field.isStatic ? 'static ' : '';
  final typeName = field.typeName?.value ?? '';
  final signature = '$staticPrefix$typeName ${field.name.value}'.trim();

  if (parentType != null) {
    return '// in ${parentType.name.value}\n$signature';
  }
  return signature;
}

String _formatEnumValue(
  EnumValueMember enumValue, {
  required IndexedEnum parentEnum,
}) => '${parentEnum.name.value}.${enumValue.name.value}';
