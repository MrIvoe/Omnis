import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_operations.dart';

BaseTrack _track(String id) => BaseTrack(
      id: id,
      title: 'Title $id',
      artists: const ['Artist'],
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
}
