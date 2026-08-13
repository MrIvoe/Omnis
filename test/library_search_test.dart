import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_search.dart';

BaseTrack _track({
  required String id,
  String title = 'Track',
  List<String> artists = const ['Artist'],
  String album = 'Album',
  List<String> genres = const [],
  int? year,
  String? mood,
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: artists,
      album: album,
      duration: 200,
      type: TrackType.local,
      genres: genres,
      year: year,
      mood: mood,
    );

void main() {
  group('filterTracks — free text', () {
    final tracks = [
      _track(id: '1', title: 'Bohemian Rhapsody', artists: ['Queen'], album: 'A Night at the Opera'),
      _track(id: '2', title: 'Somebody to Love', artists: ['Queen'], album: 'A Day at the Races'),
      _track(id: '3', title: 'Imagine', artists: ['John Lennon'], album: 'Imagine'),
    ];

    test('empty query returns every track unchanged', () {
      expect(filterTracks(tracks, ''), tracks);
      expect(filterTracks(tracks, '   '), tracks);
    });

    test('matches title, case-insensitively', () {
      final result = filterTracks(tracks, 'IMAGINE');
      expect(result.map((t) => t.id), ['3']);
    });

    test('matches artist', () {
      final result = filterTracks(tracks, 'queen');
      expect(result.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('matches album', () {
      final result = filterTracks(tracks, 'opera');
      expect(result.map((t) => t.id), ['1']);
    });

    test('matches genre', () {
      final withGenre = [
        _track(id: 'g1', title: 'Song', genres: ['Rock']),
        _track(id: 'g2', title: 'Other', genres: ['Jazz']),
      ];
      expect(filterTracks(withGenre, 'rock').map((t) => t.id), ['g1']);
    });

    test('multiple free-text terms are ANDed', () {
      final result = filterTracks(tracks, 'queen night');
      expect(result.map((t) => t.id), ['1']);
    });

    test('no matches returns an empty list, not null or an error', () {
      expect(filterTracks(tracks, 'nonexistent xyz'), isEmpty);
    });
  });

  group('filterTracks — field-qualified terms', () {
    final tracks = [
      _track(id: '1', title: 'A', artists: ['Queen'], album: 'Greatest Hits', genres: ['Rock'], year: 1981),
      _track(id: '2', title: 'B', artists: ['Queen'], album: 'A Night at the Opera', genres: ['Rock'], year: 1975),
      _track(id: '3', title: 'C', artists: ['Metallica'], album: 'Master of Puppets', genres: ['Metal'], year: 1986),
    ];

    test('artist: matches only the artist field', () {
      final result = filterTracks(tracks, 'artist:queen');
      expect(result.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('artist: does not match a term that only appears in another '
        'field', () {
      // "metallica" appears nowhere but track 3's artist — artist:queen
      // must not accidentally match it via some other field.
      final result = filterTracks(tracks, 'artist:metallica');
      expect(result.map((t) => t.id), ['3']);
    });

    test('album: matches only the album field', () {
      final result = filterTracks(tracks, 'album:opera');
      expect(result.map((t) => t.id), ['2']);
    });

    test('genre: matches only the genre field', () {
      final result = filterTracks(tracks, 'genre:metal');
      expect(result.map((t) => t.id), ['3']);
    });

    test('year: matches an exact year', () {
      final result = filterTracks(tracks, 'year:1986');
      expect(result.map((t) => t.id), ['3']);
    });

    test('year: matches an inclusive range', () {
      final result = filterTracks(tracks, 'year:1975..1981');
      expect(result.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('year: with a malformed range matches nothing rather than '
        'throwing', () {
      expect(() => filterTracks(tracks, 'year:abc..def'), returnsNormally);
      expect(filterTracks(tracks, 'year:abc..def'), isEmpty);
    });

    test('a track with no year never matches a year: filter', () {
      final noYear = [_track(id: 'ny', year: null)];
      expect(filterTracks(noYear, 'year:2000'), isEmpty);
    });

    test('field terms combine with free text (AND)', () {
      // Free text only covers title/artist/album/genre, not year (see
      // filterTracks' own doc) — "hits" matches track 1's album
      // ("Greatest Hits"), narrowing artist:queen's two matches to one.
      final result = filterTracks(tracks, 'artist:queen hits');
      expect(result.map((t) => t.id), ['1']);
    });

    test('an unrecognized field prefix falls back to free text instead '
        'of matching nothing', () {
      // "format:flac" isn't a supported field yet — must not silently
      // exclude every track just because of the unknown prefix.
      final result = filterTracks(tracks, 'format:flac');
      expect(result, isEmpty); // no track's title/artist/album/genre
      // contains the literal text "format:flac", which is the correct
      // free-text fallback behavior, not a crash or a `known field`
      // exception.
    });

    test('field prefix matching is case-insensitive', () {
      final result = filterTracks(tracks, 'ARTIST:queen');
      expect(result.map((t) => t.id).toSet(), {'1', '2'});
    });
  });

  group('filterTracks — mood field', () {
    test('mood: matches the mood field', () {
      final tracks = [
        _track(id: '1', mood: 'Energetic'),
        _track(id: '2', mood: 'Chill'),
      ];
      expect(filterTracks(tracks, 'mood:chill').map((t) => t.id), ['2']);
    });

    test('mood: on a track with no mood never matches', () {
      final tracks = [_track(id: '1')];
      expect(filterTracks(tracks, 'mood:chill'), isEmpty);
    });
  });
}
