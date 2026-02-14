import 'package:apex_lsp/message.dart';

/// Result of extracting cursor position from text with a {cursor} marker.
class TextWithPosition {
  /// The text with the {cursor} marker removed.
  final String text;

  /// The position where the cursor was located.
  final Position position;

  const TextWithPosition({required this.text, required this.position});
}

/// Converts text containing a {cursor} marker into a Position and clean text.
///
/// The marker {cursor} indicates where the cursor position should be.
/// Lines are 0-indexed and characters are 0-indexed as per LSP specification.
///
/// Example:
/// ```dart
/// final result = extractCursorPosition('Foo.{cursor}');
/// // result.position == Position(line: 0, character: 4)
/// // result.text == 'Foo.'
/// ```
///
/// Throws [ArgumentError] if the text does not contain exactly one {cursor} marker.
TextWithPosition extractCursorPosition(String text) {
  const marker = '{cursor}';

  final markerIndex = text.indexOf(marker);
  if (markerIndex == -1) {
    throw ArgumentError('Text must contain a {cursor} marker');
  }

  if (text.indexOf(marker, markerIndex + 1) != -1) {
    throw ArgumentError('Text must contain exactly one {cursor} marker');
  }

  int line = 0;
  int character = 0;

  for (int i = 0; i < markerIndex; i++) {
    if (text[i] == '\n') {
      line++;
      character = 0;
    } else {
      character++;
    }
  }

  final cleanText = text.replaceFirst(marker, '');

  return TextWithPosition(
    text: cleanText,
    position: Position(line: line, character: character),
  );
}
