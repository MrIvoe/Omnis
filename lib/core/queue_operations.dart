import 'package:omnis/core/base_track.dart';

/// Pure index-selection logic for queue cleanup actions ("Remove
/// duplicates", "Clear played"). Kept free of [AudioEngine] so it's
/// fully unit-testable without the deferred injectable-player test seam
/// (item 9) — callers loop the returned indices through
/// `AudioEngine.removeTrack(index)` themselves, highest index first so
/// earlier indices don't shift out from under later removals.
///
/// Indices are always returned in descending order for that reason.
class QueueOperations {
  const QueueOperations._();

  /// Indices of duplicate tracks (matched by [BaseTrack.id]) to remove,
  /// keeping the first occurrence of each id — except [currentIndex],
  /// which is always kept even if it's a later duplicate, so removing
  /// duplicates never disturbs what's currently playing.
  static List<int> duplicateIndicesToRemove(
    List<BaseTrack> queue, {
    int? currentIndex,
  }) {
    final seen = <String>{};
    if (currentIndex != null &&
        currentIndex >= 0 &&
        currentIndex < queue.length) {
      seen.add(queue[currentIndex].id);
    }
    final toRemove = <int>[];
    for (var i = 0; i < queue.length; i++) {
      if (i == currentIndex) continue;
      final id = queue[i].id;
      if (!seen.add(id)) toRemove.add(i);
    }
    return toRemove.reversed.toList();
  }

  /// Indices strictly before [currentIndex] — the tracks that have
  /// already been played. Returns an empty list when there's nothing
  /// queued before the current position.
  static List<int> playedIndicesToRemove(
    List<BaseTrack> queue,
    int currentIndex,
  ) {
    if (currentIndex <= 0) return const [];
    final end = currentIndex > queue.length ? queue.length : currentIndex;
    return List<int>.generate(end, (i) => end - 1 - i);
  }
}
