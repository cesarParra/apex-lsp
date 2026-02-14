int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Ensure we use less memory by keeping the shorter string as "b".
  if (a.length < b.length) {
    final tmp = a;
    a = b;
    b = tmp;
  }

  final previous = List<int>.generate(b.length + 1, (i) => i);
  final current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    final aChar = a.codeUnitAt(i - 1);

    for (var j = 1; j <= b.length; j++) {
      final cost = aChar == b.codeUnitAt(j - 1) ? 0 : 1;

      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;

      var best = deletion;
      if (insertion < best) best = insertion;
      if (substitution < best) best = substitution;

      current[j] = best;
    }

    for (var j = 0; j < current.length; j++) {
      previous[j] = current[j];
    }
  }

  return previous[b.length];
}
