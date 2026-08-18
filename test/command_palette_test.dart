import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/command_palette.dart';
import 'package:omnis_plugin_api/playlist.dart';

BaseTrack _track(String id, {String title = 'Title', String artist = 'Artist'}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: [artist],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

Playlist _playlist(String id, String name) => Playlist(
      id: id,
      name: name,
      trackIds: const [],
      createdAt: DateTime(2025),
    );

void main() {
  test('paletteCommands is pinned to the 11 spec-named commands this '
      'pass actually wires up — a change here should be deliberate, not '
      'silent drift', () {
    expect(
      paletteCommands.map((c) => c.id).toList(),
      [
        'play',
        'pause',
        'next',
        'previous',
        'shuffle',
        'open_settings',
        'enable_driving_mode',
        'open_lyrics',
        'change_theme',
        'customize_home',
        'scan_library',
      ],
    );
  });

  group('matchCommands', () {
    test('an empty query returns every command in its fixed order', () {
      expect(matchCommands(''), paletteCommands);
    });

    test('a whitespace-only query is treated the same as empty', () {
      expect(matchCommands('   '), paletteCommands);
    });

    test('matches case-insensitively against the title', () {
      final results = matchCommands('PLAY');
      expect(results.map((c) => c.id), containsAll(['play']));
    });

    test('matches against a keyword, not just the title', () {
      final results = matchCommands('preferences');
      expect(results.single.id, 'open_settings');
    });

    test('a query matching nothing returns an empty list', () {
      expect(matchCommands('xyzzy'), isEmpty);
    });

    test('a title starting with the query ranks above one that merely '
        'contains it', () {
      const commands = [
        PaletteCommand(id: 'contains', title: 'Something play related'),
        PaletteCommand(id: 'starts', title: 'Play something'),
      ];
      final results = matchCommands('play', commands);
      expect(results.first.id, 'starts');
    });

    test('a custom command list is used instead of the default when '
        'supplied', () {
      const custom = [PaletteCommand(id: 'custom', title: 'Custom Command')];
      expect(matchCommands('custom', custom).single.id, 'custom');
      expect(matchCommands('play', custom), isEmpty);
    });
  });

  group('searchEverywhere', () {
    test('an empty query returns every command and nothing else, matching '
        'matchCommands\' own empty-query behavior exactly', () {
      final results = searchEverywhere(
        query: '',
        tracks: [_track('t1', title: 'Blue Skies')],
        playlists: [_playlist('p1', 'Road Trip')],
        moods: ['Chill'],
      );

      expect(results, hasLength(paletteCommands.length));
      expect(results.every((r) => r.kind == GlobalSearchResultKind.command),
          isTrue);
    });

    test('a non-empty query matches a track by title, case-insensitively',
        () {
      final results = searchEverywhere(
        query: 'blue',
        tracks: [_track('t1', title: 'Blue Skies'), _track('t2', title: 'Red Sun')],
      );

      final trackResults =
          results.where((r) => r.kind == GlobalSearchResultKind.track);
      expect(trackResults.single.actionId, 't1');
      expect(trackResults.single.title, 'Blue Skies');
    });

    test('a track also matches by artist name', () {
      final results = searchEverywhere(
        query: 'wonder',
        tracks: [_track('t1', title: 'Song', artist: 'Stevie Wonder')],
      );

      expect(
        results
            .where((r) => r.kind == GlobalSearchResultKind.track)
            .single
            .actionId,
        't1',
      );
    });

    test('matches a playlist by name', () {
      final results = searchEverywhere(
        query: 'road',
        playlists: [_playlist('p1', 'Road Trip'), _playlist('p2', 'Study')],
      );

      final playlistResults =
          results.where((r) => r.kind == GlobalSearchResultKind.playlist);
      expect(playlistResults.single.actionId, 'p1');
      expect(playlistResults.single.title, 'Road Trip');
    });

    test('matches a mood/preset by name', () {
      final results = searchEverywhere(
        query: 'chi',
        moods: ['Chill', 'Focus', 'Workout'],
      );

      final moodResults =
          results.where((r) => r.kind == GlobalSearchResultKind.mood);
      expect(moodResults.single.actionId, 'Chill');
    });

    test('results are capped at limitPerCategory per kind', () {
      final tracks = List.generate(10, (i) => _track('t$i', title: 'Match $i'));

      final results = searchEverywhere(
        query: 'match',
        tracks: tracks,
        limitPerCategory: 3,
      );

      expect(
        results.where((r) => r.kind == GlobalSearchResultKind.track),
        hasLength(3),
      );
    });

    test('a query matching nothing in any category returns an empty list',
        () {
      final results = searchEverywhere(
        query: 'xyzzy',
        tracks: [_track('t1', title: 'Blue Skies')],
        playlists: [_playlist('p1', 'Road Trip')],
        moods: ['Chill'],
      );

      expect(results, isEmpty);
    });

    test('commands, tracks, playlists, and moods can all match the same '
        'query at once, each kept in its own kind group', () {
      final results = searchEverywhere(
        query: 'play',
        commands: const [
          PaletteCommand(id: 'play', title: 'Play'),
        ],
        tracks: [_track('t1', title: 'Playlist Anthem')],
        playlists: [_playlist('p1', 'My Playlist')],
        moods: const ['Playtime'],
      );

      expect(
        results.map((r) => r.kind).toSet(),
        {
          GlobalSearchResultKind.command,
          GlobalSearchResultKind.track,
          GlobalSearchResultKind.playlist,
          GlobalSearchResultKind.mood,
        },
      );
    });
  });
}
