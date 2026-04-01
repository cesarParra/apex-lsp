import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/context/expression_chain.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';

/// Resolves the result type of an expression chain by walking through each
/// segment and resolving intermediate types via the declaration [index].
///
/// [segments] is the list of chain segments to resolve (typically all segments
/// except the last one, which is the member being completed/hovered).
/// [index] is the combined local and workspace declaration list.
/// [cursorOffset] is used for variable visibility checking.
///
/// Returns the type name at the end of the chain, or `null` if any step
/// cannot be resolved (unknown variable, unknown member, or void return).
String? resolveChainType({
  required List<ChainSegment> segments,
  required List<Declaration> index,
  required int cursorOffset,
}) {
  if (segments.isEmpty) return null;

  // Resolve the first segment to get the starting type name.
  final firstTypeName = _resolveFirstSegment(segments.first, index, cursorOffset);
  if (firstTypeName == null) return null;

  // Walk the remaining segments, resolving each as a member of the current type.
  var currentTypeName = firstTypeName;
  for (final segment in segments.skip(1)) {
    final currentType = index.findType(DeclarationName(currentTypeName));
    if (currentType == null) return null;

    final memberTypeName = _resolveMemberType(currentType, segment);
    if (memberTypeName == null) return null;

    // Strip generic type parameters to get a resolvable type name.
    final stripped = _stripGenerics(memberTypeName);
    if (stripped.toLowerCase() == 'void') return null;
    currentTypeName = stripped;
  }

  return currentTypeName;
}

/// Resolves the first chain segment to a type name.
String? _resolveFirstSegment(
  ChainSegment segment,
  List<Declaration> index,
  int cursorOffset,
) => switch (segment) {
  ThisSegment() => index.innermostEnclosingAt<IndexedClass>(cursorOffset)?.name.value,
  SuperSegment() => index.innermostEnclosingAt<IndexedClass>(cursorOffset)?.superClass,
  // A constructor call always produces an instance of the named type.
  ObjectCreationSegment(:final name) => index.findType(DeclarationName(name))?.name.value,
  IdentifierSegment(:final name) || MethodCallSegment(:final name) =>
    _resolveIdentifierToType(name, index, cursorOffset, isCall: segment is MethodCallSegment),
};

/// Resolves an identifier or method call in the first chain position.
///
/// For an identifier, checks if it's a known variable (returns its type) or
/// a type name itself (for static member access like `MyClass.staticMethod()`).
/// For a method call, looks up the method in the enclosing class and returns
/// its return type.
String? _resolveIdentifierToType(
  String name,
  List<Declaration> index,
  int cursorOffset, {
  required bool isCall,
}) {
  final declarationName = DeclarationName(name);

  if (isCall) {
    // A free-standing method call — look in the enclosing class.
    final enclosing = index.innermostEnclosingAt<IndexedClass>(cursorOffset);
    if (enclosing != null) {
      final method = enclosing.members
          .whereType<MethodDeclaration>()
          .firstWhereOrNull((m) => m.name == declarationName);
      if (method?.returnType != null) return _stripGenerics(method!.returnType!);
    }
    return null;
  }

  // Variable: return its declared type.
  final variable = index
      .whereType<IndexedVariable>()
      .where((v) => v.isVisibleAt(cursorOffset))
      .firstWhereOrNull((v) => v.name == declarationName);
  if (variable != null) return variable.typeName.value;

  // Type name (for static access like `MyClass.staticMethod()`).
  final type = index.findType(declarationName);
  if (type != null) return type.name.value;

  return null;
}

/// Returns the result type of [segment] when accessed on [type].
String? _resolveMemberType(IndexedType type, ChainSegment segment) =>
    switch (segment) {
      IdentifierSegment(:final name) => _resolveFieldType(type, name),
      MethodCallSegment(:final name) => _resolveMethodReturnType(type, name),
      ThisSegment() || SuperSegment() || ObjectCreationSegment() => null,
    };

String? _resolveFieldType(IndexedType type, String name) {
  final memberName = DeclarationName(name);
  return switch (type) {
    IndexedClass(:final members) => switch (
      members.firstWhereOrNull(
        (m) => m.name == memberName && (m is FieldMember || m is PropertyDeclaration),
      )
    ) {
      FieldMember(:final typeName) => typeName?.value,
      PropertyDeclaration(:final typeName) => typeName?.value,
      _ => null,
    },
    IndexedSObject(:final fields) => fields
        .firstWhereOrNull((f) => f.name == memberName)
        ?.typeName
        ?.value,
    IndexedInterface() || IndexedEnum() => null,
  };
}

String? _resolveMethodReturnType(IndexedType type, String name) {
  final memberName = DeclarationName(name);
  return switch (type) {
    IndexedClass(:final members) => members
        .whereType<MethodDeclaration>()
        .firstWhereOrNull((m) => m.name == memberName)
        ?.returnType,
    IndexedInterface(:final methods) => methods
        .firstWhereOrNull((m) => m.name == memberName)
        ?.returnType,
    IndexedSObject() || IndexedEnum() => null,
  };
}

/// Strips generic type parameters from a type name string.
///
/// For example, `List<Account>` becomes `List`, and `Map<String, Integer>`
/// becomes `Map`. Full generic type parameter tracking is not supported.
String _stripGenerics(String typeName) {
  final angle = typeName.indexOf('<');
  return angle == -1 ? typeName : typeName.substring(0, angle).trim();
}

