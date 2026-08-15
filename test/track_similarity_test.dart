import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/track_similarity.dart';

void main() {
  BaseTrack track({
    required String id,
    List<String> genres = const [],
    String? mood,
    double? bpm,
    String? key,
  }) =>
      BaseTrack(
        id: id,
        title: 'Track $id',
        artists: const ['Artist'],
        album: 'Album',
        duration: 200,
        type: TrackType.local,
        genres: genres,
        mood: mood,
        bpm: bpm,
        key: key,
      );

  group('similarityScore — no comparable data', () {
    test('two tracks with zero data on every signal score 0.0, not NaN or '
        'a divide-by-zero crash', () {
      final a = track(id: 'a');
      final b = track(id: 'b');
      expect(similarityScore(a, b), 0.0);
    });

    test('a signal present on only one side is ignored entirely, not '
        'treated as a mismatch', () {
      final a = track(id: 'a', bpm: 120);
      final b = track(id: 'b'); // no bpm at all
      expect(similarityScore(a, b), 0.0);
    });
  });

  group('similarityScore — genre (Jaccard over the genre set)', () {
    test('identical single-genre tracks score 1.0 on that signal alone',
        () {
      final a = track(id: 'a', genres: const ['Rock']);
      final b = track(id: 'b', genres: const ['Rock']);
      expect(similarityScore(a, b), 1.0);
    });

    test('genre matching is case- and whitespace-insensitive', () {
      final a = track(id: 'a', genres: const [' Rock ']);
      final b = track(id: 'b', genres: const ['rock']);
      expect(similarityScore(a, b), 1.0);
    });

    test('partial genre overlap scores strictly between 0 and 1', () {
      final a = track(id: 'a', genres: const ['Rock', 'Pop']);
      final b = track(id: 'b', genres: const ['Rock', 'Jazz']);
      // Jaccard = |{Rock}| / |{Rock,Pop,Jazz}| = 1/3.
      expect(similarityScore(a, b), closeTo(1 / 3, 0.0001));
    });

    test('completely disjoint genres score 0.0', () {
      final a = track(id: 'a', genres: const ['Rock']);
      final b = track(id: 'b', genres: const ['Jazz']);
      expect(similarityScore(a, b), 0.0);
    });

    test('an empty genre list on either side excludes genre from the '
        'comparison entirely rather than scoring 0 for "no overlap" — a '
        'matching mood alone still reaches a perfect score', () {
      final a = track(id: 'a', genres: const [], mood: 'chill');
      final b = track(id: 'b', genres: const ['Rock'], mood: 'chill');
      expect(similarityScore(a, b), 1.0);
    });
  });

  group('similarityScore — mood (exact match only)', () {
    test('identical mood scores 1.0 on that signal', () {
      final a = track(id: 'a', mood: 'chill');
      final b = track(id: 'b', mood: 'chill');
      expect(similarityScore(a, b), 1.0);
    });

    test('mood matching is case-insensitive', () {
      final a = track(id: 'a', mood: 'Chill');
      final b = track(id: 'b', mood: 'CHILL');
      expect(similarityScore(a, b), 1.0);
    });

    test('different moods score 0.0 for that signal (not a partial credit)',
        () {
      final a = track(id: 'a', mood: 'chill', genres: const ['Rock']);
      final b = track(id: 'b', mood: 'aggressive', genres: const ['Rock']);
      // Genre matches fully (weight 0.35), mood scores 0 (weight 0.30);
      // combined score should be less than the genre-only weight share.
      expect(similarityScore(a, b), lessThan(1.0));
      expect(similarityScore(a, b), greaterThan(0.0));
    });

    test('an empty-string mood is treated the same as null — excluded, '
        'not compared', () {
      final a = track(id: 'a', mood: '', genres: const ['Rock']);
      final b = track(id: 'b', mood: 'chill', genres: const ['Rock']);
      final c = track(id: 'c', genres: const ['Rock']); // mood: null
      expect(similarityScore(a, b), similarityScore(c, b));
    });
  });

  group('similarityScore — BPM (linear falloff, zero past the tolerance)',
      () {
    test('identical BPM scores 1.0 on that signal', () {
      final a = track(id: 'a', bpm: 120);
      final b = track(id: 'b', bpm: 120);
      expect(similarityScore(a, b), 1.0);
    });

    test('BPM difference at or beyond the zero-score delta (30) scores 0 '
        'for that signal, clamped rather than going negative', () {
      final a = track(id: 'a', bpm: 90, genres: const ['Rock']);
      final b = track(id: 'b', bpm: 200, genres: const ['Rock']); // 110 apart
      final c = track(id: 'c', bpm: 999999, genres: const ['Rock']);
      // Both should collapse to the same score: pure genre weight share,
      // since BPM contributes exactly 0 past the tolerance in either case.
      expect(similarityScore(a, b), closeTo(similarityScore(a, c), 0.0001));
    });

    test('a partial BPM difference scores strictly between 0 and 1', () {
      final a = track(id: 'a', bpm: 120);
      final b = track(id: 'b', bpm: 135); // 15 apart, half of the 30 delta
      expect(similarityScore(a, b), closeTo(0.5, 0.0001));
    });

    test('closer BPM always scores at least as high as farther BPM, all '
        'else equal (monotonic falloff)', () {
      final seed = track(id: 'seed', bpm: 120);
      final near = track(id: 'near', bpm: 125);
      final far = track(id: 'far', bpm: 145);
      expect(similarityScore(seed, near), greaterThanOrEqualTo(similarityScore(seed, far)));
    });
  });

  group('similarityScore — key (exact match only)', () {
    test('identical key scores 1.0 on that signal', () {
      final a = track(id: 'a', key: 'C Major');
      final b = track(id: 'b', key: 'C Major');
      expect(similarityScore(a, b), 1.0);
    });

    test('key matching is case-insensitive', () {
      final a = track(id: 'a', key: 'c major');
      final b = track(id: 'b', key: 'C MAJOR');
      expect(similarityScore(a, b), 1.0);
    });

    test('different keys score 0.0 for that signal', () {
      final a = track(id: 'a', key: 'C Major', genres: const ['Rock']);
      final b = track(id: 'b', key: 'D Minor', genres: const ['Rock']);
      expect(similarityScore(a, b), lessThan(1.0));
    });
  });

  group('similarityScore — combined signals and weighting', () {
    test('a track matching on every signal scores exactly 1.0', () {
      final a = track(id: 'a', genres: const ['Rock'], mood: 'chill', bpm: 120, key: 'C Major');
      final b = track(id: 'b', genres: const ['Rock'], mood: 'chill', bpm: 120, key: 'C Major');
      expect(similarityScore(a, b), 1.0);
    });

    test('genre carries more weight than key alone — an exact genre match '
        'beats an exact key match when only one can be true', () {
      final seed = track(id: 'seed', genres: const ['Rock'], key: 'C Major');
      final genreMatch = track(id: 'g', genres: const ['Rock'], key: 'D Minor');
      final keyMatch = track(id: 'k', genres: const ['Jazz'], key: 'C Major');
      expect(similarityScore(seed, genreMatch), greaterThan(similarityScore(seed, keyMatch)));
    });

    test('is symmetric: score(a, b) == score(b, a)', () {
      final a = track(id: 'a', genres: const ['Rock', 'Pop'], mood: 'chill', bpm: 118, key: 'C Major');
      final b = track(id: 'b', genres: const ['Rock', 'Jazz'], mood: 'aggressive', bpm: 130, key: 'D Minor');
      expect(similarityScore(a, b), closeTo(similarityScore(b, a), 0.0001));
    });

    test('score never exceeds 1.0 or drops below 0.0 across many random-ish '
        'combinations', () {
      final pool = [
        track(id: '1', genres: const ['Rock'], mood: 'chill', bpm: 90, key: 'C Major'),
        track(id: '2', genres: const ['Jazz', 'Soul'], mood: 'sad', bpm: 200, key: 'A Minor'),
        track(id: '3', genres: const [], mood: null, bpm: null, key: null),
        track(id: '4', genres: const ['Rock', 'Metal'], mood: 'aggressive', bpm: 140),
        track(id: '5', bpm: 60, key: 'E Major'),
      ];
      for (final a in pool) {
        for (final b in pool) {
          final score = similarityScore(a, b);
          expect(score, greaterThanOrEqualTo(0.0));
          expect(score, lessThanOrEqualTo(1.0));
        }
      }
    });
  });

  group('findSimilarTracks', () {
    test('excludes the seed track itself even if it is present in the '
        'library and would otherwise score 1.0 against itself', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final result = findSimilarTracks(seed, [seed]);
      expect(result, isEmpty);
    });

    test('empty library returns empty', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      expect(findSimilarTracks(seed, const []), isEmpty);
    });

    test('a seed with no comparable data at all returns empty rather than '
        'an arbitrary ranking of the whole library', () {
      final seed = track(id: 'seed'); // no genres/mood/bpm/key
      final library = [
        track(id: 'a', genres: const ['Rock']),
        track(id: 'b', mood: 'chill'),
      ];
      expect(findSimilarTracks(seed, library), isEmpty);
    });

    test('results are sorted most-similar first', () {
      final seed = track(id: 'seed', genres: const ['Rock'], bpm: 120);
      final closeMatch = track(id: 'close', genres: const ['Rock'], bpm: 121);
      final farMatch = track(id: 'far', genres: const ['Rock'], bpm: 200);
      final result = findSimilarTracks(seed, [farMatch, closeMatch]);
      expect(result, [closeMatch, farMatch]);
    });

    test('tracks that share nothing with the seed are excluded entirely, '
        'not included with a score of 0', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final noOverlap = track(id: 'none', genres: const ['Classical']);
      final overlap = track(id: 'match', genres: const ['Rock']);
      final result = findSimilarTracks(seed, [noOverlap, overlap]);
      expect(result, [overlap]);
    });

    test('result length is capped at limit', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final library = List.generate(10, (i) => track(id: 't$i', genres: const ['Rock']));
      final result = findSimilarTracks(seed, library, limit: 3);
      expect(result.length, 3);
    });

    test('does not mutate the input library list', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final library = [
        track(id: 'b', genres: const ['Rock'], bpm: 100),
        track(id: 'a', genres: const ['Rock'], bpm: 121),
      ];
      final before = List<BaseTrack>.from(library);
      findSimilarTracks(seed, library);
      expect(library, before);
    });
  });
}
