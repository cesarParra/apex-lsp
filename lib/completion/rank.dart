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

/// Ranks completion candidates by relevance to the prefix.
///
/// Uses Levenshtein distance to measure similarity between the prefix and
/// candidate names. Candidates are ranked by:
/// 1. **Edit distance** (lower is better) - fewer character changes needed
/// 2. **Name length** (shorter is better) - prefer concise names
/// 3. **Alphabetical order** - consistent tie-breaking
///
/// - [candidates]: The completion candidates to rank.
/// - [prefix]: The partial identifier being typed. Case-insensitive comparison.
///
/// Returns candidates sorted by relevance. When [prefix] is empty, returns
/// candidates in their original order.
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
  String prefix,
) {
  // No ranking needed for empty prefix
  if (prefix.isEmpty) return candidates;
  final lowerPrefix = prefix.toLowerCase();

  // Score each candidate with distance and length metrics
  final scored =
      candidates
          .map(
            (candidate) => (
              candidate: candidate,
              length: candidate.name.length,
              distance: levenshteinDistance(
                lowerPrefix,
                candidate.name.toLowerCase(),
              ),
            ),
          )
          .toList()
        ..sort((a, b) {
          // Primary sort: smallest edit distance (most similar)
          final byDistance = a.distance.compareTo(b.distance);
          if (byDistance != 0) return byDistance;

          // Secondary sort: shortest name (prefer concise options)
          final byLength = a.length.compareTo(b.length);
          if (byLength != 0) return byLength;

          // Tertiary sort: alphabetical (consistent tie-breaking)
          return a.candidate.name.compareTo(b.candidate.name);
        });

  return scored.map((c) => c.candidate).toList();
}
