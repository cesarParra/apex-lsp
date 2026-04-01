import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/type_name.dart';

extension IntCompletionExtension on int {
  /// Whether the character is an Apex identifier or not.
  /// An identifier matches the following rules:
  /// - Letters (A-Z, a-z)
  /// - Digits (0-9)
  /// - Underscore (_)
  /// - Dollar sign ($)
  bool get isIdentifierChar {
    return (this >= 48 && this <= 57) || // 0-9
        (this >= 65 && this <= 90) || // A-Z
        (this >= 97 && this <= 122) || // a-z
        this == 95 || // _
        this == 36;
  }
}

extension StringCompletionExtension on String {
  /// Extracts the identifier prefix immediately before the cursor offset.
  /// Scans backward from the cursor position to find the start of an identifier.
  ///
  /// This prefix is used to filter completion candidates and compute ranking.
  ///
  /// - [text]: The complete text content.
  /// - [cursorOffset]: Zero-based byte offset of the cursor position.
  ///
  /// Returns the identifier prefix as a string, which may be empty if the cursor
  /// is not positioned after an identifier character.
  ///
  /// Example:
  /// ```dart
  /// final prefix = text.extractIndentifierPrefixAt(19);
  /// // For 'System.debug(myVar)', returns 'myVar'
  /// ```
  String extractIndentifierPrefixAt(int cursorOffset) {
    var i = cursorOffset;
    if (i > length) i = length;

    var start = i;
    while (start > 0 && codeUnitAt(start - 1).isIdentifierChar) {
      start--;
    }
    return substring(start, i);
  }

  /// Extracts a qualified identifier (including periods) immediately before the cursor offset.
  /// Scans backward from the cursor position, accepting identifier characters and periods.
  /// Supports qualified names (e.g., OuterClass.InnerClass).
  ///
  /// - [cursorOffset]: Zero-based byte offset of the cursor position.
  ///
  /// Returns the qualified identifier as a string, which may be empty if the cursor
  /// is not positioned after an identifier character or period.
  ///
  /// Example:
  /// ```dart
  /// final name = text.extractQualifiedIdentifierAt(23);
  /// // For 'OuterClass.InnerClass', returns 'OuterClass.InnerClass'
  /// ```
  String extractQualifiedIdentifierAt(int cursorOffset) {
    var i = cursorOffset;
    if (i > length) i = length;

    var start = i;
    while (start > 0) {
      final ch = codeUnitAt(start - 1);
      if (ch.isIdentifierChar || ch == 0x2E /* . */ ) {
        start--;
      } else {
        break;
      }
    }
    return substring(start, i).trim();
  }

  bool startsWithIgnoreCase(String prefix) {
    return toLowerCase().startsWith(prefix.toLowerCase());
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

extension DeclarationsExtension on List<Declaration> {
  IndexedType? findType(DeclarationName name) =>
      whereType<IndexedType>().firstWhereOrNull(
        (indexedType) => indexedType.name == name,
      ) ??
      whereType<IndexedClass>()
          .expand((c) => c.members)
          .whereType<IndexedType>()
          .firstWhereOrNull((indexedType) => indexedType.name == name);

  Declaration? findDeclaration(DeclarationName name) =>
      firstWhereOrNull((declaration) => declaration.name == name);

  T? enclosingAt<T extends Declaration>(int cursorOffset) =>
      whereType<T>().firstWhereOrNull((declaration) {
        final location = declaration.location;
        if (location == null) return false;
        return cursorOffset >= location.$1 && cursorOffset <= location.$2;
      });

  /// Returns the innermost (smallest byte range) [T] that contains [cursorOffset].
  ///
  /// When multiple declarations of type [T] are nested (e.g. an inner class
  /// inside an outer class), this returns the most specific one rather than
  /// the first encountered in the list.
  T? innermostEnclosingAt<T extends Declaration>(int cursorOffset) {
    T? result;
    int? smallestRange;
    for (final declaration in whereType<T>()) {
      final location = declaration.location;
      if (location == null) continue;
      if (cursorOffset < location.$1 || cursorOffset > location.$2) continue;
      final range = location.$2 - location.$1;
      if (smallestRange == null || range < smallestRange) {
        smallestRange = range;
        result = declaration;
      }
    }
    return result;
  }

  /// Resolves a dot-qualified name (e.g. "Foo.Bar") by walking through
  /// class members. Returns null if any segment cannot be resolved.
  Declaration? resolveQualifiedName(String qualifiedName) {
    final segments = qualifiedName.split('.');
    if (segments.length < 2) {
      return findDeclaration(DeclarationName(qualifiedName));
    }

    Declaration? current = findDeclaration(DeclarationName(segments.first));
    for (var i = 1; i < segments.length; i++) {
      if (current is! IndexedClass) return null;
      final memberName = DeclarationName(segments[i]);
      current = current.members.firstWhereOrNull((m) => m.name == memberName);
    }
    return current;
  }
}

/// The result of extracting an identifier from text at a cursor position.
///
/// Contains both the extracted identifier [value] and the [startOffset]
/// within the text where the identifier begins. The start offset is needed
/// for dot-context detection, which probes one position before the identifier
/// to check for a `.` operator.
typedef ExtractedIdentifier = ({String value, int startOffset});

/// A function that extracts an identifier from [text] at [cursorOffset].
///
/// Different strategies are used depending on the consumer:
/// - [extractIdentifierPrefix] scans backward only (for completion, where only the
///   text already typed matters).
/// - [extractIdentifierAtCursor] scans in both directions (for hover, where the
///   entire word under the cursor is needed).
typedef IdentifierExtractor =
    ExtractedIdentifier Function(String text, int cursorOffset);

/// Extracts the identifier prefix before the cursor (backward scan only).
///
/// Used by the completion system, where only the already-typed portion
/// matters for filtering candidates.
ExtractedIdentifier extractIdentifierPrefix(String text, int cursorOffset) {
  final value = text.extractIndentifierPrefixAt(cursorOffset);
  return (value: value, startOffset: cursorOffset - value.length);
}

/// Extracts the full identifier token under the cursor (bidirectional scan).
///
/// Used by the hover system, where the entire word the cursor is touching
/// is needed for exact-match resolution.
ExtractedIdentifier extractIdentifierAtCursor(String text, int cursorOffset) {
  if (text.isEmpty) return (value: '', startOffset: cursorOffset);

  final offset = cursorOffset.clamp(0, text.length - 1).toInt();

  // If cursor is not on an identifier character, try one position left.
  int probe = offset;
  if (!text.codeUnitAt(probe).isIdentifierChar) {
    if (probe > 0) {
      probe--;
    } else {
      return (value: '', startOffset: cursorOffset);
    }
  }

  if (!text.codeUnitAt(probe).isIdentifierChar) {
    return (value: '', startOffset: cursorOffset);
  }

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

  return (value: text.substring(start, end), startOffset: start);
}

/// Extracts declarations from method/constructor bodies and class members.
///
/// Used by both completion and hover to expand the index with declarations
/// from the enclosing context.
///
/// Since blocks are flattened during indexing, we only need to extract the
/// immediate body.declarations list from methods and constructors.
/// For classes, we recursively extract from all members and static initializers.
List<Declaration> getBodyDeclarations(Declaration? declaration) {
  return switch (declaration) {
    null ||
    FieldMember() ||
    EnumValueMember() ||
    IndexedVariable() ||
    IndexedInterface() ||
    IndexedEnum() ||
    IndexedSObject() => const [],

    // Declarations with body
    ConstructorDeclaration(:final body) ||
    MethodDeclaration(:final body) => body.declarations,

    PropertyDeclaration(:final getterBody, :final setterBody) => [
      ...?getterBody?.declarations,
      ...?setterBody?.declarations,
    ],

    IndexedClass() => [
      ...declaration.members,
      ...declaration.members.expand(getBodyDeclarations),
      ...declaration.staticInitializers.expand((s) => s.declarations),
    ],
  };
}
