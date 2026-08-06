import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugins/queue_preset_plugin.dart';

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
}
