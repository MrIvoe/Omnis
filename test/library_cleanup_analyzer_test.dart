import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_cleanup_analyzer.dart';

void main() {
  BaseTrack track({
    required String id,
    String title = 'Title',
    String artist = 'Artist',
    String album = 'Album',
    int? year,
    int? trackNumber,
    String? genre,
    String? coverArt,
    String? codec,
    String? localPath,
    TrackType type = TrackType.local,
  }) =>
      BaseTrack(
        id: id,
        title: title,
        artists: [artist],
        album: album,
        duration: 180,
        year: year,
        trackNumber: trackNumber,
        genres: genre == null ? const [] : [genre],
        coverArt: coverArt,
        codec: codec,
        localPath: localPath,
        type: type,
      );

  group('missing artwork', () {
    test('flags tracks with a null or blank coverArt', () {
      final tracks = [
        track(id: '1', coverArt: null),
        track(id: '2', coverArt: ''),
        track(id: '3', coverArt: '  '),
        track(id: '4', coverArt: '/art/cover.jpg'),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.missingArtwork.map((t) => t.id).toSet(), {'1', '2', '3'});
    });
  });

  group('inconsistent artists', () {
    test('flags tracks in the same album whose primary artist spelling '
        'differs', () {
      final tracks = [
        track(id: '1', album: 'Greatest Hits', artist: 'The Beatles'),
        track(id: '2', album: 'greatest  hits', artist: 'Beatles'),
        track(id: '3', album: 'Greatest Hits', artist: 'The Beatles'),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.inconsistentArtists.map((t) => t.id).toSet(),
          {'1', '2', '3'});
    });

    test('an album with one consistent artist spelling is never flagged',
        () {
      final tracks = [
        track(id: '1', album: 'Album', artist: 'Ava'),
        track(id: '2', album: 'Album', artist: 'Ava'),
      ];

      expect(LibraryCleanupAnalyzer.analyze(tracks).inconsistentArtists,
          isEmpty);
    });

    test('a blank album is never grouped/flagged', () {
      final tracks = [
        track(id: '1', album: '', artist: 'Ava'),
        track(id: '2', album: '', artist: 'Ben'),
      ];

      expect(LibraryCleanupAnalyzer.analyze(tracks).inconsistentArtists,
          isEmpty);
    });
  });

  group('duplicate tracks', () {
    test('reuses the same title+primary-artist matching as '
        'findDuplicateTracks, and the count sums every flagged track',
        () {
      final tracks = [
        track(id: '1', title: 'Sunrise', artist: 'Ava'),
        track(id: '2', title: '  sunrise ', artist: 'ava'),
        track(id: '3', title: 'Moonlight', artist: 'Ava'),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.duplicateTrackGroups, hasLength(1));
      expect(report.duplicateTrackGroups.first.map((t) => t.id),
          containsAll(['1', '2']));
      expect(report.duplicateTracksCount, 2);
    });
  });

  group('albums missing year', () {
    test('flags an album only when every one of its tracks has no year',
        () {
      final tracks = [
        track(id: '1', album: 'No Year Album', year: null),
        track(id: '2', album: 'No Year Album', year: null),
        track(id: '3', album: 'Dated Album', year: null),
        track(id: '4', album: 'Dated Album', year: 1999),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.albumsMissingYear, ['No Year Album']);
    });
  });

  group('malformed track numbers', () {
    test('flags a null or non-positive track number, only within a real '
        'album', () {
      final tracks = [
        track(id: '1', album: 'Album', trackNumber: null),
        track(id: '2', album: 'Album', trackNumber: 0),
        track(id: '3', album: 'Album', trackNumber: -1),
        track(id: '4', album: 'Album', trackNumber: 3),
        track(id: '5', album: '', trackNumber: null),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.malformedTrackNumbers.map((t) => t.id).toSet(),
          {'1', '2', '3'});
    });
  });

  group('inconsistent genres', () {
    test('flags tracks in the same album whose primary genre differs', () {
      final tracks = [
        track(id: '1', album: 'Album', genre: 'Rock'),
        track(id: '2', album: 'Album', genre: 'Pop'),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(
          report.inconsistentGenres.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('a track with no genre at all is never flagged even inside an '
        'otherwise-inconsistent album', () {
      final tracks = [
        track(id: '1', album: 'Album', genre: 'Rock'),
        track(id: '2', album: 'Album', genre: 'Pop'),
        track(id: '3', album: 'Album', genre: null),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.inconsistentGenres.map((t) => t.id), isNot(contains('3')));
    });
  });

  group('duplicate albums', () {
    test('groups the same album+artist appearing under different '
        'spelling/casing/whitespace', () {
      final tracks = [
        track(id: '1', album: 'Abbey Road', artist: 'The Beatles'),
        track(id: '2', album: '  abbey  road', artist: 'the beatles'),
      ];

      final report = LibraryCleanupAnalyzer.analyze(tracks);

      expect(report.duplicateAlbumGroups, hasLength(1));
      expect(report.duplicateAlbumGroups.first.map((t) => t.id),
          containsAll(['1', '2']));
      expect(report.duplicateAlbumsCount, 1);
    });

    test('two different artists\' same-named album are never merged', () {
      final tracks = [
        track(id: '1', album: 'Greatest Hits', artist: 'Artist A'),
        track(id: '2', album: 'Greatest Hits', artist: 'Artist B'),
      ];

      expect(
          LibraryCleanupAnalyzer.analyze(tracks).duplicateAlbumGroups,
          isEmpty);
    });

    test('a single spelling of an album is never flagged as its own '
        'duplicate', () {
      final tracks = [
        track(id: '1', album: 'Album', artist: 'Ava'),
        track(id: '2', album: 'Album', artist: 'Ava'),
      ];

      expect(
          LibraryCleanupAnalyzer.analyze(tracks).duplicateAlbumGroups,
          isEmpty);
    });
  });

  group('corrupt files', () {
    test('flags a local track with a fully-parsed extension but no '
        'codec', () {
      final tracks = [
        track(id: '1', localPath: '/music/song.flac', codec: null),
      ];

      expect(LibraryCleanupAnalyzer.analyze(tracks).corruptFiles,
          hasLength(1));
    });

    test('a successfully-parsed track (real codec) is never flagged', () {
      final tracks = [
        track(id: '1', localPath: '/music/song.flac', codec: 'FLAC'),
      ];

      expect(
          LibraryCleanupAnalyzer.analyze(tracks).corruptFiles, isEmpty);
    });

    test('a bare .aac file (deliberately unparsed) is never flagged as '
        'corrupt', () {
      final tracks = [
        track(id: '1', localPath: '/music/song.aac', codec: null),
      ];

      expect(
          LibraryCleanupAnalyzer.analyze(tracks).corruptFiles, isEmpty);
    });

    test('a non-local track with no codec is never flagged', () {
      final tracks = [
        track(id: '1', codec: null, type: TrackType.spotify),
      ];

      expect(
          LibraryCleanupAnalyzer.analyze(tracks).corruptFiles, isEmpty);
    });
  });

  group('LibraryCleanupReport.categories / isClean', () {
    test('an empty library reports every category at zero and isClean '
        'true', () {
      final report = LibraryCleanupAnalyzer.analyze(const []);

      expect(report.categories, hasLength(9));
      expect(report.categories.every((c) => c.count == 0), isTrue);
      expect(report.isClean, isTrue);
    });

    test('any single non-zero category makes isClean false', () {
      final tracks = [track(id: '1', coverArt: null)];

      expect(LibraryCleanupAnalyzer.analyze(tracks).isClean, isFalse);
    });

    test('missingFiles defaults to empty on a fresh analyze() — it is '
        'never computed by the synchronous pass', () {
      final tracks = [track(id: '1', localPath: '/does/not/exist.mp3')];
      expect(LibraryCleanupAnalyzer.analyze(tracks).missingFiles, isEmpty);
    });

    test('copyWithMissingFiles updates only that field, leaving every '
        'other category untouched', () {
      final tracks = [track(id: '1', coverArt: null)];
      final base = LibraryCleanupAnalyzer.analyze(tracks);
      final missing = [track(id: '2', localPath: '/gone.mp3')];

      final updated = base.copyWithMissingFiles(missing);

      expect(updated.missingFiles, missing);
      expect(updated.missingArtwork, base.missingArtwork);
      expect(updated.categories, hasLength(9));
    });
  });

  group('findMissingFiles (item 17)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('omnis_cleanup_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a track whose file genuinely exists is not flagged', () async {
      final file = File('${tempDir.path}/present.mp3');
      await file.writeAsBytes([0]);
      final tracks = [track(id: '1', localPath: file.path)];

      final missing = await LibraryCleanupAnalyzer.findMissingFiles(tracks);

      expect(missing, isEmpty);
    });

    test('a track whose file is gone is flagged', () async {
      final tracks = [
        track(id: '1', localPath: '${tempDir.path}/never_existed.mp3'),
      ];

      final missing = await LibraryCleanupAnalyzer.findMissingFiles(tracks);

      expect(missing.map((t) => t.id), ['1']);
    });

    test('a real create-then-delete round trip is genuinely detected, not '
        'just a made-up path', () async {
      final file = File('${tempDir.path}/temporary.mp3');
      await file.writeAsBytes([0]);
      final tracks = [track(id: '1', localPath: file.path)];

      expect(await LibraryCleanupAnalyzer.findMissingFiles(tracks), isEmpty);

      await file.delete();

      final missing = await LibraryCleanupAnalyzer.findMissingFiles(tracks);
      expect(missing.map((t) => t.id), ['1']);
    });

    test('a non-local track is never checked, even with a localPath set',
        () async {
      final tracks = [
        track(
          id: '1',
          localPath: '${tempDir.path}/never_existed.mp3',
          type: TrackType.youtube,
        ),
      ];

      expect(await LibraryCleanupAnalyzer.findMissingFiles(tracks), isEmpty);
    });

    test('a local track with no localPath at all is never checked',
        () async {
      final tracks = [track(id: '1')];
      expect(await LibraryCleanupAnalyzer.findMissingFiles(tracks), isEmpty);
    });

    test('present and missing tracks are correctly distinguished within '
        'the same call', () async {
      final present = File('${tempDir.path}/present.mp3');
      await present.writeAsBytes([0]);
      final tracks = [
        track(id: 'present', localPath: present.path),
        track(id: 'missing', localPath: '${tempDir.path}/gone.mp3'),
      ];

      final missing = await LibraryCleanupAnalyzer.findMissingFiles(tracks);
      expect(missing.map((t) => t.id), ['missing']);
    });

    test('an empty track list returns empty without touching the '
        'filesystem', () async {
      expect(await LibraryCleanupAnalyzer.findMissingFiles(const []), isEmpty);
    });
  });
}
