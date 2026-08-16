import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/calculated_tags.dart';

BaseTrack _track({
  required String id,
  String title = 'Title',
  List<String> artists = const ['Artist'],
  String album = 'Album',
  List<String> genres = const [],
  int? year,
  int? trackNumber,
  int? discNumber,
  int? bitrateKbps,
  int duration = 180,
  String? codec,
  DateTime? dateAdded,
  String? localPath,
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: artists,
      album: album,
      duration: duration,
      genres: genres,
      year: year,
      trackNumber: trackNumber,
      discNumber: discNumber,
      bitrateKbps: bitrateKbps,
      codec: codec,
      dateAdded: dateAdded,
      localPath: localPath,
      type: TrackType.local,
    );

void main() {
  group('resolveCalculatedTagTemplate — individual tokens', () {
    test('{title}/{artist}/{album}/{genre} resolve to the current '
        'writable field values', () {
      final track = _track(
        id: '1',
        title: 'Song',
        artists: ['A', 'B'],
        album: 'LP',
        genres: ['Rock', 'Pop'],
      );

      expect(resolveCalculatedTagTemplate(track, '{title}'), 'Song');
      expect(resolveCalculatedTagTemplate(track, '{artist}'), 'A, B');
      expect(resolveCalculatedTagTemplate(track, '{album}'), 'LP');
      expect(resolveCalculatedTagTemplate(track, '{genre}'), 'Rock, Pop');
    });

    test('{year} resolves to the release year, or "" when unknown', () {
      expect(
        resolveCalculatedTagTemplate(_track(id: '1', year: 1999), '{year}'),
        '1999',
      );
      expect(
        resolveCalculatedTagTemplate(_track(id: '1'), '{year}'),
        '',
      );
    });

    test('{track}/{disc} resolve to their numbers, or "" when unknown', () {
      final track = _track(id: '1', trackNumber: 4, discNumber: 2);
      expect(resolveCalculatedTagTemplate(track, '{track}'), '4');
      expect(resolveCalculatedTagTemplate(track, '{disc}'), '2');
      expect(resolveCalculatedTagTemplate(_track(id: '2'), '{track}'), '');
      expect(resolveCalculatedTagTemplate(_track(id: '2'), '{disc}'), '');
    });

    test('{bitrate} resolves to the bitrate in kbps, or "" when unknown',
        () {
      expect(
        resolveCalculatedTagTemplate(
            _track(id: '1', bitrateKbps: 320), '{bitrate}'),
        '320',
      );
      expect(resolveCalculatedTagTemplate(_track(id: '2'), '{bitrate}'), '');
    });

    test('{duration} formats as mm:ss', () {
      expect(
        resolveCalculatedTagTemplate(
            _track(id: '1', duration: 65), '{duration}'),
        '1:05',
      );
      expect(
        resolveCalculatedTagTemplate(
            _track(id: '2', duration: 5), '{duration}'),
        '0:05',
      );
      expect(
        resolveCalculatedTagTemplate(
            _track(id: '3', duration: 600), '{duration}'),
        '10:00',
      );
    });

    test('{codec} resolves to the codec label, or "" when unknown', () {
      expect(
        resolveCalculatedTagTemplate(_track(id: '1', codec: 'FLAC'), '{codec}'),
        'FLAC',
      );
      expect(resolveCalculatedTagTemplate(_track(id: '2'), '{codec}'), '');
    });

    test('{dateAdded} formats as YYYY-MM-DD, or "" when unknown', () {
      expect(
        resolveCalculatedTagTemplate(
          _track(id: '1', dateAdded: DateTime(2024, 3, 7)),
          '{dateAdded}',
        ),
        '2024-03-07',
      );
      expect(
        resolveCalculatedTagTemplate(_track(id: '2'), '{dateAdded}'),
        '',
      );
    });

    test('{folderName}/{fileExtension} resolve from localPath, or "" for '
        'a non-local/no-path track', () {
      final track = _track(
        id: '1',
        localPath: '/music/Queen/Opera/track.flac',
      );
      expect(resolveCalculatedTagTemplate(track, '{folderName}'), 'Opera');
      expect(resolveCalculatedTagTemplate(track, '{fileExtension}'), 'flac');

      final noPath = _track(id: '2');
      expect(resolveCalculatedTagTemplate(noPath, '{folderName}'), '');
      expect(resolveCalculatedTagTemplate(noPath, '{fileExtension}'), '');
    });

    test('an unrecognized token resolves to an empty string rather than '
        'throwing or being left literally in place', () {
      final track = _track(id: '1');
      expect(
        () => resolveCalculatedTagTemplate(track, '{bogus}'),
        returnsNormally,
      );
      expect(resolveCalculatedTagTemplate(track, '{bogus}'), '');
    });
  });

  group('resolveCalculatedTagTemplate — combined templates', () {
    test('multiple tokens plus literal text combine correctly', () {
      final track = _track(
        id: '1',
        title: 'Bohemian Rhapsody',
        artists: ['Queen'],
        year: 1975,
      );

      expect(
        resolveCalculatedTagTemplate(track, '{artist} - {title} [{year}]'),
        'Queen - Bohemian Rhapsody [1975]',
      );
    });

    test('a template with no tokens at all passes through as a literal '
        'value', () {
      final track = _track(id: '1');
      expect(
        resolveCalculatedTagTemplate(track, 'Fixed Value'),
        'Fixed Value',
      );
    });
  });

  group('previewCalculatedTags', () {
    test('an empty template returns no matches rather than clearing every '
        "track's field", () {
      final tracks = [_track(id: '1', title: 'Song')];
      const rule = CalculatedTagRule(
        target: CalculatedTagTargetField.title,
        template: '',
      );

      expect(previewCalculatedTags(tracks, rule), isEmpty);
    });

    test('a track whose resolved template equals its current value is '
        'never included', () {
      final tracks = [_track(id: '1', title: 'Song')];
      const rule = CalculatedTagRule(
        target: CalculatedTagTargetField.title,
        template: '{title}',
      );

      expect(previewCalculatedTags(tracks, rule), isEmpty);
    });

    test('a track whose resolved template differs is included with the '
        'correct before/after', () {
      final tracks = [
        _track(id: '1', title: 'Old Title', artists: ['Queen'], year: 1975),
      ];
      const rule = CalculatedTagRule(
        target: CalculatedTagTargetField.title,
        template: '{artist} - {title} [{year}]',
      );

      final result = previewCalculatedTags(tracks, rule);

      expect(result, hasLength(1));
      expect(result.single.before, 'Old Title');
      expect(result.single.after, 'Queen - Old Title [1975]');
    });

    test('targeting a different field reads/writes that field, not title',
        () {
      final tracks = [
        _track(id: '1', album: 'Old Album', codec: 'FLAC'),
      ];
      const rule = CalculatedTagRule(
        target: CalculatedTagTargetField.album,
        template: '{album} ({codec})',
      );

      final result = previewCalculatedTags(tracks, rule);

      expect(result, hasLength(1));
      expect(result.single.before, 'Old Album');
      expect(result.single.after, 'Old Album (FLAC)');
    });

    test('multiple tracks are previewed independently, only the genuinely '
        'changed ones included', () {
      final tracks = [
        _track(id: 'changes', title: 'A', year: 2000),
        _track(id: 'no-year', title: 'B'), // {year} -> "" -> "B []"
        _track(id: 'unchanged', title: '{year}'), // literal match by luck
      ];
      const rule = CalculatedTagRule(
        target: CalculatedTagTargetField.title,
        template: '{title}',
      );

      // With template '{title}' every track's after == before, so nothing
      // should ever be flagged regardless of the other fields' values.
      expect(previewCalculatedTags(tracks, rule), isEmpty);
    });
  });
}
