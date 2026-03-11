import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';

/// A symbol that was successfully resolved at a cursor position.
sealed class ResolvedSymbol {
  const ResolvedSymbol();
}

/// A resolved top-level type (class, enum, or interface).
final class ResolvedType extends ResolvedSymbol {
  final IndexedType indexedType;

  const ResolvedType(this.indexedType);
}

/// A resolved method declaration (with optional parent type context).
final class ResolvedMethod extends ResolvedSymbol {
  final MethodDeclaration method;
  final IndexedType? parentType;

  const ResolvedMethod(this.method, {this.parentType});
}

/// A resolved field member (with optional parent type context).
final class ResolvedField extends ResolvedSymbol {
  final FieldMember field;
  final IndexedType? parentType;

  const ResolvedField(this.field, {this.parentType});
}

/// A resolved local variable.
final class ResolvedVariable extends ResolvedSymbol {
  final IndexedVariable variable;

  const ResolvedVariable(this.variable);
}

/// A resolved enum value member.
final class ResolvedEnumValue extends ResolvedSymbol {
  final EnumValueMember enumValue;
  final IndexedEnum parentEnum;

  const ResolvedEnumValue(this.enumValue, {required this.parentEnum});
}

/// Resolves the symbol at [cursorOffset] within [text] using [index].
///
/// Delegates to [detectCompletionContext] with [extractFullIdentifier] to
/// determine whether the cursor is on a standalone identifier or a
/// dot-qualified member access, then resolves the appropriate declaration.
///
/// Returns a [ResolvedSymbol] variant wrapping the found declaration, or
/// `null` if no symbol is found.
Future<ResolvedSymbol?> resolveSymbolAt({
  required int cursorOffset,
  required String text,
  required List<Declaration> index,
}) async {
  if (cursorOffset < 0 || cursorOffset > text.length) return null;

  // Expand the index with body declarations from the enclosing scope so that
  // local variables are visible to context detection (e.g. resolving the
  // receiver type in "cust.name" where cust is a local variable).
  final enclosing = index.enclosingAt<Declaration>(cursorOffset);
  final expandedIndex = [...index, ...getBodyDeclarations(enclosing)];

  final context = await detectCompletionContext(
    text: text,
    cursorOffset: cursorOffset,
    index: expandedIndex,
    extractIdentifier: extractFullIdentifier,
  );

  return switch (context) {
    CompletionContextNone() => null,
    CompletionContextTopLevel(:final prefix) => _resolveTopLevel(
      prefix,
      cursorOffset,
      expandedIndex,
    ),
    CompletionContextMember(:final prefix, :final typeName) => _resolveMember(
      prefix,
      typeName,
      expandedIndex,
    ),
  };
}

/// Resolves a standalone identifier (no dot before it).
///
/// Search order follows Apex name-resolution rules:
/// 1. Local variables and parameters (with visibility checking)
/// 2. Members of the enclosing class (methods and fields)
/// 3. Top-level types (classes, enums, interfaces)
/// 4. Enum values
ResolvedSymbol? _resolveTopLevel(
  String identifier,
  int cursorOffset,
  List<Declaration> index,
) {
  if (identifier.isEmpty) return null;

  final name = DeclarationName(identifier);

  // Local variables first (parameters and local vars) with visibility.
  final variable = index
      .whereType<IndexedVariable>()
      .where((v) => v.isVisibleAt(cursorOffset))
      .firstWhereOrNull((v) => v.name == name);
  if (variable != null) return ResolvedVariable(variable);

  // Members of the enclosing class only. When a name matches but is not a
  // hoverable member (e.g. a ConstructorDeclaration), stop searching rather
  // than falling through to unrelated declarations.
  final enclosingClass = index.enclosingAt<IndexedClass>(cursorOffset);
  if (enclosingClass != null) {
    final result = _findMemberInType(enclosingClass, name);
    if (result != null) return result;
  }

  // Top-level types (classes, enums, interfaces, sobjects).
  final type = index.findType(name);
  if (type != null) return ResolvedType(type);

  // Enum values across all enums.
  for (final decl in index.whereType<IndexedEnum>()) {
    final match = decl.values.firstWhereOrNull((v) => v.name == name);
    if (match != null) return ResolvedEnumValue(match, parentEnum: decl);
  }

  return null;
}

/// Resolves a dot-qualified member access (e.g. cursor on `bar` in `Foo.bar`).
///
/// Uses the already-resolved [typeName] from context detection to find the
/// target type, then searches its members for an exact match on [identifier].
ResolvedSymbol? _resolveMember(
  String identifier,
  String? typeName,
  List<Declaration> index,
) {
  if (identifier.isEmpty || typeName == null) return null;

  final resolvedType = _resolveType(typeName, index);
  if (resolvedType == null) return null;

  final name = DeclarationName(identifier);
  return _findMemberInType(resolvedType, name);
}

/// Resolves a type name to an [IndexedType] from the index.
///
/// Tries direct type lookup first, then checks if it is a variable whose
/// declared type can be resolved, and finally attempts qualified name
/// resolution (e.g. "Outer.Inner").
IndexedType? _resolveType(String typeName, List<Declaration> index) {
  final name = DeclarationName(typeName);

  // Direct type lookup.
  final direct = index.findType(name);
  if (direct != null) return direct;

  // Variable whose declared type we can resolve.
  final variableType = index
      .whereType<IndexedVariable>()
      .firstWhereOrNull((v) => v.name == name)
      ?.typeName;
  if (variableType != null) {
    final resolved = index.findType(variableType);
    if (resolved != null) return resolved;
  }

  // Qualified name resolution (e.g. "Outer.Inner").
  final qualified = index.resolveQualifiedName(typeName);
  return qualified is IndexedType ? qualified : null;
}

/// Searches a type's members for an exact name match and returns the
/// appropriate [ResolvedSymbol], or `null` if no match or the match is
/// not a hoverable member (e.g. a ConstructorDeclaration).
ResolvedSymbol? _findMemberInType(IndexedType type, DeclarationName name) {
  return switch (type) {
    IndexedClass(:final members) => _findInMembers(members, name, type),
    IndexedInterface(:final methods) => switch (methods.firstWhereOrNull(
      (m) => m.name == name,
    )) {
      final method? => ResolvedMethod(method, parentType: type),
      null => null,
    },
    IndexedEnum(:final values) => switch (values.firstWhereOrNull(
      (v) => v.name == name,
    )) {
      final match? => ResolvedEnumValue(match, parentEnum: type),
      null => null,
    },
    IndexedSObject(:final fields) => switch (fields.firstWhereOrNull(
      (f) => f.name == name,
    )) {
      final match? => ResolvedField(match, parentType: type),
      null => null,
    },
  };
}

/// Searches a list of class members for an exact name match.
///
/// When a name matches a non-hoverable member (e.g. ConstructorDeclaration),
/// returns `null` to stop the search rather than falling through.
ResolvedSymbol? _findInMembers(
  List<Declaration> members,
  DeclarationName name,
  IndexedType parentType,
) {
  for (final member in members) {
    if (member.name == name) {
      return switch (member) {
        MethodDeclaration() => ResolvedMethod(member, parentType: parentType),
        FieldMember() => ResolvedField(member, parentType: parentType),
        _ => null,
      };
    }
  }
  return null;
}
