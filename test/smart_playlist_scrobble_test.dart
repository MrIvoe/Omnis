import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugins/lyrics_plugin.dart';
import 'package:omnis_plugins/scrobble_plugin.dart';
import 'package:omnis_plugins/smart_playlist_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ScrobblePlugin now persists via its own PluginStorage (real
    // SharedPreferences.getInstance(), not the null-safe "_prefs?."
    // AppSettings used before) — every plugin-storage-touching test file
    // needs this, per docs/PLUGIN_GUIDE.md's testing section.
    SharedPreferences.setMockInitialValues({});
  });

  test('smart playlist builds a mood-based queue', () {
    final plugin = SmartPlaylistPlugin();
    final tracks = [
      BaseTrack(id: '1', title: 'A', artists: ['X'], album: 'Album', duration: 120, type: TrackType.local, mood: 'Chill'),
      BaseTrack(id: '2', title: 'B', artists: ['Y'], album: 'Album', duration: 120, type: TrackType.local, mood: 'Energetic'),
    ];

    final filtered = plugin.buildQueue(tracks, mood: 'Chill');

    expect(filtered, hasLength(1));
    expect(filtered.first.title, 'A');
  });

  test('scrobble plugin records recent tracks', () async {
    final plugin = ScrobblePlugin();
    final track = BaseTrack(id: '3', title: 'Recent', artists: ['Z'], album: 'Album', duration: 120, type: TrackType.local);

    await plugin.onTrackStart(track);

    expect(plugin.history.last, contains('Recent'));
  });

  test('lyrics plugin resolves the active lyric line by playback position', () {
    final plugin = LyricsPlugin();
    plugin.setTimedLyric('4', [
      const LyricLine(timestamp: Duration.zero, text: 'Hello'),
      const LyricLine(timestamp: Duration(seconds: 3), text: 'World'),
    ]);

    final track = BaseTrack(id: '4', title: 'Synced', artists: ['A'], album: 'Album', duration: 120, type: TrackType.local);

    expect(plugin.currentLyricFor(track, Duration.zero), 'Hello');
    expect(plugin.currentLyricFor(track, const Duration(seconds: 4)), 'World');
  });
}
