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
  // No ranking needed for empty prefix
  if (prefix.isEmpty) {
    return limit == null ? candidates : candidates.take(limit);
  }

  final lowerPrefix = prefix.toLowerCase();

  // Bounded insertion: maintain a sorted list of at most [limit] entries.
  // For each candidate we compute its score and binary-search for its
  // insertion point. When the buffer is full, candidates that score worse
  // than the current worst are skipped without further work.
  final topK = <({CompletionCandidate candidate, int distance, int length})>[];

  int compareScore(
    ({CompletionCandidate candidate, int distance, int length}) a,
    ({CompletionCandidate candidate, int distance, int length}) b,
  ) {
    final byDistance = a.distance.compareTo(b.distance);
    if (byDistance != 0) return byDistance;
    final byLength = a.length.compareTo(b.length);
    if (byLength != 0) return byLength;
    return a.candidate.name.compareTo(b.candidate.name);
  }

  for (final candidate in candidates) {
    final distance = levenshteinDistance(
      lowerPrefix,
      candidate.name.toLowerCase(),
    );
    final entry = (
      candidate: candidate,
      distance: distance,
      length: candidate.name.length,
    );

    if (limit != null && topK.length == limit) {
      // Buffer is full — only insert if this entry beats the current worst.
      if (compareScore(entry, topK.last) >= 0) continue;
      topK.removeLast();
    }

    // Binary search for the correct insertion position to keep topK sorted.
    var lo = 0;
    var hi = topK.length;
    while (lo < hi) {
      final mid = (lo + hi) >>> 1;
      if (compareScore(topK[mid], entry) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    topK.insert(lo, entry);
  }

  return topK.map((e) => e.candidate);
}
