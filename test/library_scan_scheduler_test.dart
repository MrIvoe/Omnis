import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_scan_scheduler.dart';

BaseTrack _track({
  required String id,
  DateTime? dateAdded,
}) =>
    BaseTrack(
      id: id,
      title: 'Title $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
      dateAdded: dateAdded,
    );

void main() {
  final now = DateTime(2026, 8, 16);

  group('LibraryScanScheduler.isDue', () {
    test('null lastScanAt is always due, regardless of interval', () {
      expect(
        LibraryScanScheduler.isDue(null, const Duration(hours: 24), now),
        isTrue,
      );
    });

    test('a scan older than the interval is due', () {
      final last = now.subtract(const Duration(hours: 7));
      expect(
        LibraryScanScheduler.isDue(last, const Duration(hours: 6), now),
        isTrue,
      );
    });

    test('a scan within the interval is not due', () {
      final last = now.subtract(const Duration(hours: 2));
      expect(
        LibraryScanScheduler.isDue(last, const Duration(hours: 6), now),
        isFalse,
      );
    });

    test('exactly at the interval boundary is due — >=, not >', () {
      final last = now.subtract(const Duration(hours: 6));
      expect(
        LibraryScanScheduler.isDue(last, const Duration(hours: 6), now),
        isTrue,
      );
    });

    test('a scan timestamp in the future (clock skew) is not due', () {
      final last = now.add(const Duration(hours: 1));
      expect(
        LibraryScanScheduler.isDue(last, const Duration(hours: 6), now),
        isFalse,
      );
    });
  });

  group('newTracksFromScan', () {
    test('an empty scan result finds nothing new', () {
      final current = [_track(id: '1')];
      expect(newTracksFromScan(current, const []), isEmpty);
    });

    test('a scan that only re-reports existing ids finds nothing new', () {
      final current = [_track(id: '1'), _track(id: '2')];
      final scanned = [_track(id: '1'), _track(id: '2')];
      expect(newTracksFromScan(current, scanned), isEmpty);
    });

    test('a scan result with a genuinely new id is returned', () {
      final current = [_track(id: '1')];
      final scanned = [_track(id: '1'), _track(id: '2')];

      final result = newTracksFromScan(current, scanned);

      expect(result.map((t) => t.id), ['2']);
    });

    test('an empty current library treats every scanned track as new', () {
      final scanned = [_track(id: '1'), _track(id: '2')];
      final result = newTracksFromScan(const [], scanned);
      expect(result.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('a new track with no dateAdded is stamped with now()', () {
      final fixedNow = DateTime(2026, 1, 1);
      final scanned = [_track(id: '1')];

      final result =
          newTracksFromScan(const [], scanned, now: () => fixedNow);

      expect(result.single.dateAdded, fixedNow);
    });

    test("a new track that already has its own dateAdded keeps it, "
        "not overwritten by now()", () {
      final original = DateTime(2020, 1, 1);
      final scanned = [_track(id: '1', dateAdded: original)];

      final result =
          newTracksFromScan(const [], scanned, now: () => DateTime(2026, 1, 1));

      expect(result.single.dateAdded, original);
    });
  });
}
