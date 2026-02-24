import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Completion matchers
// ---------------------------------------------------------------------------

/// Asserts a [CompletionList] contains an item with the given label.
///
///   expect(completions, containsCompletion('myVariable'));
Matcher containsCompletion(String label) => _CompletionLabelsMatcher(
  description: 'contains completion "$label"',
  predicate: (labels) => labels.contains(label),
);

/// Asserts a [CompletionList] does not contain an item with the given label.
///
///   expect(completions, doesNotContainCompletion('myVariable'));
Matcher doesNotContainCompletion(String label) => _CompletionLabelsMatcher(
  description: 'does not contain completion "$label"',
  predicate: (labels) => !labels.contains(label),
);

/// Asserts a [CompletionList] contains items with all the given labels
/// (in any order).
///
///   expect(completions, containsCompletions(['SPRING', 'SUMMER']));
Matcher containsCompletions(List<String> labels) => _CompletionLabelsMatcher(
  description: 'contains completions ${labels.join(", ")}',
  predicate: (actual) => labels.every(actual.contains),
);

/// Asserts a [CompletionList] has exactly these labels (in any order).
///
///   expect(completions, hasExactCompletions(['foo', 'bar']));
Matcher hasExactCompletions(List<String> labels) => _CompletionLabelsMatcher(
  description: 'has exact completions ${labels.join(", ")}',
  predicate: (actual) {
    final sortedActual = [...actual]..sort();
    final sortedExpected = [...labels]..sort();
    return _listEquals(sortedActual, sortedExpected);
  },
);

/// Asserts a [CompletionList] has no items.
///
///   expect(completions, hasNoCompletions);
final Matcher hasNoCompletions = _CompletionLabelsMatcher(
  description: 'has no completions',
  predicate: (labels) => labels.isEmpty,
);

/// Asserts a [CompletionList] is marked incomplete.
///
///   expect(completions, isIncompleteList);
final Matcher isIncompleteList = isA<CompletionList>().having(
  (list) => list.isIncomplete,
  'isIncomplete',
  isTrue,
);

/// Asserts a [CompletionList] is marked complete.
///
///   expect(completions, isCompleteList);
final Matcher isCompleteList = isA<CompletionList>().having(
  (list) => list.isIncomplete,
  'isIncomplete',
  isFalse,
);

// ---------------------------------------------------------------------------
// Initialize matchers
// ---------------------------------------------------------------------------

/// Asserts an [InitializeResult] advertises a specific capability.
///
///   expect(result, hasCapability('completionProvider'));
Matcher hasCapability(String name) => isA<InitializeResult>().having(
  (result) => result.capabilities.toJson().containsKey(name),
  'capabilities contains "$name"',
  isTrue,
);

// ---------------------------------------------------------------------------
// Error response matchers (for sendRawRequest results)
// ---------------------------------------------------------------------------

/// Asserts a raw response map contains an LSP error with the given code.
///
///   expect(response, isLspError(-32002));
Matcher isLspError(int code) => predicate<Map<String, Object?>>((response) {
  final error = response['error'];
  if (error is! Map) return false;
  return error['code'] == code;
}, 'is LSP error with code $code');

/// Asserts a raw response map contains an LSP error with a specific message.
///
///   expect(response, isLspErrorWithMessage('Server not initialized'));
Matcher isLspErrorWithMessage(String message) =>
    predicate<Map<String, Object?>>((response) {
      final error = response['error'];
      if (error is! Map) return false;
      return error['message'] == message;
    }, 'is LSP error with message "$message"');

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

final class _CompletionLabelsMatcher extends Matcher {
  final String _description;
  final bool Function(List<String> labels) _predicate;

  _CompletionLabelsMatcher({
    required String description,
    required bool Function(List<String> labels) predicate,
  }) : _description = description,
       _predicate = predicate;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! CompletionList) return false;
    final labels = item.items.map((i) => i.label).toList();
    matchState['actualLabels'] = labels;
    return _predicate(labels);
  }

  @override
  Description describe(Description description) =>
      description.add(_description);

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! CompletionList) {
      return mismatchDescription.add('was not a CompletionList');
    }
    final labels = matchState['actualLabels'] as List<String>;
    return mismatchDescription.add('had labels $labels');
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
