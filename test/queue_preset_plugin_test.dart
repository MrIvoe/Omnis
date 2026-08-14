import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/plugin_api/play_record.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/queue_preset_plugin.dart';

/// No-op stand-in for AudioEngine — "Forgotten Favorites" never touches
/// playback, only [IPlayHistoryProvider].
class _FakeEngine implements AudioEngine {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// A controllable [IPlayHistoryProvider] double — real `ScrobblePlugin`
/// lives in the separate `Omnis-Plugins` repo, so this fake stands in
/// for "whatever real history provider is registered," matching how
/// `QueuePresetPlugin` actually reaches it in production (by interface,
/// via `context.services`, never by concrete type).
class _FakeHistoryProvider implements IPlayHistoryProvider {
  List<MapEntry<String, int>> mostPlayed = const [];
  List<PlayRecord> recent = const [];

  @override
  List<MapEntry<String, int>> mostPlayedIds({int limit = 25}) =>
      mostPlayed.take(limit).toList();

  @override
  List<PlayRecord> recentlyPlayed({int limit = 25}) =>
      recent.take(limit).toList();

  @override
  int playCountFor(String trackId) =>
      mostPlayed.firstWhere((e) => e.key == trackId, orElse: () => const MapEntry('', 0)).value;
}

PlayRecord _playedRecord(String trackId) => PlayRecord(
      trackId: trackId,
      title: 'T$trackId',
      artist: 'Artist',
      playedAt: DateTime(2026, 1, 1),
    );

void main() {
  BaseTrack track({
    required String id,
    List<String> genres = const [],
    double? bpm,
  }) =>
      BaseTrack(
        id: id,
        title: 'T$id',
        artists: const ['Artist'],
        album: 'Album',
        duration: 180,
        type: TrackType.local,
        genres: genres,
        bpm: bpm,
      );

  test('matchesPreset matches workout by high BPM even with no genre data', () {
    final plugin = QueuePresetPlugin();
    expect(plugin.matchesPreset(track(id: '1', bpm: 140), 'Workout'), isTrue);
    expect(plugin.matchesPreset(track(id: '2', bpm: 60), 'Workout'), isFalse);
  });

  test('matchesPreset matches sleep by genre keyword', () {
    final plugin = QueuePresetPlugin();
    expect(
      plugin.matchesPreset(track(id: '1', genres: ['Ambient']), 'Sleep'),
      isTrue,
    );
    expect(
      plugin.matchesPreset(track(id: '2', genres: ['Death Metal']), 'Sleep'),
      isFalse,
    );
  });

  test('an unknown preset name matches nothing', () {
    final plugin = QueuePresetPlugin();
    expect(
      plugin.matchesPreset(track(id: '1', bpm: 140, genres: ['edm']), 'Party'),
      isFalse,
    );
  });

  test('buildQueue prefers matching tracks when some exist', () {
    final plugin = QueuePresetPlugin();
    final tracks = [
      track(id: 'match', genres: ['Ambient']),
      track(id: 'nomatch', genres: ['Death Metal']),
    ];

    final queue = plugin.buildQueue(tracks, 'Sleep', random: Random(1));

    expect(queue.map((t) => t.id), ['match']);
  });

  test('buildQueue falls back to the whole library when nothing matches — '
      'never leaves the caller with an empty queue', () {
    final plugin = QueuePresetPlugin();
    final tracks = [
      track(id: '1', genres: ['Death Metal']),
      track(id: '2', genres: ['Polka']),
    ];

    final queue = plugin.buildQueue(tracks, 'Sleep', random: Random(1));

    expect(queue, hasLength(2));
  });

  test('buildQueue respects limit', () {
    final plugin = QueuePresetPlugin();
    final tracks = List.generate(10, (i) => track(id: '$i', bpm: 140));

    final queue = plugin.buildQueue(tracks, 'Workout', limit: 3, random: Random(1));

    expect(queue, hasLength(3));
  });

  group('Forgotten Favorites', () {
    test('"Forgotten Favorites" is a supported query', () {
      final plugin = QueuePresetPlugin();
      expect(plugin.supportedQueries, contains('Forgotten Favorites'));
    });

    test('returns empty (not the whole-library shuffle fallback) when the '
        'plugin has no context at all', () {
      final plugin = QueuePresetPlugin();
      final tracks = [track(id: '1')];

      final queue = plugin.buildQueueFor(tracks, 'Forgotten Favorites');

      expect(queue, isEmpty);
    });

    test('returns empty when no IPlayHistoryProvider is registered', () {
      final plugin = QueuePresetPlugin()
        ..attach(OmnisPluginContext(
          audioEngine: _FakeEngine(),
          services: ServiceRegistry(),
          events: EventBus(),
        ));
      final tracks = [track(id: '1')];

      final queue = plugin.buildQueueFor(tracks, 'Forgotten Favorites');

      expect(queue, isEmpty);
    });

    test('returns empty when there is history but nothing has ever been '
        'played (no genuine "used to love this" claim to make)', () {
      final services = ServiceRegistry();
      services.register(IPlayHistoryProvider, _FakeHistoryProvider());
      final plugin = QueuePresetPlugin()
        ..attach(OmnisPluginContext(
          audioEngine: _FakeEngine(),
          services: services,
          events: EventBus(),
        ));
      final tracks = [track(id: '1')];

      final queue = plugin.buildQueueFor(tracks, 'Forgotten Favorites');

      expect(queue, isEmpty);
    });

    test('a most-played track absent from the recent window is a real '
        'forgotten favorite', () {
      final services = ServiceRegistry();
      final history = _FakeHistoryProvider()
        ..mostPlayed = [
          const MapEntry('old-favorite', 50),
          const MapEntry('current-favorite', 40),
        ]
        ..recent = [_playedRecord('current-favorite')];
      services.register(IPlayHistoryProvider, history);
      final plugin = QueuePresetPlugin()
        ..attach(OmnisPluginContext(
          audioEngine: _FakeEngine(),
          services: services,
          events: EventBus(),
        ));
      final tracks = [
        track(id: 'old-favorite'),
        track(id: 'current-favorite'),
        track(id: 'never-played'),
      ];

      final queue = plugin.buildQueueFor(tracks, 'Forgotten Favorites');

      expect(queue.map((t) => t.id), ['old-favorite']);
    });

    test('a most-played track missing from the current library (deleted/'
        'moved) is skipped rather than producing a broken entry', () {
      final services = ServiceRegistry();
      final history = _FakeHistoryProvider()
        ..mostPlayed = [const MapEntry('gone-track', 99)]
        ..recent = const [];
      services.register(IPlayHistoryProvider, history);
      final plugin = QueuePresetPlugin()
        ..attach(OmnisPluginContext(
          audioEngine: _FakeEngine(),
          services: services,
          events: EventBus(),
        ));
      final tracks = [track(id: 'unrelated')];

      final queue = plugin.buildQueueFor(tracks, 'Forgotten Favorites');

      expect(queue, isEmpty);
    });

    test('query matching is case-insensitive, same as every other preset '
        'name here', () {
      final services = ServiceRegistry();
      final history = _FakeHistoryProvider()
        ..mostPlayed = [const MapEntry('old-favorite', 10)]
        ..recent = const [];
      services.register(IPlayHistoryProvider, history);
      final plugin = QueuePresetPlugin()
        ..attach(OmnisPluginContext(
          audioEngine: _FakeEngine(),
          services: services,
          events: EventBus(),
        ));
      final tracks = [track(id: 'old-favorite')];

      final queue = plugin.buildQueueFor(tracks, 'forgotten favorites');

      expect(queue.map((t) => t.id), ['old-favorite']);
    });
  });
}
