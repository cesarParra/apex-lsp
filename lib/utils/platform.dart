import 'dart:io';

/// Abstraction for platform-specific queries and behavior.
///
/// This allows tests to override platform detection (e.g. simulating Windows
/// on a macOS host) and ensures deterministic behavior in unit tests.
abstract interface class LspPlatform {
  /// Whether the current platform is Windows.
  bool get isWindows;

  /// The character used to separate path segments (e.g. '/' or '\').
  String get pathSeparator;
}

/// The default implementation using 'dart:io'.
final class DartIoLspPlatform implements LspPlatform {
  const DartIoLspPlatform();

  @override
  bool get isWindows => Platform.isWindows;

  @override
  String get pathSeparator => Platform.pathSeparator;
}
