/// Compares two dotted version strings (e.g. `"1.2.3"`) numerically,
/// segment by segment — not lexically, so `"1.10.0"` correctly compares
/// greater than `"1.9.0"` (a plain string compare would get this
/// backwards: `"1.10.0" < "1.9.0"`).
///
/// Returns a negative number if [a] < [b], zero if equal, positive if
/// [a] > [b] — the same contract `Comparable.compareTo` uses.
///
/// A non-numeric segment (a plugin author writing `"1.0.0-beta"`, or
/// just a malformed version string) is treated as `0` for that segment
/// rather than throwing — this drives an *optional* "update available"
/// nudge, not a hard gate, so degrading gracefully to "no difference
/// detected" for a version string this can't fully parse is safer than
/// crashing the update check for every other installed plugin.
int compareVersions(String a, String b) {
  final partsA = a.trim().split('.');
  final partsB = b.trim().split('.');
  final length = partsA.length > partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < length; i++) {
    final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
    final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
    if (numA != numB) return numA - numB;
  }
  return 0;
}
