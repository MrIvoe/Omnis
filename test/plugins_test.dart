import 'package:flutter_test/flutter_test.dart';
import 'package:omnis_plugins/lyrics_plugin.dart';
import 'package:omnis_plugins/replay_gain_plugin.dart';
import 'package:omnis/core/base_track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // LyricsPlugin now persists via its own PluginStorage (real
    // SharedPreferences.getInstance(), not the null-safe "_prefs?."
    // AppSettings used before) — every plugin-storage-touching test file
    // needs this, per docs/PLUGIN_GUIDE.md's testing section.
    SharedPreferences.setMockInitialValues({});
  });

  test('replay gain plugin computes a multiplier from track gain', () {
    final plugin = ReplayGainPlugin();
    final track = BaseTrack(
      id: 't1',
      title: 'Test',
      artists: ['A'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
      replayGain: ReplayGainValues(trackGain: -6.0),
    );

    plugin.onTrackStart(track);

    expect(plugin.multiplier, greaterThan(1.0));
  });

  test('lyrics plugin stores and retrieves lyrics by track id', () {
    final plugin = LyricsPlugin();
    final track = BaseTrack(
      id: 't2',
      title: 'Test 2',
      artists: ['B'],
      album: 'Album',
      duration: 200,
      type: TrackType.local,
    );

    plugin.setLyric(track.id, 'Hold on to the feeling');

    expect(plugin.lyricFor(track), 'Hold on to the feeling');
  });
}
