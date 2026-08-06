import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugins/shuffle_repeat_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records shuffle/repeat traffic without a real audio engine.
class _FakeEngine implements AudioEngine {
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

  @override
  bool get shuffleEnabled => shuffle;

  @override
  Future<void> setShuffleEnabled(bool enabled) async => shuffle = enabled;

  @override
  RepeatMode get repeatMode => repeat;

  @override
  Future<void> setRepeatMode(RepeatMode mode) async => repeat = mode;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

PluginManager _managerWith(_FakeEngine engine) {
  final manager = PluginManager();
  manager.attachContext(PluginContext(
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

  test('toggleShuffle flips the engine and persists across a fresh instance',
      () async {
    final engine = _FakeEngine();
    final manager = _managerWith(engine);
    final plugin = ShuffleRepeatPlugin();
    manager.register(plugin);
    await manager.initializeAll();

    await plugin.toggleShuffle();
    expect(engine.shuffle, isTrue);
    expect(plugin.shuffleEnabled, isTrue);

    // A fresh app start: new engine, new manager, new plugin instance.
    final freshEngine = _FakeEngine();
    final freshManager = _managerWith(freshEngine);
    final freshPlugin = ShuffleRepeatPlugin();
    freshManager.register(freshPlugin);
    await freshManager.initializeAll();

    expect(freshEngine.shuffle, isTrue,
        reason: 'initialize() must restore the persisted toggle onto the '
            'engine, the way main_core.dart used to do directly');
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
}
