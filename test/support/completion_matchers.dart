import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

/// Asserts a [CompletionList] contains an item with the given label and kind.
Matcher completionWithKind(String label, CompletionItemKind kind) =>
    predicate<CompletionList>(
      (list) => list.items.any((i) => i.label == label && i.kind == kind),
      'contains completion "$label" with kind $kind',
    );

/// Asserts a [CompletionList] contains an item with the given label and detail.
Matcher completionWithDetail(String label, String detail) =>
    predicate<CompletionList>(
      (list) => list.items.any((i) => i.label == label && i.detail == detail),
      'contains completion "$label" with detail "$detail"',
    );

/// Asserts a [CompletionList] contains an item with the given label, kind,
/// and detail.
Matcher completionWith({
  required String label,
  required CompletionItemKind kind,
  String? detail,
}) => predicate<CompletionList>(
  (list) => list.items.any(
    (i) => i.label == label && i.kind == kind && i.detail == detail,
  ),
  'contains completion "$label" with kind $kind'
  '${detail != null ? ' and detail "$detail"' : ''}',
);

/// Asserts a [CompletionList] contains an item with the given label and
/// label details.
Matcher completionWithLabelDetails({
  required String label,
  String? detail,
  String? description,
}) => predicate<CompletionList>(
  (list) => list.items.any(
    (i) =>
        i.label == label &&
        i.labelDetails?.detail == detail &&
        i.labelDetails?.description == description,
  ),
  'contains completion "$label" with label details'
  '${detail != null ? ' "$detail"' : ''}'
  '${description != null ? ' and description "$description"' : ''}',
);
