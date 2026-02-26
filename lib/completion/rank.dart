import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/levenshtein_distance.dart';

/// Function signature for ranking completion candidates.
///
/// Takes a collection of candidates and a prefix string, and returns
/// the candidates in ranked order (most relevant first).
///
/// - First parameter: The completion candidates to rank.
/// - Second parameter: The prefix string to rank against.
///
/// Returns the ranked candidates as an iterable.
typedef Rank =
    Iterable<CompletionCandidate> Function(
      Iterable<CompletionCandidate>,
      String prefix,
    );

typedef _ScoredCandidate = ({
  CompletionCandidate candidate,
  int editDistance,
  int nameLength,
});

/// Ranks completion candidates by relevance to the prefix, returning at most
/// [limit] results.
///
/// Uses Levenshtein distance to measure similarity between the prefix and
/// candidate names. Candidates are ranked by:
/// 1. **Edit distance** (lower is better) - fewer character changes needed
/// 2. **Name length** (shorter is better) - prefer concise names
/// 3. **Alphabetical order** - consistent tie-breaking
///
/// - [candidates]: The completion candidates to rank.
/// - [prefix]: The partial identifier being typed. Case-insensitive comparison.
/// - [limit]: Maximum number of results to return. Defaults to returning all.
///
/// Uses a bounded insertion strategy — O(n × limit) rather than O(n log n) —
/// which is significantly faster when [limit] is small (e.g. 25).
///
/// Returns candidates sorted by relevance. When [prefix] is empty, returns
/// candidates in their original order (up to [limit]).
///
/// Example:
/// ```dart
/// final candidates = [
///   ApexTypeCandidate(IndexedClass(DeclarationName('Account'))),
///   ApexTypeCandidate(IndexedClass(DeclarationName('Accordion'))),
///   ApexTypeCandidate(IndexedClass(DeclarationName('Contact'))),
/// ];
/// final ranked = rankCandidates(candidates, 'Acc');
/// // Returns: [Account, Accordion, Contact]
/// // Account has distance 0, Accordion distance 6, Contact distance 7
/// ```
///
/// See also:
///  * [levenshteinDistance], which computes edit distance.
Iterable<CompletionCandidate> rankCandidates(
  Iterable<CompletionCandidate> candidates,
  String prefix, {
  int? limit,
}) {
  if (prefix.isEmpty) {
    return limit == null ? candidates : candidates.take(limit);
  }

  final lowerPrefix = prefix.toLowerCase();

  // Bounded insertion: maintain a sorted list of at most [limit] entries.
  // For each candidate we compute its score and binary-search for its
  // insertion point. When the buffer is full, candidates that score worse
  // than the current worst are skipped without further work.
  final rankedBuffer = <_ScoredCandidate>[];

  for (final candidate in candidates) {
    final scored = _scoreFor(candidate, lowerPrefix);

    if (limit != null && rankedBuffer.length == limit) {
      if (_compareScore(scored, rankedBuffer.last) >= 0) continue;
      rankedBuffer.removeLast();
    }

    _insertSorted(rankedBuffer, scored);
  }

  return rankedBuffer.map((scored) => scored.candidate);
}

_ScoredCandidate _scoreFor(CompletionCandidate candidate, String lowerPrefix) {
  return (
    candidate: candidate,
    editDistance: levenshteinDistance(
      lowerPrefix,
      candidate.name.toLowerCase(),
    ),
    nameLength: candidate.name.length,
  );
}

int _compareScore(_ScoredCandidate a, _ScoredCandidate b) {
  final byDistance = a.editDistance.compareTo(b.editDistance);
  if (byDistance != 0) return byDistance;
  final byLength = a.nameLength.compareTo(b.nameLength);
  if (byLength != 0) return byLength;
  return a.candidate.name.compareTo(b.candidate.name);
}

void _insertSorted(List<_ScoredCandidate> sortedList, _ScoredCandidate entry) {
  var low = 0;
  var high = sortedList.length;
  while (low < high) {
    final mid = (low + high) >>> 1;
    if (_compareScore(sortedList[mid], entry) <= 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  sortedList.insert(low, entry);
}
