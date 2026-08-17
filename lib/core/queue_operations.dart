import 'dart:math' as math;

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_rules.dart';

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

  /// Moves the track at [from] to [to], using the same `(oldIndex,
  /// newIndex)` convention Flutter's `ReorderableListView.onReorder`
  /// hands callers directly — [to] is the target index as if [from]
  /// hadn't been removed yet, so moving an item one slot later (`to ==
  /// from + 1`) is correctly a no-op rather than a same-position
  /// round-trip.
  ///
  /// Returns the reordered queue and [currentIndex]'s new position —
  /// the currently-playing track's identity never changes, only where
  /// it now sits, so callers can rebuild the audio source around the
  /// returned index without interrupting playback.
  static (List<BaseTrack>, int) reorder(
    List<BaseTrack> queue,
    int currentIndex,
    int from,
    int to,
  ) {
    if (from < 0 ||
        from >= queue.length ||
        to < 0 ||
        to > queue.length) {
      return (List<BaseTrack>.of(queue), currentIndex);
    }
    final insertAt = from < to ? to - 1 : to;
    if (insertAt == from) {
      return (List<BaseTrack>.of(queue), currentIndex);
    }

    final newQueue = List<BaseTrack>.of(queue);
    final track = newQueue.removeAt(from);
    newQueue.insert(insertAt, track);

    final int newCurrentIndex;
    if (currentIndex == from) {
      newCurrentIndex = insertAt;
    } else {
      final shifted = currentIndex > from ? currentIndex - 1 : currentIndex;
      newCurrentIndex = shifted >= insertAt ? shifted + 1 : shifted;
    }
    return (newQueue, newCurrentIndex);
  }

  /// Shuffles everything after [currentIndex], leaving the current track
  /// and everything already played untouched. With no current track
  /// (`currentIndex < 0`), shuffles the whole queue.
  ///
  /// [constraints] defaults to [QueueRuleConstraints.none] (a pure
  /// no-op) — item 2's "queue rules/exclusions" gap. When active, the
  /// shuffled tail is repaired via [applyQueueRules] against itself and
  /// [head] (the already-placed/played tracks, so a repeat right at the
  /// shuffle boundary is caught too), never against the pre-shuffle
  /// order.
  static List<BaseTrack> shuffledRemaining(
    List<BaseTrack> queue,
    int currentIndex, {
    math.Random? random,
    QueueRuleConstraints constraints = QueueRuleConstraints.none,
    bool groupByAlbumArtist = false,
  }) {
    final splitAt = currentIndex < 0 ? 0 : currentIndex + 1;
    if (splitAt >= queue.length) return List<BaseTrack>.of(queue);
    final head = queue.sublist(0, splitAt);
    final tail = queue.sublist(splitAt).toList()..shuffle(random);
    final repairedTail = constraints.isActive
        ? applyQueueRules(tail, constraints,
            groupByAlbumArtist: groupByAlbumArtist, precedingContext: head)
        : tail;
    return [...head, ...repairedTail];
  }
}
