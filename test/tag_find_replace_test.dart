import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/tag_find_replace.dart';

BaseTrack _track({
  required String id,
  String title = 'Title',
  List<String> artists = const ['Artist'],
  String album = 'Album',
  List<String> genres = const [],
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: artists,
      album: album,
      duration: 180,
      genres: genres,
      type: TrackType.local,
    );

void main() {
  group('previewFindReplace — literal mode', () {
    test('replaces a literal substring in the requested field', () {
      final tracks = [_track(id: '1', title: 'Live at Wembley (Remaster)')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: ' (Remaster)',
        replace: '',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result, hasLength(1));
      expect(result.single.before, 'Live at Wembley (Remaster)');
      expect(result.single.after, 'Live at Wembley');
    });

    test('a track whose field does not contain the pattern is never '
        'included', () {
      final tracks = [_track(id: '1', title: 'Untouched')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'Remaster',
        replace: '',
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });

    test('literal mode is case-insensitive by default', () {
      final tracks = [_track(id: '1', title: 'REMASTERED Track')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'remastered',
        replace: 'Remaster',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.single.after, 'Remaster Track');
    });

    test('caseSensitive: true only matches exact case', () {
      final tracks = [_track(id: '1', title: 'REMASTERED Track')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'remastered',
        replace: 'X',
        caseSensitive: true,
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });

    test('literal mode treats regex-special characters as plain text',
        () {
      final tracks = [_track(id: '1', title: 'Track (Live)')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: '(Live)',
        replace: '',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.single.after, 'Track ');
    });
  });

  group('previewFindReplace — regex mode', () {
    test('matches using real regex syntax', () {
      final tracks = [_track(id: '1', title: 'Track 001')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: r'\s\d+$',
        replace: '',
        useRegex: true,
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.single.after, 'Track');
    });

    test('replacement text is inserted literally, not templated with '
        r'$1-style capture-group references', () {
      final tracks = [_track(id: '1', title: 'Track 001')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: r'(\d+)',
        replace: r'[$1]',
        useRegex: true,
      );

      final result = previewFindReplace(tracks, rule);

      // The literal text "[$1]" is what's inserted -- not "[001]".
      expect(result.single.after, r'Track [$1]');
    });

    test('an invalid regex pattern returns no matches rather than '
        'throwing', () {
      final tracks = [_track(id: '1', title: 'Track')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: '(unclosed',
        replace: '',
        useRegex: true,
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });
  });

  group('previewFindReplace — field selection', () {
    test('artist operates on the joined multi-artist string', () {
      final tracks = [
        _track(id: '1', artists: const ['Ava', 'Bo (feat.)'])
      ];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.artist},
        find: ' (feat.)',
        replace: '',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.single.before, 'Ava, Bo (feat.)');
      expect(result.single.after, 'Ava, Bo');
    });

    test('genre operates on the joined multi-genre string', () {
      final tracks = [
        _track(id: '1', genres: const ['Rock', 'Hard Rock'])
      ];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.genre},
        find: 'Rock',
        replace: 'Metal',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.single.after, 'Metal, Hard Metal');
    });

    test('only the requested fields are checked, even if other fields '
        'would also match', () {
      final tracks = [
        _track(id: '1', title: 'Live Album', album: 'Live at Wembley')
      ];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'Live',
        replace: 'Recorded',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result, hasLength(1));
      expect(result.single.field, TagFindReplaceField.title);
    });

    test('multiple selected fields each produce their own match entry',
        () {
      final tracks = [
        _track(id: '1', title: 'Live', album: 'Live at Wembley')
      ];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title, TagFindReplaceField.album},
        find: 'Live',
        replace: 'Recorded',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.map((m) => m.field).toSet(),
          {TagFindReplaceField.title, TagFindReplaceField.album});
    });

    test('an empty field on a track (e.g. blank genre) is never checked',
        () {
      final tracks = [_track(id: '1', genres: const [])];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.genre},
        find: 'Rock',
        replace: 'Metal',
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });
  });

  group('previewFindReplace — guard rails', () {
    test('an empty find pattern returns no matches, not "match '
        'everything"', () {
      final tracks = [_track(id: '1', title: 'Anything')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: '',
        replace: 'X',
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });

    test('an empty fields set returns no matches', () {
      final tracks = [_track(id: '1', title: 'Remaster')];
      const rule = TagFindReplaceRule(
        fields: {},
        find: 'Remaster',
        replace: '',
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });

    test('an empty track list returns no matches', () {
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'x',
        replace: 'y',
      );

      expect(previewFindReplace(const [], rule), isEmpty);
    });

    test('a replacement identical to the matched text produces no '
        'match entry — nothing genuinely changed', () {
      final tracks = [_track(id: '1', title: 'Same')];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'Same',
        replace: 'Same',
      );

      expect(previewFindReplace(tracks, rule), isEmpty);
    });

    test('multiple tracks are each evaluated independently', () {
      final tracks = [
        _track(id: '1', title: 'Remaster A'),
        _track(id: '2', title: 'Untouched'),
        _track(id: '3', title: 'Remaster B'),
      ];
      const rule = TagFindReplaceRule(
        fields: {TagFindReplaceField.title},
        find: 'Remaster ',
        replace: '',
      );

      final result = previewFindReplace(tracks, rule);

      expect(result.map((m) => m.track.id).toSet(), {'1', '3'});
    });
  });
}
