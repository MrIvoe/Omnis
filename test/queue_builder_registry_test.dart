import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/queue_preset_plugin.dart';
import 'package:omnis_plugins/smart_playlist_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No-op stand-in for AudioEngine — neither plugin under test touches
/// playback.
class _FakeEngine implements AudioEngine {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  BaseTrack track({
    required String id,
    String? mood,
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
        mood: mood,
        genres: genres,
        bpm: bpm,
      );

  test('both plugins register as IQueueBuilder, in the order they were '
      'registered with PluginManager', () async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    // Deliberately registered SmartPlaylistPlugin first, matching
    // bundled_plugins.dart's real order.
    manager.register(SmartPlaylistPlugin());
    manager.register(QueuePresetPlugin());
    await manager.initializeAll();

    final builders = manager.services.getAll<IQueueBuilder>();

    expect(builders, hasLength(2));
    expect(builders[0], isA<SmartPlaylistPlugin>());
    expect(builders[1], isA<QueuePresetPlugin>());
  });

  test('a curated mood match from the first builder wins over the second '
      "builder's objective fallback — the whole reason registration order "
      'is meaningful for IQueueBuilder', () async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    manager.register(SmartPlaylistPlugin());
    manager.register(QueuePresetPlugin());
    await manager.initializeAll();

    final tracks = [
      track(id: 'curated', mood: 'Chill'),
      track(id: 'other', genres: ['Death Metal']),
    ];

    // Simulates MoodsPageState.playMood's "first non-empty result wins"
    // loop (that page moved to `omnis_plugins` at Tier 2 task 4; the
    // registration-order contract it depends on is still this app's).
    List<BaseTrack> queue = const [];
    for (final builder in manager.services.getAll<IQueueBuilder>()) {
      final result = builder.buildQueueFor(tracks, 'Chill');
      if (result.isNotEmpty) {
        queue = result;
        break;
      }
    }

    expect(queue.map((t) => t.id), ['curated']);
  });

  test("QueuePresetPlugin's fallback still produces a queue when nothing "
      'has mood tags at all — the case a freshly scanned library hits', () async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    manager.register(SmartPlaylistPlugin());
    manager.register(QueuePresetPlugin());
    await manager.initializeAll();

    final tracks = [track(id: 'untagged', genres: const [])];

    List<BaseTrack> queue = const [];
    for (final builder in manager.services.getAll<IQueueBuilder>()) {
      final result = builder.buildQueueFor(tracks, 'Sleep');
      if (result.isNotEmpty) {
        queue = result;
        break;
      }
    }

    expect(queue.map((t) => t.id), ['untagged']);
  });

  test('disabling SmartPlaylistPlugin removes it from IQueueBuilder without '
      "affecting QueuePresetPlugin's registration", () async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    manager.register(SmartPlaylistPlugin());
    manager.register(QueuePresetPlugin());
    await manager.initializeAll();

    final smart = manager.byId('smart_playlist')!;
    await manager.disablePlugin(smart);

    final builders = manager.services.getAll<IQueueBuilder>();
    expect(builders, hasLength(1));
    expect(builders.single, isA<QueuePresetPlugin>());
  });
}
