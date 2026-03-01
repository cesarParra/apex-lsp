import 'package:apex_lsp/completion/helpers.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';

/// Base class for completion context types.
///
/// Completion context represents the syntactic location where code completion
/// was triggered, determining what kind of suggestions are appropriate.
///
/// See also:
///  * [CompletionContextNone], when no valid completion context is detected.
///  * [CompletionContextTopLevel], for top-level type and variable completions.
///  * [CompletionContextMember], for member access completions.
sealed class CompletionContext {
  /// The partial identifier prefix being typed at the cursor position.
  ///
  /// Used for filtering and ranking completion candidates.
  final String prefix;
  const CompletionContext({required this.prefix});
}

/// Completion context indicating no valid completion location.
///
/// This occurs when the cursor is in a position where code completion
/// doesn't make sense, such as inside string literals or comments.
///
/// Example scenarios:
/// ```dart
/// // Cursor inside a string literal
/// String name = "test|";  // | = cursor
/// ```
final class CompletionContextNone extends CompletionContext {
  const CompletionContextNone() : super(prefix: '');

  @override
  String toString() {
    return 'CompletionContextNone()';
  }
}

/// Completion context for top-level type names and local variables.
///
/// This context applies when the cursor is in a position where type names,
/// local variables, or method names can appear, but not after a dot operator.
///
/// Example scenarios:
/// ```dart
/// Acc|  // Type name completion
/// accountList.|  // Before the dot (not this context)
/// String name = acc|  // Variable name completion
/// ```
final class CompletionContextTopLevel extends CompletionContext {
  const CompletionContextTopLevel({
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
    return 'CompletionContextClass(className: $prefix)';
  }
}

/// Completion context for member access via dot operator.
///
/// This context applies when the cursor follows a dot (`.`) or safe navigation
/// (`?.`) operator, indicating member access on an object or type.
///
/// Example scenarios:
/// ```dart
/// account.|  // Instance member access
/// Account.|  // Static member access or enum values
/// Colors.R|  // Enum value completion with prefix 'R'
/// ```
final class CompletionContextMember extends CompletionContext {
  const CompletionContextMember({
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
    return 'CompletionContextMember(objectName: $objectName, typeName: $typeName, prefix: $prefix, text: $text, cursorOffset: $cursorOffset)';
  }
}

/// Determines the completion context at the cursor position in [text].
///
/// Uses the [index] to resolve variable types and type names when detecting
/// member-access contexts (e.g. `account.`).
Future<CompletionContext> detectCompletionContext({
  required String text,
  required int cursorOffset,
  required List<Declaration> index,
}) async {
  final prefix = text.extractIndentifierPrefixAt(cursorOffset);

  var dotIndex = _findMemberDotIndex(text, cursorOffset);

  // When typing a member name (e.g. "foo.ba"), the cursor is past the dot.
  // Look before the prefix to find the dot operator.
  if (dotIndex == null && prefix.isNotEmpty) {
    final probeIndex = cursorOffset - prefix.length - 1;
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
      return CompletionContextNone();
    }

    if (DeclarationName(objectName) == const DeclarationName('this')) {
      final enclosingClass = index.enclosingAt<IndexedClass>(cursorOffset);

      return CompletionContextMember(
        typeName: enclosingClass?.name.value,
        objectName: objectName,
        prefix: prefix,
        text: text,
        cursorOffset: cursorOffset,
      );
    }

    final declaration =
        index.findDeclaration(DeclarationName(objectName)) ??
        index.resolveQualifiedName(objectName);

    return CompletionContextMember(
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
      prefix: prefix,
      text: text,
      cursorOffset: cursorOffset,
    );
  }

  return CompletionContextTopLevel(
    prefix: prefix,
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
