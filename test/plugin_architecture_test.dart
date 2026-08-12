import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis_plugins/bundled_plugins.dart';
import 'package:omnis_plugins/equalizer_plugin.dart';
import 'package:omnis_plugins/lyrics_plugin.dart';
import 'package:omnis_plugins/replay_gain_plugin.dart';
import 'package:omnis_plugins/scrobble_plugin.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';
import 'package:omnis/ui/now_playing_page.dart' show TapZoneAction, tapZoneAction;
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records gain traffic without needing a real audio engine.
class _FakeEngine implements AudioEngine {
  final Map<String, double> gains = {};
  int pauseCount = 0;

  @override
  Future<void> setGainContribution(String source, double multiplier) async {
    gains[source] = multiplier;
  }

  @override
  Future<void> clearGainContribution(String source) async {
    gains.remove(source);
  }

  // EqualizerPlugin reads this on every `hasHardwareBands` check (which
  // its `description` getter also touches) — no hardware EQ in these
  // fakes, so the virtual-band code path is what's under test here.
  @override
  List<HardwareEqBand>? get hardwareEqBands => null;

  @override
  Future<void> ensureHardwareEqLoaded() async {}

  @override
  Future<void> pause() async => pauseCount++;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// Reads/writes its own [MusicPlugin.storage] during lifecycle hooks, to
/// prove [PluginManager] warms it before `initialize()` runs and that it
/// survives across separate plugin instances the way `AppSettings`-backed
/// state does.
class _StoragePlugin extends MusicPlugin {
  String? seenOnInitialize;

  @override
  String get id => 'storage_test';
  @override
  String get name => 'Storage Test';
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';

  @override
  Future<void> initialize() async {
    // Warmed by PluginManager before this runs — a synchronous read here
    // must see whatever was persisted by an earlier instance, not `null`.
    seenOnInitialize = storage.getString('note');
    await storage.setString('note', 'hello');
  }

  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}
}

/// Records its id into a shared [log] when [initialize] finishes — used to
/// assert `initializeAll()`'s two-round parallel/sequential ordering
/// without depending on real bundled plugins or their real dependencies.
class _RoundPlugin extends MusicPlugin {
  final String _id;
  final List<String> log;
  final Future<void> Function()? delay;
  @override
  final bool requiresSequentialInit;

  _RoundPlugin(this._id, this.log,
      {this.delay, this.requiresSequentialInit = false});

  @override
  String get id => _id;
  @override
  String get name => _id;
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';

  @override
  Future<void> initialize() async {
    if (delay != null) await delay!();
    log.add(_id);
  }

  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}
}

/// Minimal plugin used to assert lifecycle ordering.
class _LifecyclePlugin extends MusicPlugin {
  final List<String> calls = [];

  @override
  String get id => 'lifecycle';
  @override
  String get name => 'Lifecycle';
  @override
  String get description => 'Records lifecycle calls';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';

  @override
  Future<void> initialize() async => calls.add('initialize');
  @override
  Future<void> enable() async => calls.add('enable');
  @override
  Future<void> disable() async => calls.add('disable');
  @override
  Future<void> onTrackStart(BaseTrack track) async => calls.add('track');
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async => calls.add('dispose');
}

BaseTrack _track({String id = 't1', double? gain}) => BaseTrack(
      id: id,
      title: 'Track $id',
      artists: const ['A'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
      localPath: '/music/$id.mp3',
      replayGain: gain == null ? null : ReplayGainValues(trackGain: gain),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // PluginManager consults AppSettings for persisted enable/disable state;
    // give every test a clean store.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('bundled plugin registry', () {
    test('every bundled plugin has a unique id and registers', () {
      final manager = PluginManager();
      final bundled = createBundledPlugins();

      for (final plugin in bundled) {
        manager.register(plugin);
      }

      expect(bundled, isNotEmpty);
      expect(
        bundled.map((p) => p.id).toSet(),
        hasLength(bundled.length),
        reason: 'duplicate plugin ids would silently drop a plugin',
      );
      expect(manager.plugins, hasLength(bundled.length));
      expect(manager.plugins.every((p) => p.isBundled), isTrue);
    });

    test(
        'exactly QueuePresetPlugin and EqualizerPlugin declare '
        'requiresSequentialInit — this must stay in sync with '
        "bundled_plugins.dart's documented ordering dependencies "
        '(QueuePresetPlugin after SmartPlaylistPlugin, EqualizerPlugin '
        'after BluetoothPlaybackPlugin); a third dependency added without '
        'updating both that doc and this test fails here rather than '
        'silently racing under initializeAll()\'s parallel round', () {
      final flagged = createBundledPlugins()
          .where((p) => p.requiresSequentialInit)
          .map((p) => p.id)
          .toSet();

      expect(flagged, {'queue_presets', 'equalizer'});
    });

    test('bundled<T>() returns the registered shared instance', () {
      final manager = PluginManager();
      for (final plugin in createBundledPlugins()) {
        manager.register(plugin);
      }

      final equalizer = manager.bundled<EqualizerPlugin>();
      expect(equalizer, isNotNull);
      // The instance the UI resolves must be the same object the manager
      // dispatches hooks to — the old UI built its own and got neither.
      expect(identical(equalizer, manager.bundled<EqualizerPlugin>()), isTrue);
      expect(
        identical(equalizer, manager.byId('equalizer')!.inProcess),
        isTrue,
      );
      expect(manager.bundled<LyricsPlugin>(), isNotNull);
    });

    test('bundled<T>(onlyEnabled: true) hides a disabled plugin', () async {
      final manager = PluginManager();
      for (final plugin in createBundledPlugins()) {
        manager.register(plugin);
      }

      expect(manager.bundled<ScrobblePlugin>(onlyEnabled: true), isNotNull);
      await manager.disablePlugin(manager.byId('scrobble')!);

      expect(manager.bundled<ScrobblePlugin>(onlyEnabled: true), isNull);
      // Still reachable without the filter, so it can be re-enabled.
      expect(manager.bundled<ScrobblePlugin>(), isNotNull);
    });
  });

  group('PluginContext wiring', () {
    test('attachContext reaches plugins registered before and after it', () {
      final engine = _FakeEngine();
      final context = OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      );
      final manager = PluginManager();

      final early = EqualizerPlugin();
      manager.register(early);
      expect(early.context, isNull);

      manager.attachContext(context);
      expect(early.context, same(context));

      final late_ = LyricsPlugin();
      manager.register(late_);
      expect(late_.context, same(context));
    });

    test('equalizer bands reach the engine as a gain contribution', () async {
      final engine = _FakeEngine();
      final manager = PluginManager()
        ..attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      final equalizer = EqualizerPlugin();
      manager.register(equalizer);

      equalizer.setBand('bass', 12.0);
      await Future<void>.delayed(Duration.zero);

      expect(engine.gains[EqualizerPlugin.gainSource], greaterThan(1.0));

      equalizer.reset();
      await Future<void>.delayed(Duration.zero);
      expect(engine.gains[EqualizerPlugin.gainSource], closeTo(1.0, 1e-9));
    });

    test('replay gain contributes on track start and releases on disable',
        () async {
      final engine = _FakeEngine();
      final manager = PluginManager()
        ..attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      final replayGain = ReplayGainPlugin();
      manager.register(replayGain);

      await manager.onTrackStart(_track(gain: -6.0));
      expect(engine.gains[ReplayGainPlugin.gainSource], greaterThan(1.0));

      // A disabled plugin must not keep shaping playback.
      await manager.disablePlugin(manager.byId('replay_gain')!);
      expect(engine.gains.containsKey(ReplayGainPlugin.gainSource), isFalse);
    });

    test('sleep timer pauses through the context when it fires', () async {
      final engine = _FakeEngine();
      final manager = PluginManager()
        ..attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      final timer = SleepTimerPlugin();
      manager.register(timer);
      // This test is about the pause reaching the real engine through
      // PluginContext, not fade timing (that's sleep_timer_plugin_test.dart's
      // job) — disable the fade so it isolates that concern.
      await timer.storage.initialize();
      await timer.setFadeSeconds(0);

      timer.startTimer(const Duration(milliseconds: 30));
      expect(timer.isActive, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(timer.isActive, isFalse);
      // The registered instance used to be built with no pause callback at
      // all, so its timer fired into the void.
      expect(engine.pauseCount, 1);
    });
  });

  group('plugin lifecycle', () {
    test('re-enabling calls enable(), not initialize() a second time',
        () async {
      final manager = PluginManager();
      final plugin = _LifecyclePlugin();
      manager.register(plugin);
      await manager.initializeAll();

      expect(plugin.calls, ['initialize']);

      final managed = manager.byId('lifecycle')!;
      await manager.disablePlugin(managed);
      await manager.enablePlugin(managed);

      expect(plugin.calls, ['initialize', 'disable', 'enable']);
    });

    test('a disabled plugin receives no hooks', () async {
      final manager = PluginManager();
      final plugin = _LifecyclePlugin();
      manager.register(plugin);
      await manager.initializeAll();

      await manager.disablePlugin(manager.byId('lifecycle')!);
      await manager.onTrackStart(_track());

      expect(plugin.calls, isNot(contains('track')));
    });

    test('storage is warmed before initialize() runs, and persists across '
        'a fresh plugin instance the way AppSettings-backed state does',
        () async {
      final manager = PluginManager();
      final plugin = _StoragePlugin();
      manager.register(plugin);
      await manager.initializeAll();

      // Nothing was persisted yet, but storage.getString must already be
      // readable (not throw, not silently stale) inside initialize().
      expect(plugin.seenOnInitialize, isNull);
      expect(plugin.storage.getString('note'), 'hello');

      final second = PluginManager();
      final freshInstance = _StoragePlugin();
      second.register(freshInstance);
      await second.initializeAll();

      expect(freshInstance.seenOnInitialize, 'hello');
    });

    test('disabled state survives a fresh PluginManager', () async {
      final first = PluginManager();
      first.register(ScrobblePlugin());
      await first.disablePlugin(first.byId('scrobble')!);

      // A new manager reads the persisted state, the way a restart would.
      final second = PluginManager();
      second.register(ScrobblePlugin());

      expect(second.byId('scrobble')!.enabled, isFalse);
    });
  });

  group('initializeAll() parallel rounds', () {
    test(
        'round-one plugins initialize concurrently, not one at a time — '
        'total elapsed time is close to the slowest single delay, not '
        'their sum', () async {
      final manager = PluginManager();
      final log = <String>[];
      const delay = Duration(milliseconds: 60);
      manager.register(_RoundPlugin('a', log,
          delay: () => Future.delayed(delay)));
      manager.register(_RoundPlugin('b', log,
          delay: () => Future.delayed(delay)));
      manager.register(_RoundPlugin('c', log,
          delay: () => Future.delayed(delay)));

      final stopwatch = Stopwatch()..start();
      await manager.initializeAll();
      stopwatch.stop();

      expect(log.toSet(), {'a', 'b', 'c'});
      // Sequential would take ~180ms; parallel takes ~60ms. 150ms is a
      // generous cutoff that only a sequential run could cross.
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });

    test(
        'a requiresSequentialInit plugin only initializes after every '
        'round-one plugin has finished — even one that is slower than it '
        'and registered after it', () async {
      final manager = PluginManager();
      final log = <String>[];
      // 'slow' finishes after 'fast' despite being registered first, and
      // after 'sequential' too if round two ran in parallel with round
      // one instead of strictly after it — proving the wait is on "every
      // round-one plugin," not "the previous list entry."
      manager.register(_RoundPlugin('slow', log,
          delay: () => Future.delayed(const Duration(milliseconds: 40))));
      manager.register(_RoundPlugin('fast', log));
      manager.register(
          _RoundPlugin('sequential', log, requiresSequentialInit: true));

      await manager.initializeAll();

      expect(log.indexOf('sequential'), greaterThan(log.indexOf('slow')));
      expect(log.indexOf('sequential'), greaterThan(log.indexOf('fast')));
    });

    test('a disabled plugin is skipped entirely by both rounds, same as '
        'the previous sequential initializeAll()', () async {
      final manager = PluginManager();
      final log = <String>[];
      final plugin = _RoundPlugin('disabled', log);
      manager.register(plugin);
      await manager.disablePlugin(manager.byId('disabled')!);

      await manager.initializeAll();

      expect(log, isEmpty);
    });
  });

  group('AudioEngine.uriFor', () {
    test('treats a Windows drive letter as a path, not a URI scheme', () {
      final uri = AudioEngine.uriFor(BaseTrack(
        id: 'w',
        title: 'W',
        artists: const ['A'],
        album: 'Album',
        duration: 1,
        type: TrackType.local,
        localPath: r'C:\Music\song.mp3',
      ));

      expect(uri, isNotNull);
      expect(uri!.scheme, 'file');
      expect(uri.toFilePath(windows: true), r'C:\Music\song.mp3');
    });

    test('keeps real URI schemes intact', () {
      final content = AudioEngine.uriFor(BaseTrack(
        id: 'c',
        title: 'C',
        artists: const ['A'],
        album: 'Album',
        duration: 1,
        type: TrackType.local,
        localPath: 'content://media/external/audio/media/42',
      ));
      expect(content!.scheme, 'content');

      final stream = AudioEngine.uriFor(BaseTrack(
        id: 's',
        title: 'S',
        artists: const ['A'],
        album: 'Album',
        duration: 1,
        type: TrackType.youtube,
        streamUrl: 'https://example.com/a.mp3',
      ));
      expect(stream!.scheme, 'https');
    });

    test('returns null when a track has nothing playable', () {
      final uri = AudioEngine.uriFor(BaseTrack(
        id: 'n',
        title: 'N',
        artists: const ['A'],
        album: 'Album',
        duration: 1,
        type: TrackType.local,
      ));
      expect(uri, isNull);
    });
  });

  group('AudioEngine.crossfadeVolumes', () {
    test('splits base volume between outgoing and incoming players', () {
      final (outgoing, incoming) = AudioEngine.crossfadeVolumes(1.0, 0.0);
      expect(outgoing, 1.0);
      expect(incoming, 0.0);

      final (midOut, midIn) = AudioEngine.crossfadeVolumes(1.0, 0.5);
      expect(midOut, closeTo(0.5, 1e-9));
      expect(midIn, closeTo(0.5, 1e-9));

      final (endOut, endIn) = AudioEngine.crossfadeVolumes(1.0, 1.0);
      expect(endOut, closeTo(0.0, 1e-9));
      expect(endIn, closeTo(1.0, 1e-9));
    });

    test('always sums back to the base volume, at any progress', () {
      for (final progress in [0.0, 0.2, 0.5, 0.75, 1.0]) {
        final (outgoing, incoming) =
            AudioEngine.crossfadeVolumes(0.8, progress);
        expect(outgoing + incoming, closeTo(0.8, 1e-9));
      }
    });

    test('clamps progress and base volume to sane ranges', () {
      final (over, _) = AudioEngine.crossfadeVolumes(0.5, 1.5);
      expect(over, closeTo(0.0, 1e-9));

      final (negOut, negIn) = AudioEngine.crossfadeVolumes(0.5, -0.5);
      expect(negOut, closeTo(0.5, 1e-9));
      expect(negIn, closeTo(0.0, 1e-9));

      final (clampedOut, clampedIn) = AudioEngine.crossfadeVolumes(5.0, 0.5);
      expect(clampedOut, closeTo(0.5, 1e-9));
      expect(clampedIn, closeTo(0.5, 1e-9));
    });
  });

  group('EqualizerPlugin hardware bands', () {
    test('setHardwareBand updates the matching band and persists gains',
        () async {
      final bandA =
          HardwareEqBand.forTesting(index: 0, centerFrequencyHz: 60);
      final bandB =
          HardwareEqBand.forTesting(index: 1, centerFrequencyHz: 1000);
      final engine = _HardwareEqFakeEngine([bandA, bandB]);
      final manager = PluginManager()
        ..attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      final equalizer = EqualizerPlugin();
      manager.register(equalizer);
      await manager.initializeAll();

      expect(equalizer.hasHardwareBands, isTrue);
      // Real hardware bands are shaping the signal directly — the virtual
      // gain contribution must not also apply a trim on top of that.
      expect(equalizer.combinedMultiplier, 1.0);

      await equalizer.setHardwareBand(0, 6.0);
      expect(bandA.gain, 6.0);
      await equalizer.persistHardwareBands();

      // EqualizerPlugin now persists via its own PluginStorage, not
      // AppSettings — reset the shared fake band directly to prove the
      // restoration step below actually re-reads the persisted value
      // rather than just observing a gain that was never touched.
      await bandA.setGain(0.0);
      expect(bandA.gain, 0.0);

      // A fresh plugin against the same (still-loaded) bands restores the
      // persisted gain instead of coming back flat. Driven directly
      // (not via PluginManager.register) because PluginManager silently
      // no-ops registering a second plugin with an id already in use —
      // `restored` shares the 'equalizer' id with the plugin registered
      // above, so manager.byId('equalizer') would just resolve back to
      // the original, already-initialized instance instead of this one.
      final restored = EqualizerPlugin();
      restored.attach(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      await restored.storage.initialize();
      await restored.initialize();
      expect(bandA.gain, 6.0);
    });

    test('falls back to the virtual model when there is no hardware EQ',
        () async {
      final engine = _HardwareEqFakeEngine(const []);
      final manager = PluginManager()
        ..attachContext(OmnisPluginContext(
        audioEngine: engine,
        services: ServiceRegistry(),
        events: EventBus(),
      ));
      final equalizer = EqualizerPlugin();
      manager.register(equalizer);

      expect(equalizer.hasHardwareBands, isFalse);
      equalizer.setBand('bass', 6.0);
      expect(equalizer.combinedMultiplier, greaterThan(1.0));
    });
  });

  group('now_playing_page.tapZoneAction', () {
    test('right half of the content skips forward', () {
      expect(tapZoneAction(600, 800), TapZoneAction.next);
    });

    test('left half of the content skips backward', () {
      expect(tapZoneAction(100, 800), TapZoneAction.previous);
    });

    test('returns null before layout has produced a real width', () {
      expect(tapZoneAction(50, 0), isNull);
    });
  });

  group('PluginSlotView', () {
    testWidgets('renders a real Widget from a bundled plugin', (tester) async {
      final manager = PluginManager();
      manager.register(_WidgetSlotPlugin());
      await manager.initializeAll();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PluginSlotView(
            pluginManager: manager,
            locationId: 'now_playing_overlay',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('widget slot'), findsOneWidget);
    });

    testWidgets('renders a declarative Map payload (the external-plugin path)',
        (tester) async {
      final manager = PluginManager();
      manager.register(_DeclarativeSlotPlugin());
      await manager.initializeAll();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PluginSlotView(
            pluginManager: manager,
            locationId: 'now_playing_overlay',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('declarative badge'), findsOneWidget);
    });

    testWidgets('renders nothing for a location no plugin uses', (tester) async {
      final manager = PluginManager();
      manager.register(_WidgetSlotPlugin());
      await manager.initializeAll();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PluginSlotView(
            pluginManager: manager,
            locationId: 'settings_page',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('widget slot'), findsNothing);
    });
  });

  group('PluginManager.uiSlotForPlugin', () {
    test('calls exactly the specified plugin, not every enabled plugin',
        () async {
      final manager = PluginManager();
      manager.register(_SettingsSlotPlugin(id: 'a', text: 'settings A'));
      manager.register(_SettingsSlotPlugin(id: 'b', text: 'settings B'));
      await manager.initializeAll();

      final result =
          await manager.uiSlotForPlugin(manager.byId('a')!, 'plugin_settings');

      expect(result, isA<Text>());
      expect((result as Text).data, 'settings A');
    });

    test('returns null when the plugin has nothing at that location',
        () async {
      final manager = PluginManager();
      manager.register(_SettingsSlotPlugin(id: 'a', text: 'settings A'));
      await manager.initializeAll();

      final result =
          await manager.uiSlotForPlugin(manager.byId('a')!, 'now_playing_overlay');

      expect(result, isNull);
    });

    test('works even when the plugin is disabled — settings must stay '
        'reachable so a disabled plugin can be reconfigured or re-enabled',
        () async {
      final manager = PluginManager();
      manager.register(_SettingsSlotPlugin(id: 'a', text: 'settings A'));
      await manager.initializeAll();
      await manager.disablePlugin(manager.byId('a')!);

      final result =
          await manager.uiSlotForPlugin(manager.byId('a')!, 'plugin_settings');

      expect(result, isA<Text>());
    });

    test('a throwing plugin is sandboxed: returns null, does not throw out',
        () async {
      final manager = PluginManager();
      manager.register(_ThrowingSettingsSlotPlugin());
      await manager.initializeAll();

      final result = await manager.uiSlotForPlugin(
          manager.byId('throwing_settings')!, 'plugin_settings');

      expect(result, isNull);
      expect(manager.sandbox.healthRecords, isNotEmpty);
    });
  });
}

/// A fake [AudioEngine] that reports pre-built hardware bands, used to
/// exercise [EqualizerPlugin]'s hardware-mode code path without a real
/// Android platform channel.
class _HardwareEqFakeEngine implements AudioEngine {
  final List<HardwareEqBand> _bands;
  _HardwareEqFakeEngine(this._bands);

  @override
  List<HardwareEqBand>? get hardwareEqBands => _bands.isEmpty ? null : _bands;

  @override
  Future<void> ensureHardwareEqLoaded() async {}

  @override
  Future<void> setGainContribution(String source, double multiplier) async {}

  @override
  Future<void> clearGainContribution(String source) async {}

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

class _SettingsSlotPlugin extends MusicPlugin {
  final String _id;
  final String text;

  _SettingsSlotPlugin({required String id, required this.text}) : _id = id;

  @override
  String get id => _id;
  @override
  String get name => 'Settings Slot $_id';
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) =>
      locationID == 'plugin_settings' ? Text(text) : null;
  @override
  Future<void> dispose() async {}
}

class _ThrowingSettingsSlotPlugin extends MusicPlugin {
  @override
  String get id => 'throwing_settings';
  @override
  String get name => 'Throwing Settings';
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => throw StateError('boom');
  @override
  Future<void> dispose() async {}
}

class _WidgetSlotPlugin extends MusicPlugin {
  @override
  String get id => 'widget_slot';
  @override
  String get name => 'Widget Slot';
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) =>
      locationID == 'now_playing_overlay' ? const Text('widget slot') : null;
  @override
  Future<void> dispose() async {}
}

class _DeclarativeSlotPlugin extends MusicPlugin {
  @override
  String get id => 'declarative_slot';
  @override
  String get name => 'Declarative Slot';
  @override
  String get description => 'test';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {}
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => locationID == 'now_playing_overlay'
      ? {'type': 'badge', 'text': 'declarative badge', 'icon': 'info'}
      : null;
  @override
  Future<void> dispose() async {}
}
