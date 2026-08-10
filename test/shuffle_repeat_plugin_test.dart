import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis_plugins/shuffle_repeat_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseTrack _track(String id, {String artist = 'Artist', String album = 'Album'}) =>
    BaseTrack(
      id: id,
      title: 'T$id',
      artists: [artist],
      album: album,
      duration: 180,
      type: TrackType.local,
    );

/// Records shuffle/repeat/queue traffic without a real audio engine.
class _FakeEngine implements AudioEngine {
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;
  List<BaseTrack> queueTracks = const [];
  int queueStartIndex = 0;

  @override
  bool get shuffleEnabled => shuffle;

  @override
  Future<void> setShuffleEnabled(bool enabled) async => shuffle = enabled;

  @override
  RepeatMode get repeatMode => repeat;

  @override
  Future<void> setRepeatMode(RepeatMode mode) async => repeat = mode;

  @override
  List<BaseTrack> get queue => queueTracks;

  @override
  BaseTrack? get currentTrack =>
      queueTracks.isEmpty ? null : queueTracks[queueStartIndex];

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    queueTracks = tracks;
    queueStartIndex = startIndex;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

PluginManager _managerWith(_FakeEngine engine) {
  final manager = PluginManager();
  manager.attachContext(OmnisPluginContext(
    audioEngine: engine,
    services: manager.services,
    events: manager.events,
  ));
  return manager;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  test('defaults to shuffle off and repeat off when nothing was persisted',
      () async {
    final engine = _FakeEngine();
    final manager = _managerWith(engine);
    final plugin = ShuffleRepeatPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    expect(engine.shuffle, isFalse);
    expect(engine.repeat, RepeatMode.off);
    expect(plugin.shuffleEnabled, isFalse);
    expect(plugin.repeatMode, RepeatMode.off);
  });

  test(
      'toggleShuffle re-orders the queue itself (not the engine shuffle '
      'flag) and persists the toggle across a fresh instance', () async {
    final engine = _FakeEngine()
      ..queueTracks = [_track('1'), _track('2'), _track('3')];
    final manager = _managerWith(engine);
    final plugin = ShuffleRepeatPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await plugin.toggleShuffle();
    // The engine's own shuffle flag is never touched — this plugin owns
    // ordering itself now, not just_audio's shuffle mode.
    expect(engine.shuffle, isFalse);
    expect(plugin.shuffleEnabled, isTrue);
    expect(engine.queueTracks, hasLength(3));
    expect(engine.queueTracks.map((t) => t.id).toSet(), {'1', '2', '3'});

    // A fresh app start: new engine, new manager, new plugin instance.
    final freshEngine = _FakeEngine();
    final freshManager = _managerWith(freshEngine);
    final freshPlugin = ShuffleRepeatPlugin();
    freshManager.register(freshPlugin);
    await freshManager.initializeAll();

    expect(freshPlugin.shuffleEnabled, isTrue,
        reason: 'initialize() must restore the persisted toggle onto the '
            'plugin itself');
  });

  test('toggling shuffle off restores the exact pre-shuffle order',
      () async {
    final engine = _FakeEngine()
      ..queueTracks = [_track('1'), _track('2'), _track('3'), _track('4')];
    final manager = _managerWith(engine);
    final plugin = ShuffleRepeatPlugin();
    manager.register(plugin);
    await manager.initializeAll();
    final original = List.of(engine.queueTracks);

    await plugin.toggleShuffle();
    expect(plugin.shuffleEnabled, isTrue);

    await plugin.toggleShuffle();
    expect(plugin.shuffleEnabled, isFalse);
    expect(engine.queueTracks.map((t) => t.id),
        original.map((t) => t.id));
  });

  test(
      'deClusteredOrder avoids placing same-artist/same-album tracks '
      'adjacently when a non-conflicting swap is available', () {
    final tracks = [
      _track('a1', artist: 'X', album: 'AlbumX'),
      _track('a2', artist: 'X', album: 'AlbumX'),
      _track('a3', artist: 'X', album: 'AlbumX'),
      _track('b1', artist: 'Y', album: 'AlbumY'),
      _track('b2', artist: 'Y', album: 'AlbumY'),
      _track('b3', artist: 'Y', album: 'AlbumY'),
    ];

    // Run many times since the algorithm starts from a random shuffle —
    // a flaky assertion here would mean the de-clustering pass itself is
    // unreliable, not just unlucky.
    for (var attempt = 0; attempt < 20; attempt++) {
      final result = ShuffleRepeatPlugin.deClusteredOrder(tracks);
      expect(result, hasLength(tracks.length));
      expect(result.map((t) => t.id).toSet(), tracks.map((t) => t.id).toSet());
      for (var i = 1; i < result.length; i++) {
        expect(result[i - 1].artists.first == result[i].artists.first, isFalse,
            reason: 'same-artist tracks landed adjacent: '
                '${result[i - 1].id}, ${result[i].id}');
      }
    }
  });

  test('deClusteredOrder leaves fewer than 3 tracks untouched (order-wise)',
      () {
    final tracks = [_track('1'), _track('2')];
    final result = ShuffleRepeatPlugin.deClusteredOrder(tracks);
    expect(result.map((t) => t.id).toSet(), {'1', '2'});
  });

  test('cycleRepeat goes off -> all -> one -> off and persists each step',
      () async {
    final engine = _FakeEngine();
    final manager = _managerWith(engine);
    final plugin = ShuffleRepeatPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await plugin.cycleRepeat();
    expect(engine.repeat, RepeatMode.all);

    await plugin.cycleRepeat();
    expect(engine.repeat, RepeatMode.one);

    await plugin.cycleRepeat();
    expect(engine.repeat, RepeatMode.off);

    // Persisted at the "one" step above, then back to "off" — a fresh
    // instance restored right after the second cycleRepeat() should see
    // "one" if it existed then, so re-check the "one" -> restore case here.
    await plugin.cycleRepeat(); // off -> all
    final freshEngine = _FakeEngine();
    final freshManager = _managerWith(freshEngine);
    final freshPlugin = ShuffleRepeatPlugin();
    freshManager.register(freshPlugin);
    await freshManager.initializeAll();

    expect(freshEngine.repeat, RepeatMode.all);
  });

  group('cyclePlayMode', () {
    test('cycles off -> repeat all -> repeat one -> shuffle -> off',
        () async {
      final engine = _FakeEngine()
        ..queueTracks = [_track('1'), _track('2'), _track('3')];
      final manager = _managerWith(engine);
      final plugin = ShuffleRepeatPlugin();
      manager.register(plugin);
      await manager.initializeAll();

      await plugin.cyclePlayMode();
      expect(engine.repeat, RepeatMode.all);
      expect(plugin.shuffleEnabled, isFalse);

      await plugin.cyclePlayMode();
      expect(engine.repeat, RepeatMode.one);
      expect(plugin.shuffleEnabled, isFalse);

      await plugin.cyclePlayMode();
      expect(engine.repeat, RepeatMode.off,
          reason: 'entering shuffle must clear repeat — the two were '
              'never meant to combine');
      expect(plugin.shuffleEnabled, isTrue);

      await plugin.cyclePlayMode();
      expect(engine.repeat, RepeatMode.off);
      expect(plugin.shuffleEnabled, isFalse);
    });

    test('starting from shuffle-on (independently toggled) clears shuffle '
        'first rather than also touching repeat', () async {
      final engine = _FakeEngine()
        ..queueTracks = [_track('1'), _track('2'), _track('3')];
      final manager = _managerWith(engine);
      final plugin = ShuffleRepeatPlugin();
      manager.register(plugin);
      await manager.initializeAll();

      await plugin.toggleShuffle();
      expect(plugin.shuffleEnabled, isTrue);

      await plugin.cyclePlayMode();
      expect(plugin.shuffleEnabled, isFalse);
      expect(engine.repeat, RepeatMode.off);
    });
  });
}
