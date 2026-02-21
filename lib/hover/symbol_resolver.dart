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
/// Extracts the identifier under the cursor, then searches [index] for a
/// matching declaration. Returns a [ResolvedSymbol] variant that wraps the
/// found declaration, or `null` if no symbol is found.
ResolvedSymbol? resolveSymbolAt({
  required int cursorOffset,
  required String text,
  required List<Declaration> index,
}) {
  if (cursorOffset < 0 || cursorOffset > text.length) return null;

  final identifier = _extractIdentifierAt(text, cursorOffset);
  if (identifier.isEmpty) return null;

  final name = DeclarationName(identifier);

  // Search top-level types first. This matches Apex name-resolution rules:
  // a type name always shadows a local variable with the same name.
  final type = index.findType(name);
  if (type != null) return ResolvedType(type);

  // Search enum values across all enums.
  for (final decl in index.whereType<IndexedEnum>()) {
    final match = decl.values.firstWhereOrNull((v) => v.name == name);
    if (match != null) return ResolvedEnumValue(match, parentEnum: decl);
  }

  // Search class members (methods and fields). When a name matches but is
  // not a hoverable member (e.g. a ConstructorDeclaration), we stop searching
  // rather than falling through to unrelated declarations.
  for (final decl in index.whereType<IndexedClass>()) {
    for (final member in decl.members) {
      if (member.name == name) {
        return switch (member) {
          MethodDeclaration() => ResolvedMethod(member, parentType: decl),
          FieldMember() => ResolvedField(member, parentType: decl),
          _ => null,
        };
      }
    }
  }

  // Search interface methods.
  for (final decl in index.whereType<IndexedInterface>()) {
    final match = decl.methods.firstWhereOrNull((m) => m.name == name);
    if (match != null) return ResolvedMethod(match, parentType: decl);
  }

  // Search local variables.
  final variable = index.whereType<IndexedVariable>().firstWhereOrNull(
    (v) => v.name == name,
  );
  if (variable != null) return ResolvedVariable(variable);

  return null;
}

/// Extracts the identifier token that contains or touches [cursorOffset].
///
/// Scans left and right from the cursor to find the full identifier word.
String _extractIdentifierAt(String text, int cursorOffset) {
  if (text.isEmpty) return '';

  final offset = cursorOffset.clamp(0, text.length - 1).toInt();

  // If cursor is not on an identifier character, try one position left.
  int probe = offset;
  if (!text.codeUnitAt(probe).isIdentifierChar) {
    if (probe > 0) {
      probe--;
    } else {
      return '';
    }
  }

  if (!text.codeUnitAt(probe).isIdentifierChar) return '';

  // Expand left.
  var start = probe;
  while (start > 0 && text.codeUnitAt(start - 1).isIdentifierChar) {
    start--;
  }

  // Expand right.
  var end = probe + 1;
  while (end < text.length && text.codeUnitAt(end).isIdentifierChar) {
    end++;
  }

  return text.substring(start, end);
}
