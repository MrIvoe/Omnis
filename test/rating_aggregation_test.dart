import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/rating_aggregation.dart';

BaseTrack _track({required String id}) => BaseTrack(
      id: id,
      title: 'Title $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

void main() {
  group('averageRating', () {
    test('an empty track list returns null', () {
      expect(averageRating(const [], (_) => 0), isNull);
    });

    test('a library with no rated tracks at all returns null, not a '
        '"0.0 average"', () {
      final tracks = [_track(id: '1'), _track(id: '2')];
      expect(averageRating(tracks, (_) => 0), isNull);
    });

    test('a single rated track returns its own rating as the average',
        () {
      final tracks = [_track(id: '1')];
      final summary = averageRating(tracks, (_) => 4);

      expect(summary, isNotNull);
      expect(summary!.average, 4.0);
      expect(summary.ratedCount, 1);
    });

    test('unrated tracks (rating 0) are excluded from both the average '
        'and the rated count', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      int ratingOf(String id) => switch (id) {
            '1' => 4,
            '2' => 0, // unrated
            _ => 2,
          };

      final summary = averageRating(tracks, ratingOf);

      expect(summary, isNotNull);
      expect(summary!.average, 3.0); // (4 + 2) / 2, not / 3
      expect(summary.ratedCount, 2);
    });

    test('all-same-rating tracks average to exactly that rating', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      final summary = averageRating(tracks, (_) => 5);

      expect(summary!.average, 5.0);
      expect(summary.ratedCount, 3);
    });

    test('a fractional average is computed correctly, not rounded', () {
      final tracks = [_track(id: '1'), _track(id: '2')];
      int ratingOf(String id) => id == '1' ? 4 : 5;

      final summary = averageRating(tracks, ratingOf);

      expect(summary!.average, 4.5);
    });

    test('three ratings averaging to a repeating decimal are computed as '
        'a real double, not truncated to an int', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      int ratingOf(String id) => switch (id) {
            '1' => 3,
            '2' => 4,
            _ => 5,
          };

      final summary = averageRating(tracks, ratingOf);

      expect(summary!.average, 4.0);
    });
  });
}
