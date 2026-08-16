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
  double? bpm,
  String? codec,
  int? bitrateKbps,
  String? coverArt,
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
      bpm: bpm,
      codec: codec,
      bitrateKbps: bitrateKbps,
      coverArt: coverArt,
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
      // "wishlist:someday" isn't a supported field — must not silently
      // exclude every track just because of the unknown prefix.
      final result = filterTracks(tracks, 'wishlist:someday');
      expect(result, isEmpty); // no track's title/artist/album/genre
      // contains the literal text "wishlist:someday", which is the correct
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

  group('filterTracks — rating field', () {
    final tracks = [
      _track(id: '5star'),
      _track(id: '3star'),
      _track(id: '0star'),
    ];
    int ratingOf(String id) => switch (id) {
          '5star' => 5,
          '3star' => 3,
          _ => 0,
        };

    test('rating:N matches an exact rating', () {
      expect(
        filterTracks(tracks, 'rating:3', ratingOf: ratingOf).map((t) => t.id),
        ['3star'],
      );
    });

    test('rating:>=N matches at or above the threshold', () {
      expect(
        filterTracks(tracks, 'rating:>=3', ratingOf: ratingOf)
            .map((t) => t.id),
        ['5star', '3star'],
      );
    });

    test('rating:<=N matches at or below the threshold', () {
      expect(
        filterTracks(tracks, 'rating:<=3', ratingOf: ratingOf)
            .map((t) => t.id),
        ['3star', '0star'],
      );
    });

    test('rating:>N and rating:<N are strict comparisons', () {
      expect(
        filterTracks(tracks, 'rating:>3', ratingOf: ratingOf).map((t) => t.id),
        ['5star'],
      );
      expect(
        filterTracks(tracks, 'rating:<3', ratingOf: ratingOf).map((t) => t.id),
        ['0star'],
      );
    });

    test('rating:0 (or rating:<1) finds unrated tracks — same "unrated == '
        '0" convention RatingsPlugin.ratingOf already uses', () {
      expect(
        filterTracks(tracks, 'rating:0', ratingOf: ratingOf).map((t) => t.id),
        ['0star'],
      );
    });

    test('rating: matches nothing (not "matches everything") when the '
        'caller supplies no ratingOf lookup — same as an unknown field, '
        'never a silent no-op filter', () {
      expect(filterTracks(tracks, 'rating:>=1'), isEmpty);
    });

    test('an unparseable rating value matches nothing rather than '
        'throwing', () {
      expect(
        filterTracks(tracks, 'rating:bogus', ratingOf: ratingOf),
        isEmpty,
      );
    });

    test('rating: composes with other terms via AND, same as every other '
        'field', () {
      final mixed = [
        _track(id: 'match', title: 'Bohemian Rhapsody'),
        _track(id: 'wrong-title', title: 'Somebody to Love'),
      ];
      int mixedRatingOf(String id) => id == 'match' ? 5 : 5;
      expect(
        filterTracks(mixed, 'rating:>=4 bohemian', ratingOf: mixedRatingOf)
            .map((t) => t.id),
        ['match'],
      );
    });
  });

  group('filterTracks — bpm field', () {
    final tracks = [
      _track(id: '1', bpm: 120),
      _track(id: '2', bpm: 140),
      _track(id: '3'), // no bpm at all
    ];

    test('exact match', () {
      expect(filterTracks(tracks, 'bpm:120').map((t) => t.id), ['1']);
    });

    test('a track with no bpm data never matches', () {
      expect(filterTracks(tracks, 'bpm:>=0').map((t) => t.id).toSet(),
          {'1', '2'});
    });

    test('inclusive range, same convention as year:', () {
      expect(
        filterTracks(tracks, 'bpm:100..130').map((t) => t.id),
        ['1'],
      );
    });

    test('comparison operators', () {
      expect(filterTracks(tracks, 'bpm:>=130').map((t) => t.id), ['2']);
      expect(filterTracks(tracks, 'bpm:<=130').map((t) => t.id), ['1']);
      expect(filterTracks(tracks, 'bpm:>120').map((t) => t.id), ['2']);
      expect(filterTracks(tracks, 'bpm:<140').map((t) => t.id), ['1']);
    });

    test('an unparseable bpm value matches nothing rather than throwing',
        () {
      expect(filterTracks(tracks, 'bpm:fast'), isEmpty);
    });
  });

  group('filterTracks — format field', () {
    final tracks = [
      _track(id: '1', codec: 'FLAC'),
      _track(id: '2', codec: 'MP3'),
      _track(id: '3'), // no codec at all
    ];

    test('exact, case-insensitive codec match', () {
      expect(filterTracks(tracks, 'format:flac').map((t) => t.id), ['1']);
      expect(filterTracks(tracks, 'format:FLAC').map((t) => t.id), ['1']);
    });

    test('is not a substring match — "format:mp" must not match "MP3"',
        () {
      expect(filterTracks(tracks, 'format:mp'), isEmpty);
    });

    test('a track with no codec data never matches', () {
      expect(filterTracks(tracks, 'format:flac').map((t) => t.id),
          isNot(contains('3')));
    });
  });

  group('filterTracks — favorite field', () {
    final tracks = [_track(id: '1'), _track(id: '2')];
    bool favoriteOf(String id) => id == '1';

    test('favorite:true matches only favorited tracks', () {
      expect(
        filterTracks(tracks, 'favorite:true', favoriteOf: favoriteOf)
            .map((t) => t.id),
        ['1'],
      );
    });

    test('favorite:false matches only non-favorited tracks', () {
      expect(
        filterTracks(tracks, 'favorite:false', favoriteOf: favoriteOf)
            .map((t) => t.id),
        ['2'],
      );
    });

    test('every favorite: term matches nothing when favoriteOf is omitted',
        () {
      expect(filterTracks(tracks, 'favorite:true'), isEmpty);
    });

    test('an unrecognized favorite value matches nothing rather than '
        'throwing', () {
      expect(
        filterTracks(tracks, 'favorite:maybe', favoriteOf: favoriteOf),
        isEmpty,
      );
    });
  });

  group('filterTracks — bitrate field', () {
    final tracks = [
      _track(id: '1', bitrateKbps: 320),
      _track(id: '2', bitrateKbps: 1411),
      _track(id: '3'), // no bitrate at all
    ];

    test('exact match', () {
      expect(filterTracks(tracks, 'bitrate:320').map((t) => t.id), ['1']);
    });

    test('inclusive range, same convention as bpm:/year:', () {
      expect(
        filterTracks(tracks, 'bitrate:200..500').map((t) => t.id),
        ['1'],
      );
    });

    test('comparison operators, e.g. finding lossless-range tracks', () {
      expect(filterTracks(tracks, 'bitrate:>=1000').map((t) => t.id), ['2']);
      expect(filterTracks(tracks, 'bitrate:<1000').map((t) => t.id), ['1']);
    });

    test('a track with no bitrate data never matches', () {
      expect(filterTracks(tracks, 'bitrate:>=0').map((t) => t.id).toSet(),
          {'1', '2'});
    });

    test('an unparseable bitrate value matches nothing rather than '
        'throwing', () {
      expect(filterTracks(tracks, 'bitrate:huge'), isEmpty);
    });
  });

  group('filterTracks — lyrics field', () {
    final tracks = [_track(id: '1'), _track(id: '2')];
    bool hasLyrics(BaseTrack track) => track.id == '1';

    test('lyrics:true matches only tracks with lyrics', () {
      expect(
        filterTracks(tracks, 'lyrics:true', hasLyrics: hasLyrics)
            .map((t) => t.id),
        ['1'],
      );
    });

    test('lyrics:false matches only tracks without lyrics', () {
      expect(
        filterTracks(tracks, 'lyrics:false', hasLyrics: hasLyrics)
            .map((t) => t.id),
        ['2'],
      );
    });

    test('every lyrics: term matches nothing when hasLyrics is omitted',
        () {
      expect(filterTracks(tracks, 'lyrics:true'), isEmpty);
    });
  });

  group('filterTracks — quoted multi-word values', () {
    final tracks = [
      _track(id: 'gnr', title: 'Paradise City', artists: ["Guns N' Roses"],
          album: 'Appetite for Destruction'),
      _track(id: 'greatest-hits', title: 'A', artists: ['Queen'],
          album: 'Greatest Hits'),
      // Deliberately contains "greatest" and "hits" as separate words,
      // not as the contiguous phrase "greatest hits" — proves quoting
      // narrows the match, not just that a substring happens to appear.
      _track(id: 'other-hits', title: 'B', artists: ['Someone'],
          album: 'Greatest Rock Hits'),
      _track(id: 'unrelated', title: 'C', artists: ['Other'], album: 'X'),
    ];

    test('a quoted field value is matched as one phrase, not split into '
        "multiple AND'd terms", () {
      expect(
        filterTracks(tracks, 'artist:"Guns N\' Roses"').map((t) => t.id),
        ['gnr'],
      );
    });

    test('an unquoted multi-word field value still splits into '
        "independent terms — the pre-existing, documented behavior "
        'quoting is meant to fix', () {
      // "greatest hits" without quotes: album:greatest AND the free-text
      // term "hits" — both albums below satisfy that looser condition.
      expect(
        filterTracks(tracks, 'album:greatest hits').map((t) => t.id).toSet(),
        {'greatest-hits', 'other-hits'},
      );
    });

    test('the same value, quoted, matches only the exact phrase', () {
      expect(
        filterTracks(tracks, 'album:"greatest hits"').map((t) => t.id),
        ['greatest-hits'],
      );
    });

    test('a bare quoted phrase (no field prefix) works as one free-text '
        'term too', () {
      expect(
        filterTracks(tracks, '"paradise city"').map((t) => t.id),
        ['gnr'],
      );
    });

    test('a quoted phrase still composes with other terms via AND', () {
      final withGenre = [
        _track(id: 'gnr-rock', title: 'Paradise City',
            artists: ["Guns N' Roses"], genres: ['Rock']),
        _track(id: 'gnr-other', title: 'Something Else',
            artists: ["Guns N' Roses"], genres: ['Rock']),
      ];
      expect(
        filterTracks(withGenre, 'artist:"Guns N\' Roses" paradise')
            .map((t) => t.id),
        ['gnr-rock'],
      );
    });

    test('an unterminated quote extends to the end of the query rather '
        'than throwing', () {
      expect(
        () => filterTracks(tracks, 'artist:"Guns N\' Roses'),
        returnsNormally,
      );
      expect(
        filterTracks(tracks, 'artist:"Guns N\' Roses').map((t) => t.id),
        ['gnr'],
      );
    });

    test('an empty quoted value falls back to a plain free-text term '
        'rather than a field match', () {
      // No text follows "artist:" once the empty quotes are stripped, so
      // this can never match the field pattern — same as any other
      // field-looking prefix with nothing after the colon.
      expect(filterTracks(tracks, 'artist:""'), isEmpty);
    });

    test('multiple quoted terms in one query all resolve independently',
        () {
      expect(
        filterTracks(tracks, 'artist:"Guns N\' Roses" album:"Appetite for '
                'Destruction"')
            .map((t) => t.id),
        ['gnr'],
      );
    });
  });

  group('filterTracks — missing field (item 10, spec §15)', () {
    test('missing:artwork matches a track with no cover art at all', () {
      final tracks = [
        _track(id: '1', coverArt: null),
        _track(id: '2', coverArt: ''),
        _track(id: '3', coverArt: 'file://cover.jpg'),
      ];
      expect(
        filterTracks(tracks, 'missing:artwork').map((t) => t.id).toSet(),
        {'1', '2'},
      );
    });

    test('missing:year matches a track with no release year', () {
      final tracks = [_track(id: '1', year: null), _track(id: '2', year: 1999)];
      expect(filterTracks(tracks, 'missing:year').map((t) => t.id), ['1']);
    });

    test('missing:bpm matches a track that has not been BPM-analyzed', () {
      final tracks = [_track(id: '1', bpm: null), _track(id: '2', bpm: 120)];
      expect(filterTracks(tracks, 'missing:bpm').map((t) => t.id), ['1']);
    });

    test('missing:genre matches a track with no genre tags', () {
      final tracks = [
        _track(id: '1', genres: const []),
        _track(id: '2', genres: const ['Rock']),
      ];
      expect(filterTracks(tracks, 'missing:genre').map((t) => t.id), ['1']);
    });

    test('an unrecognized missing: sub-field matches nothing rather than '
        'throwing', () {
      final tracks = [_track(id: '1', coverArt: null)];
      expect(
        () => filterTracks(tracks, 'missing:bogus'),
        returnsNormally,
      );
      expect(filterTracks(tracks, 'missing:bogus'), isEmpty);
    });

    test('missing: composes with other terms via AND, same as every other '
        'field', () {
      final tracks = [
        _track(id: 'match', title: 'Bohemian Rhapsody', year: null),
        _track(id: 'has-year', title: 'Bohemian Rhapsody', year: 1975),
        _track(id: 'wrong-title', title: 'Somebody to Love', year: null),
      ];
      expect(
        filterTracks(tracks, 'missing:year bohemian').map((t) => t.id),
        ['match'],
      );
    });
  });

  group('filterTracks — duplicate field (item 10, spec §15)', () {
    test('duplicate:track matches tracks sharing title+primary artist', () {
      final tracks = [
        _track(id: '1', title: 'Yesterday', artists: ['The Beatles']),
        _track(id: '2', title: 'yesterday', artists: ['the beatles']),
        _track(id: '3', title: 'Yesterday', artists: ['Someone Else']),
        _track(id: '4', title: 'Unique Song', artists: ['The Beatles']),
      ];
      expect(
        filterTracks(tracks, 'duplicate:track').map((t) => t.id).toSet(),
        {'1', '2'},
      );
    });

    test('a track whose title+artist appears only once never matches '
        'duplicate:track', () {
      final tracks = [
        _track(id: '1', title: 'A', artists: ['X']),
        _track(id: '2', title: 'B', artists: ['Y']),
      ];
      expect(filterTracks(tracks, 'duplicate:track'), isEmpty);
    });

    test('duplicate:album matches tracks sharing album+primary artist', () {
      final tracks = [
        _track(id: '1', album: 'Greatest Hits', artists: ['Queen']),
        _track(id: '2', album: 'greatest hits', artists: ['queen']),
        _track(id: '3', album: 'Greatest Hits', artists: ['Someone Else']),
        _track(id: '4', album: 'Unique Album', artists: ['Queen']),
      ];
      expect(
        filterTracks(tracks, 'duplicate:album').map((t) => t.id).toSet(),
        {'1', '2'},
      );
    });

    test('a track with a blank album never matches duplicate:album, even '
        'if another track also has a blank album', () {
      final tracks = [
        _track(id: '1', album: '', artists: ['X']),
        _track(id: '2', album: '', artists: ['X']),
      ];
      expect(filterTracks(tracks, 'duplicate:album'), isEmpty);
    });

    test('an unrecognized duplicate: sub-field matches nothing rather than '
        'throwing', () {
      final tracks = [
        _track(id: '1', title: 'A', artists: ['X']),
        _track(id: '2', title: 'A', artists: ['X']),
      ];
      expect(
        () => filterTracks(tracks, 'duplicate:bogus'),
        returnsNormally,
      );
      expect(filterTracks(tracks, 'duplicate:bogus'), isEmpty);
    });

    test('duplicate:track composes with other terms via AND, same as every '
        'other field', () {
      final tracks = [
        _track(id: '1', title: 'Yesterday', artists: ['The Beatles'],
            genres: ['Rock']),
        _track(id: '2', title: 'Yesterday', artists: ['The Beatles'],
            genres: ['Pop']),
      ];
      expect(
        filterTracks(tracks, 'duplicate:track rock').map((t) => t.id),
        ['1'],
      );
    });

    test('duplicate:track and duplicate:album are independent groupings',
        () {
      // Same title+artist (duplicate track) but different albums, so
      // neither track should match duplicate:album.
      final tracks = [
        _track(id: '1', title: 'Yesterday', artists: ['The Beatles'],
            album: 'Help!'),
        _track(id: '2', title: 'Yesterday', artists: ['The Beatles'],
            album: '1'),
      ];
      expect(
        filterTracks(tracks, 'duplicate:track').map((t) => t.id).toSet(),
        {'1', '2'},
      );
      expect(filterTracks(tracks, 'duplicate:album'), isEmpty);
    });
  });
}
