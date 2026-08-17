import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_operations.dart';
import 'package:omnis/core/queue_rules.dart';

BaseTrack _track(String id, {String artist = 'Artist'}) => BaseTrack(
      id: id,
      title: 'Title $id',
      artists: [artist],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

void main() {
  group('duplicateIndicesToRemove', () {
    test('keeps the first occurrence of each id, flags the rest', () {
      final queue = [_track('a'), _track('b'), _track('a'), _track('a')];

      final result = QueueOperations.duplicateIndicesToRemove(queue);

      expect(result, [3, 2]);
    });

    test('a queue with no duplicates returns empty', () {
      final queue = [_track('a'), _track('b'), _track('c')];

      expect(QueueOperations.duplicateIndicesToRemove(queue), isEmpty);
    });

    test('an empty queue returns empty', () {
      expect(QueueOperations.duplicateIndicesToRemove(const []), isEmpty);
    });

    test('never flags currentIndex even if it is a later duplicate', () {
      final queue = [_track('a'), _track('b'), _track('a')];

      final result = QueueOperations.duplicateIndicesToRemove(
        queue,
        currentIndex: 2,
      );

      expect(result, [0]);
    });

    test('an earlier occurrence is removed instead of currentIndex, not '
        'the other way around', () {
      final queue = [_track('a'), _track('a'), _track('a')];

      final result = QueueOperations.duplicateIndicesToRemove(
        queue,
        currentIndex: 1,
      );

      expect(result, [2, 0]);
    });

    test('an out-of-range currentIndex is ignored, not treated as a real '
        'position', () {
      final queue = [_track('a'), _track('a')];

      final result = QueueOperations.duplicateIndicesToRemove(
        queue,
        currentIndex: 99,
      );

      expect(result, [1]);
    });

    test('result is always in descending order so callers can remove '
        'safely without index shift', () {
      final queue = [
        _track('a'),
        _track('b'),
        _track('a'),
        _track('b'),
        _track('c'),
        _track('c'),
      ];

      final result = QueueOperations.duplicateIndicesToRemove(queue);

      expect(result, [5, 3, 2]);
      for (var i = 0; i < result.length - 1; i++) {
        expect(result[i], greaterThan(result[i + 1]));
      }
    });
  });

  group('playedIndicesToRemove', () {
    test('returns every index strictly before currentIndex, descending',
        () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final result = QueueOperations.playedIndicesToRemove(queue, 3);

      expect(result, [2, 1, 0]);
    });

    test('currentIndex 0 (nothing played yet) returns empty', () {
      final queue = [_track('a'), _track('b')];

      expect(QueueOperations.playedIndicesToRemove(queue, 0), isEmpty);
    });

    test('a negative currentIndex returns empty', () {
      final queue = [_track('a'), _track('b')];

      expect(QueueOperations.playedIndicesToRemove(queue, -1), isEmpty);
    });

    test('an empty queue returns empty regardless of currentIndex', () {
      expect(QueueOperations.playedIndicesToRemove(const [], 5), isEmpty);
    });

    test('currentIndex past the end of the queue clamps to the queue '
        'length rather than throwing', () {
      final queue = [_track('a'), _track('b')];

      final result = QueueOperations.playedIndicesToRemove(queue, 99);

      expect(result, [1, 0]);
    });
  });

  group('reorder', () {
    test('moving an item later places it right after its drop target, '
        'the standard Flutter onReorder off-by-one convention', () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 0, 0, 2);

      expect(newQueue.map((t) => t.id), ['b', 'a', 'c', 'd']);
      expect(newCurrentIndex, 1);
    });

    test('moving an item earlier (to the top)', () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 0, 2, 0);

      expect(newQueue.map((t) => t.id), ['c', 'a', 'b', 'd']);
      expect(newCurrentIndex, 1);
    });

    test('dropping an item one slot later than itself is a no-op, not a '
        'same-position round trip', () {
      final queue = [_track('a'), _track('b'), _track('c')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 1, 0, 1);

      expect(newQueue.map((t) => t.id), ['a', 'b', 'c']);
      expect(newCurrentIndex, 1);
    });

    test('moving the currently-playing track follows it to its new index',
        () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 0, 0, 2);

      expect(newQueue[newCurrentIndex].id, 'a');
    });

    test('moving a track from after currentIndex to before it shifts '
        'currentIndex forward by one', () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 1, 3, 0);

      expect(newQueue.map((t) => t.id), ['d', 'a', 'b', 'c']);
      expect(newCurrentIndex, 2);
      expect(newQueue[newCurrentIndex].id, 'b');
    });

    test('an out-of-range from/to is a no-op rather than throwing', () {
      final queue = [_track('a'), _track('b')];

      final (newQueue, newCurrentIndex) =
          QueueOperations.reorder(queue, 0, 5, 0);

      expect(newQueue.map((t) => t.id), ['a', 'b']);
      expect(newCurrentIndex, 0);
    });

    test('the returned queue is a new list, not the same instance', () {
      final queue = [_track('a'), _track('b')];

      final (newQueue, _) = QueueOperations.reorder(queue, 0, 0, 1);

      expect(identical(newQueue, queue), isFalse);
    });
  });

  group('shuffledRemaining', () {
    test('leaves everything up to and including currentIndex untouched',
        () {
      final queue = [_track('a'), _track('b'), _track('c'), _track('d')];

      final result = QueueOperations.shuffledRemaining(queue, 1);

      expect(result.sublist(0, 2).map((t) => t.id), ['a', 'b']);
      expect(result.map((t) => t.id).toSet(), {'a', 'b', 'c', 'd'});
    });

    test('a deterministic Random produces a reproducible shuffle', () {
      final queue =
          List.generate(10, (i) => _track('t$i'));

      final result = QueueOperations.shuffledRemaining(
        queue,
        -1,
        random: math.Random(42),
      );

      expect(result.map((t) => t.id).toSet(), queue.map((t) => t.id).toSet());
      expect(result.map((t) => t.id).toList(), isNot(queue.map((t) => t.id).toList()),
          reason: 'a real shuffle of 10 items landing back in original '
              'order is astronomically unlikely and would indicate a bug');
    });

    test('currentIndex -1 (no current track) shuffles the whole queue',
        () {
      final queue = [_track('a'), _track('b'), _track('c')];

      final result = QueueOperations.shuffledRemaining(queue, -1);

      expect(result.map((t) => t.id).toSet(), {'a', 'b', 'c'});
      expect(result.length, 3);
    });

    test('currentIndex at or past the last index returns the queue '
        'unchanged', () {
      final queue = [_track('a'), _track('b')];

      final result = QueueOperations.shuffledRemaining(queue, 1);

      expect(result.map((t) => t.id), ['a', 'b']);
    });

    test('an empty queue returns empty', () {
      expect(QueueOperations.shuffledRemaining(const [], 0), isEmpty);
    });

    test('default (no constraints) behavior is unchanged — same set, same '
        'head', () {
      final queue = [
        _track('a', artist: 'X'),
        _track('b', artist: 'X'),
        _track('c', artist: 'X'),
        _track('d', artist: 'X'),
      ];

      final result = QueueOperations.shuffledRemaining(queue, 0,
          random: math.Random(7));

      expect(result.first.id, 'a');
      expect(result.map((t) => t.id).toSet(), {'a', 'b', 'c', 'd'});
    });

    test('an active constraint reorders the shuffled tail to satisfy it',
        () {
      // Two of three remaining tracks share an artist — Random(127)'s raw
      // shuffle lands a1/a2 adjacent ([a1, a2, b1]), which the constraint
      // then repairs into [a1, b1, a2]. (Pinning a specific seed's exact
      // output follows the same convention as the "deterministic Random
      // produces a reproducible shuffle" test above.)
      final queue = [
        _track('head', artist: 'Head'),
        _track('a1', artist: 'X'),
        _track('a2', artist: 'X'),
        _track('b1', artist: 'Y'),
      ];

      final unconstrained = QueueOperations.shuffledRemaining(queue, 0,
          random: math.Random(127));
      expect(unconstrained.map((t) => t.id).toList(),
          ['head', 'a1', 'a2', 'b1']);

      final result = QueueOperations.shuffledRemaining(
        queue,
        0,
        random: math.Random(127),
        constraints: const QueueRuleConstraints(minArtistGap: 1),
      );

      expect(result.map((t) => t.id).toList(), ['head', 'a1', 'b1', 'a2']);
    });
  });
}
