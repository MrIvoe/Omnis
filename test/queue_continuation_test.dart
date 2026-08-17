import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_continuation.dart';

void main() {
  BaseTrack track({
    required String id,
    String artist = 'Artist',
    String album = 'Album',
    String? albumArtist,
    List<String> genres = const [],
    String? mood,
    double? bpm,
    String? key,
  }) =>
      BaseTrack(
        id: id,
        title: 'Track $id',
        artists: [artist],
        album: album,
        albumArtist: albumArtist,
        duration: 200,
        type: TrackType.local,
        genres: genres,
        mood: mood,
        bpm: bpm,
        key: key,
      );

  group('continuationTracks — off', () {
    test('always returns empty regardless of library contents', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final library = [seed, track(id: 'a', genres: const ['Rock'])];
      expect(
        continuationTracks(
          seed: seed,
          library: library,
          mode: QueueContinuationMode.off,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — similarTrack', () {
    test('picks tracks scoring above 0.0 via the real similarity function',
        () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final match = track(id: 'match', genres: const ['Rock']);
      final nonMatch = track(id: 'other', genres: const ['Jazz']);
      final result = continuationTracks(
        seed: seed,
        library: [seed, match, nonMatch],
        mode: QueueContinuationMode.similarTrack,
      );
      expect(result, [match]);
    });

    test('never includes the seed itself even if somehow scored', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final result = continuationTracks(
        seed: seed,
        library: [seed],
        mode: QueueContinuationMode.similarTrack,
      );
      expect(result, isEmpty);
    });

    test('respects excludeIds', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final match = track(id: 'match', genres: const ['Rock']);
      final result = continuationTracks(
        seed: seed,
        library: [seed, match],
        mode: QueueContinuationMode.similarTrack,
        excludeIds: {'match'},
      );
      expect(result, isEmpty);
    });

    test('respects limit', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final library = [
        seed,
        for (var i = 0; i < 5; i++)
          track(id: 'm$i', genres: const ['Rock']),
      ];
      final result = continuationTracks(
        seed: seed,
        library: library,
        mode: QueueContinuationMode.similarTrack,
        limit: 3,
      );
      expect(result, hasLength(3));
    });

    test('a seed with no comparable data yields an empty list, not an '
        'arbitrary fallback', () {
      final seed = track(id: 'seed');
      final library = [seed, track(id: 'a', genres: const ['Rock'])];
      expect(
        continuationTracks(
          seed: seed,
          library: library,
          mode: QueueContinuationMode.similarTrack,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — similarArtist', () {
    test('pools tracks from artists similar to the seed track\'s own '
        'artist, excluding the seed artist\'s own tracks', () {
      final seed = track(id: 'seed', artist: 'A', genres: const ['Rock']);
      final sameArtist = track(id: 'a2', artist: 'A', genres: const ['Rock']);
      final similarArtist =
          track(id: 'b1', artist: 'B', genres: const ['Rock']);
      final unrelatedArtist =
          track(id: 'c1', artist: 'C', genres: const ['Jazz']);
      final result = continuationTracks(
        seed: seed,
        library: [seed, sameArtist, similarArtist, unrelatedArtist],
        mode: QueueContinuationMode.similarArtist,
        random: Random(1),
      );
      expect(result, [similarArtist]);
    });

    test('groups by album artist when groupByAlbumArtist is true', () {
      final seed = track(
          id: 'seed',
          artist: 'Feat Artist',
          albumArtist: 'Main Artist',
          genres: const ['Rock']);
      final sameAlbumArtistTrack = track(
          id: 'a2',
          artist: 'Other Feat',
          albumArtist: 'Main Artist',
          genres: const ['Rock']);
      final similar = track(
          id: 'b1',
          artist: 'B',
          albumArtist: 'B',
          genres: const ['Rock']);
      final result = continuationTracks(
        seed: seed,
        library: [seed, sameAlbumArtistTrack, similar],
        mode: QueueContinuationMode.similarArtist,
        groupByAlbumArtist: true,
        random: Random(1),
      );
      expect(result, [similar]);
    });

    test('a seed artist with no comparable data yields an empty list', () {
      final seed = track(id: 'seed', artist: 'A');
      final other = track(id: 'b1', artist: 'B', genres: const ['Rock']);
      expect(
        continuationTracks(
          seed: seed,
          library: [seed, other],
          mode: QueueContinuationMode.similarArtist,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — sameGenre', () {
    test('matches any track sharing at least one genre, case-insensitively',
        () {
      final seed = track(id: 'seed', genres: const ['Rock', 'Pop']);
      final match = track(id: 'a', genres: const [' rock ']);
      final noMatch = track(id: 'b', genres: const ['Jazz']);
      final result = continuationTracks(
        seed: seed,
        library: [seed, match, noMatch],
        mode: QueueContinuationMode.sameGenre,
        random: Random(1),
      );
      expect(result, [match]);
    });

    test('a seed with no genres yields an empty list', () {
      final seed = track(id: 'seed');
      final other = track(id: 'a', genres: const ['Rock']);
      expect(
        continuationTracks(
          seed: seed,
          library: [seed, other],
          mode: QueueContinuationMode.sameGenre,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — sameMood', () {
    test('matches an exact, case-insensitive mood', () {
      final seed = track(id: 'seed', mood: 'Happy');
      final match = track(id: 'a', mood: ' happy ');
      final noMatch = track(id: 'b', mood: 'Sad');
      final result = continuationTracks(
        seed: seed,
        library: [seed, match, noMatch],
        mode: QueueContinuationMode.sameMood,
        random: Random(1),
      );
      expect(result, [match]);
    });

    test('a seed with no mood yields an empty list', () {
      final seed = track(id: 'seed');
      final other = track(id: 'a', mood: 'Happy');
      expect(
        continuationTracks(
          seed: seed,
          library: [seed, other],
          mode: QueueContinuationMode.sameMood,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — sameAlbum', () {
    test('matches tracks on the same album by the same album artist', () {
      final seed = track(id: 'seed', album: 'X', albumArtist: 'AA');
      final match = track(id: 'a', album: 'X', albumArtist: 'AA');
      final differentAlbumArtist =
          track(id: 'b', album: 'X', albumArtist: 'Other');
      final differentAlbum = track(id: 'c', album: 'Y', albumArtist: 'AA');
      final result = continuationTracks(
        seed: seed,
        library: [seed, match, differentAlbumArtist, differentAlbum],
        mode: QueueContinuationMode.sameAlbum,
        random: Random(1),
      );
      expect(result, [match]);
    });

    test('a seed with an empty album yields an empty list', () {
      final seed = track(id: 'seed', album: '');
      final other = track(id: 'a', album: '');
      expect(
        continuationTracks(
          seed: seed,
          library: [seed, other],
          mode: QueueContinuationMode.sameAlbum,
        ),
        isEmpty,
      );
    });
  });

  group('continuationTracks — general behavior', () {
    test('an empty library returns empty without crashing', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      expect(
        continuationTracks(
          seed: seed,
          library: const [],
          mode: QueueContinuationMode.similarTrack,
        ),
        isEmpty,
      );
    });

    test('a fully-excluded pool returns empty without crashing', () {
      final seed = track(id: 'seed', genres: const ['Rock']);
      final match = track(id: 'match', genres: const ['Rock']);
      expect(
        continuationTracks(
          seed: seed,
          library: [seed, match],
          mode: QueueContinuationMode.sameGenre,
          excludeIds: {'match'},
        ),
        isEmpty,
      );
    });

    test('a seeded Random makes shuffle-based modes deterministic', () {
      final seed = track(id: 'seed', mood: 'Happy');
      final library = [
        seed,
        for (var i = 0; i < 4; i++) track(id: 'm$i', mood: 'Happy'),
      ];
      final first = continuationTracks(
        seed: seed,
        library: library,
        mode: QueueContinuationMode.sameMood,
        random: Random(42),
      );
      final second = continuationTracks(
        seed: seed,
        library: library,
        mode: QueueContinuationMode.sameMood,
        random: Random(42),
      );
      expect(first, second);
    });
  });
}
