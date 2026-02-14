sealed class CompletionCandidates {
  final List<String> labels;

  CompletionCandidates({required this.labels});
}

final class NoCandidates extends CompletionCandidates {
  NoCandidates() : super(labels: const []);
}

final class ClassNameOrLocalCandidates extends CompletionCandidates {
  ClassNameOrLocalCandidates({required super.labels});

  @override
  String toString() {
    return 'ClassNameOrLocalCandidates(labels: $labels)';
  }
}

final class MemberCandidates extends CompletionCandidates {
  MemberCandidates({
    required super.labels,
    required this.memberOfType,
    required this.objectName,
    required this.memberTypeResolvedFromDocument,
  });

  /// The resolved type name. e.g. `Foo`.
  final String memberOfType;

  // When [kind] is [CompletionKid.member], this represents the name of the
  // object. For example, if the user typed `foo.m`, then this is foo.
  final String objectName;

  /// True when member type resolution came from the document index.
  final bool memberTypeResolvedFromDocument;
}
