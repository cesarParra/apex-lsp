import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';

/// Base class for symbol lookup context types.
///
/// Symbol context represents the syntactic location where a language feature
/// was triggered, determining what kind of symbol lookup is appropriate.
sealed class SymbolContext {
  /// The identifier text at the cursor position.
  final String prefix;
  const SymbolContext({required this.prefix});
}

/// Symbol context indicating no valid lookup location.
///
/// This occurs when the cursor is in a position where symbol lookup does not
/// apply, such as inside string literals or comments.
final class SymbolContextNone extends SymbolContext {
  const SymbolContextNone() : super(prefix: '');

  @override
  String toString() {
    return 'SymbolContextNone()';
  }
}

/// Symbol context for top-level type names and local variables.
final class SymbolContextTopLevel extends SymbolContext {
  const SymbolContextTopLevel({
    required super.prefix,
    required this.text,
    required this.cursorOffset,
  });

  /// The complete document text.
  final String text;

  /// The byte offset of the cursor position in the text.
  final int cursorOffset;

  @override
  String toString() {
    return 'SymbolContextTopLevel(prefix: $prefix)';
  }
}

/// Symbol context for member access via dot operator.
final class SymbolContextMember extends SymbolContext {
  const SymbolContextMember({
    required this.objectName,
    required this.typeName,
    required super.prefix,
    required this.text,
    required this.cursorOffset,
  });

  /// The type name to look up members for. May be `null` if unresolved.
  final String? typeName;

  /// The object or type name before the dot operator.
  final String? objectName;

  /// The complete document text.
  final String text;

  /// The byte offset of the cursor position in the text.
  final int cursorOffset;

  @override
  String toString() {
    return 'SymbolContextMember(objectName: $objectName, typeName: $typeName, prefix: $prefix, text: $text, cursorOffset: $cursorOffset)';
  }
}

/// Determines the symbol context at the cursor position in [text].
///
/// Uses the [index] to resolve variable types and type names when detecting
/// member-access contexts (e.g. `account.`).
///
/// The [extractIdentifier] parameter controls how the identifier at the cursor
/// is extracted. Defaults to [extractIdentifierPrefix] (backward scan only), which is
/// appropriate for completion. Pass [extractIdentifierAtCursor] for hover, where
/// the entire word under the cursor is needed.
Future<SymbolContext> detectSymbolContext({
  required String text,
  required int cursorOffset,
  required List<Declaration> index,
  IdentifierExtractor extractIdentifier = extractIdentifierPrefix,
}) async {
  final extracted = extractIdentifier(text, cursorOffset);
  final identifier = extracted.value;

  var dotIndex = _findMemberDotIndex(text, cursorOffset);

  // When the identifier is past the dot (e.g. "foo.ba" or "foo.bar"),
  // look before the identifier start to find the dot operator.
  if (dotIndex == null && identifier.isNotEmpty) {
    final probeIndex = extracted.startOffset - 1;
    if (probeIndex >= 0) {
      final ch = text.codeUnitAt(probeIndex);
      if (ch == 0x2E /* . */ ) {
        dotIndex = probeIndex;
      } else if (ch == 0x3F /* ? */ ) {
        final next = probeIndex + 1;
        if (next < text.length && text.codeUnitAt(next) == 0x2E /* . */ ) {
          dotIndex = next;
        }
      }
    }
  }

  if (dotIndex != null) {
    var objectIndex = dotIndex - 1;
    if (objectIndex >= 0 && text.codeUnitAt(objectIndex) == 0x3F /* ? */ ) {
      objectIndex--;
    }
    final objectName = _extractIdentifierBefore(text, objectIndex);
    if (objectName == null) {
      return SymbolContextNone();
    }

    final isThis = DeclarationName(objectName) == const DeclarationName('this');
    final isSuper =
        DeclarationName(objectName) == const DeclarationName('super');

    if (isThis || isSuper) {
      final enclosingClass = index.innermostEnclosingAt<IndexedClass>(cursorOffset);

      return SymbolContextMember(
        typeName: isThis
            ? enclosingClass?.name.value
            : enclosingClass?.superClass,
        objectName: objectName,
        prefix: identifier,
        text: text,
        cursorOffset: cursorOffset,
      );
    }

    final declaration =
        index.findDeclaration(DeclarationName(objectName)) ??
        index.resolveQualifiedName(objectName);

    return SymbolContextMember(
      typeName: switch (declaration) {
        null => null,
        ConstructorDeclaration() => throw UnsupportedError(
          'Autocompleting constructors is not supported at the moment',
        ),

        FieldMember(:final typeName) ||
        PropertyDeclaration(:final typeName) => typeName?.value,

        MethodDeclaration() || EnumValueMember() => throw UnimplementedError(),

        // Return the declared type name so member completions resolve correctly.
        IndexedVariable(:final typeName) => typeName.value,

        // Return the type's own name so static member completions resolve correctly.
        IndexedClass() ||
        IndexedInterface() ||
        IndexedEnum() ||
        IndexedSObject() => declaration.name.value,
      },
      objectName: objectName,
      prefix: identifier,
      text: text,
      cursorOffset: cursorOffset,
    );
  }

  return SymbolContextTopLevel(
    prefix: identifier,
    text: text,
    cursorOffset: cursorOffset,
  );
}

int? _findMemberDotIndex(String text, int cursorOffset) {
  var i = cursorOffset - 1;
  if (i < 0) return null;

  while (i >= 0 && _isWhitespace(text.codeUnitAt(i))) {
    i--;
  }
  if (i < 0) return null;

  final ch = text.codeUnitAt(i);

  if (ch == 0x2E /* . */ ) return i;

  if (ch == 0x3F /* ? */ ) {
    final next = i + 1;
    if (next < text.length && text.codeUnitAt(next) == 0x2E /* . */ ) {
      return next;
    }

    final prev = i - 1;
    if (prev >= 0 && text.codeUnitAt(prev) == 0x2E /* . */ ) return prev;
  }

  return null;
}

bool _isWhitespace(int ch) => ch == 32 || ch == 9 || ch == 10 || ch == 13;

String? _extractIdentifierBefore(String text, int index) {
  var i = index;
  while (i >= 0 && _isWhitespace(text.codeUnitAt(i))) {
    i--;
  }
  if (i < 0) return null;

  final identifier = text.extractQualifiedIdentifierAt(i + 1);
  return identifier.isNotEmpty ? identifier : null;
}
