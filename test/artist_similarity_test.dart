import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/artist_similarity.dart';
import 'package:omnis/core/base_track.dart';

BaseTrack _track({
  required String id,
  List<String> genres = const [],
  String? mood,
  double? bpm,
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
    );

void main() {
  group('buildArtistProfile', () {
    test('genres are the union across every track, deduplicated and '
        'normalized', () {
      final profile = buildArtistProfile('A', [
        _track(id: '1', genres: const ['Rock', 'Pop']),
        _track(id: '2', genres: const ['rock', 'Indie']),
      ]);
      expect(profile.genres, {'rock', 'pop', 'indie'});
    });

    test('dominant mood is whichever mood appears most often', () {
      final profile = buildArtistProfile('A', [
        _track(id: '1', mood: 'Happy'),
        _track(id: '2', mood: 'Happy'),
        _track(id: '3', mood: 'Sad'),
      ]);
      expect(profile.dominantMood, 'happy');
    });

    test('a mood tie is broken alphabetically, deterministically', () {
      final profile = buildArtistProfile('A', [
        _track(id: '1', mood: 'Sad'),
        _track(id: '2', mood: 'Happy'),
      ]);
      expect(profile.dominantMood, 'happy');
    });

    test('averageBpm is the mean of only the tracks that have one', () {
      final profile = buildArtistProfile('A', [
        _track(id: '1', bpm: 100),
        _track(id: '2', bpm: 120),
        _track(id: '3'), // no bpm — excluded, not treated as 0
      ]);
      expect(profile.averageBpm, 110.0);
    });

    test('an artist with zero tracks having any signal at all yields an '
        'empty/null profile, not a crash', () {
      final profile = buildArtistProfile('A', [_track(id: '1')]);
      expect(profile.genres, isEmpty);
      expect(profile.dominantMood, isNull);
      expect(profile.averageBpm, isNull);
    });

    test('an empty track list yields an empty/null profile', () {
      final profile = buildArtistProfile('A', const []);
      expect(profile.genres, isEmpty);
      expect(profile.dominantMood, isNull);
      expect(profile.averageBpm, isNull);
    });
  });

  group('artistSimilarityScore — no comparable data', () {
    test('two artists with zero data on every signal score 0.0, not NaN '
        'or a divide-by-zero crash', () {
      final a = buildArtistProfile('A', [_track(id: '1')]);
      final b = buildArtistProfile('B', [_track(id: '2')]);
      expect(artistSimilarityScore(a, b), 0.0);
    });

    test('a signal present on only one side is ignored entirely, not '
        'treated as a mismatch', () {
      final a = buildArtistProfile('A', [_track(id: '1', bpm: 120)]);
      final b = buildArtistProfile('B', [_track(id: '2')]); // no bpm
      expect(artistSimilarityScore(a, b), 0.0);
    });
  });

  group('artistSimilarityScore — genre (Jaccard over the genre set)', () {
    test('identical single-genre artists score 1.0 on that signal alone',
        () {
      final a = buildArtistProfile(
          'A', [_track(id: '1', genres: const ['Rock'])]);
      final b = buildArtistProfile(
          'B', [_track(id: '2', genres: const ['Rock'])]);
      expect(artistSimilarityScore(a, b), 1.0);
    });

    test('disjoint genre sets score 0.0 on that signal', () {
      final a = buildArtistProfile(
          'A', [_track(id: '1', genres: const ['Rock'])]);
      final b = buildArtistProfile(
          'B', [_track(id: '2', genres: const ['Jazz'])]);
      expect(artistSimilarityScore(a, b), 0.0);
    });

    test('a partial genre overlap scores the correct Jaccard ratio', () {
      final a = buildArtistProfile(
          'A', [_track(id: '1', genres: const ['Rock', 'Pop'])]);
      final b = buildArtistProfile(
          'B', [_track(id: '2', genres: const ['Rock', 'Jazz'])]);
      // Intersection {Rock} = 1, union {Rock, Pop, Jazz} = 3 -> 1/3 — the
      // only present signal, so it's the whole (renormalized) score.
      expect(artistSimilarityScore(a, b), closeTo(1 / 3, 0.0001));
    });
  });

  group('artistSimilarityScore — mood', () {
    test('matching dominant moods score full mood weight', () {
      final a = buildArtistProfile('A', [_track(id: '1', mood: 'Happy')]);
      final b = buildArtistProfile('B', [_track(id: '2', mood: 'Happy')]);
      expect(artistSimilarityScore(a, b), 1.0);
    });

    test('mismatched dominant moods score 0.0 on that signal', () {
      final a = buildArtistProfile('A', [_track(id: '1', mood: 'Happy')]);
      final b = buildArtistProfile('B', [_track(id: '2', mood: 'Sad')]);
      expect(artistSimilarityScore(a, b), 0.0);
    });
  });

  group('artistSimilarityScore — average BPM', () {
    test('identical average BPM scores full bpm weight', () {
      final a = buildArtistProfile('A', [_track(id: '1', bpm: 120)]);
      final b = buildArtistProfile('B', [_track(id: '2', bpm: 120)]);
      expect(artistSimilarityScore(a, b), 1.0);
    });

    test('a BPM difference at or beyond the 30 BPM width scores 0.0', () {
      final a = buildArtistProfile('A', [_track(id: '1', bpm: 90)]);
      final b = buildArtistProfile('B', [_track(id: '2', bpm: 120)]);
      expect(artistSimilarityScore(a, b), 0.0);
    });

    test('a BPM difference within the width scores proportionally', () {
      final a = buildArtistProfile('A', [_track(id: '1', bpm: 100)]);
      final b = buildArtistProfile('B', [_track(id: '2', bpm: 115)]);
      // (1 - 15/30) = 0.5 — bpm is the only present signal, so its raw
      // score, not the weighted contribution, is the whole renormalized
      // result.
      expect(artistSimilarityScore(a, b), closeTo(0.5, 0.0001));
    });
  });

  group('artistSimilarityScore — combined signals', () {
    test('scoring is symmetric regardless of argument order', () {
      final a = buildArtistProfile('A',
          [_track(id: '1', genres: const ['Rock'], mood: 'Happy', bpm: 120)]);
      final b = buildArtistProfile('B',
          [_track(id: '2', genres: const ['Rock'], mood: 'Sad', bpm: 100)]);
      expect(artistSimilarityScore(a, b), artistSimilarityScore(b, a));
    });

    test('the score never leaves the [0, 1] bounds across a spread of '
        'combinations', () {
      final profiles = [
        buildArtistProfile('A',
            [_track(id: '1', genres: const ['Rock', 'Metal'], bpm: 140)]),
        buildArtistProfile(
            'B', [_track(id: '2', genres: const ['Jazz'], mood: 'Chill')]),
        buildArtistProfile('C', [_track(id: '3', bpm: 60)]),
        buildArtistProfile('D', [_track(id: '4')]),
      ];
      for (final p1 in profiles) {
        for (final p2 in profiles) {
          final score = artistSimilarityScore(p1, p2);
          expect(score, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });

  group('findSimilarArtists', () {
    test('excludes the seed artist itself', () {
      final byArtist = {
        'Seed': [_track(id: '1', genres: const ['Rock'])],
        'Other': [_track(id: '2', genres: const ['Rock'])],
      };
      final result = findSimilarArtists('Seed', byArtist);
      expect(result, isNot(contains('Seed')));
    });

    test('a seed artist not present in the map returns an empty list',
        () {
      final byArtist = {
        'Other': [_track(id: '1', genres: const ['Rock'])],
      };
      expect(findSimilarArtists('NotThere', byArtist), isEmpty);
    });

    test('a seed with no comparable data yields an empty list rather '
        'than an arbitrary ranking of the whole library', () {
      final byArtist = {
        'Seed': [_track(id: '1')], // no genre/mood/bpm at all
        'Other': [_track(id: '2', genres: const ['Rock'])],
      };
      expect(findSimilarArtists('Seed', byArtist), isEmpty);
    });

    test('ranks candidates by descending similarity score', () {
      final byArtist = {
        'Seed': [_track(id: '1', genres: const ['Rock', 'Metal'], bpm: 120)],
        'CloseMatch': [
          _track(id: '2', genres: const ['Rock', 'Metal'], bpm: 121)
        ],
        'FarMatch': [_track(id: '3', genres: const ['Rock'])],
        'NoMatch': [_track(id: '4', genres: const ['Classical'])],
      };
      final result = findSimilarArtists('Seed', byArtist);
      expect(result, ['CloseMatch', 'FarMatch']);
    });

    test('respects the limit parameter', () {
      final byArtist = {
        'Seed': [_track(id: '1', genres: const ['Rock'])],
        'A': [_track(id: '2', genres: const ['Rock'])],
        'B': [_track(id: '3', genres: const ['Rock'])],
        'C': [_track(id: '4', genres: const ['Rock'])],
      };
      expect(findSimilarArtists('Seed', byArtist, limit: 2), hasLength(2));
    });

    test('an empty tracksByArtist map returns an empty list', () {
      expect(findSimilarArtists('Seed', const {}), isEmpty);
    });

    test('an artist mapped to an empty track list is never a candidate '
        'and never crashes as the seed either', () {
      final byArtist = {
        'Seed': [_track(id: '1', genres: const ['Rock'])],
        'Empty': <BaseTrack>[],
      };
      expect(findSimilarArtists('Seed', byArtist), isEmpty);
      expect(findSimilarArtists('Empty', byArtist), isEmpty);
    });
  });
}
