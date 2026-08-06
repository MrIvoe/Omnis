import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/player_layouts/declarative/declarative_layout.dart';
import 'package:omnis/ui/player_layouts/declarative/declarative_layout_renderer.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_installer.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_manifest.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake path_provider that returns a temp directory, so LayoutInstaller can
/// write/read under it in tests — same pattern as library_store_test.dart.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

BaseTrack _track() => BaseTrack(
      id: 't1',
      title: 'Sunrise',
      artists: const ['Ava'],
      album: 'Morning',
      duration: 180,
      type: TrackType.local,
      localPath: '/music/sunrise.mp3',
    );

PlayerLayoutData _dataFor(AppSettings settings) => PlayerLayoutData(
      track: _track(),
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 180),
      playing: false,
      buffering: false,
      settings: settings,
      pluginManager: PluginManager(),
      lyricsPlugin: null,
      equalizerPlugin: null,
      visualizerPlugin: null,
      sleepTimerPlugin: null,
      lyricText: null,
      crossfadeStatusText: null,
      shuffleEnabled: false,
      repeatMode: RepeatMode.off,
      loopAMarker: null,
      abRepeatRange: null,
      onPlayPause: () {},
      onNext: () {},
      onPrevious: () {},
      onSeek: (_) {},
      onOpenEqualizer: () {},
      onEditLyrics: () {},
      onActivateVisualizer: () {},
      onStartSleepTimer: () {},
      onToggleShuffle: () {},
      onCycleRepeat: () {},
      onCycleAbRepeat: () {},
    );

const _validYaml = '''
id: test_layout
name: Test Layout
description: A test layout
author: Tester
version: 1.0.0
defines_own_gestures: false
root:
  type: column
  children:
    - { type: component, component: album_art }
    - { type: component, component: track_info }
    - { type: component, component: controls_row }
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Read once, outside any testWidgets() zone. `dart:io` file reads awaited
  // directly inside a testWidgets() callback reliably hang forever on this
  // Windows setup — reproduced deterministically in isolation (a bare
  // `await File(...).readAsString()` with nothing else in the test body)
  // and confirmed absent in a plain `test()` doing the identical read. This
  // looks like a real interaction between TestWidgetsFlutterBinding's
  // zone/scheduler and dart:io's event loop dispatch on Windows, not
  // anything specific to this file or this renderer. setUpAll() runs
  // outside that zone, so the read completes normally; testWidgets() below
  // only ever touches the already-loaded string.
  late final String sampleLayoutText;
  setUpAll(() async {
    sampleLayoutText = await File(
      p.join('layouts', 'sample_minimal', 'omnis_layout.yaml'),
    ).readAsString();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('LayoutManifest.parse', () {
    test('parses a valid manifest', () {
      final manifest = LayoutManifest.parse(_validYaml, sourceUrl: 'test://x');
      expect(manifest, isNotNull);
      expect(manifest!.id, 'test_layout');
      expect(manifest.name, 'Test Layout');
      expect(manifest.definesOwnGestures, isFalse);
      expect(manifest.root['type'], 'column');
      expect((manifest.root['children'] as List), hasLength(3));
    });

    test('also parses JSON (a subset of YAML)', () {
      const jsonText = '''
      {
        "id": "json_layout",
        "name": "JSON Layout",
        "root": { "type": "component", "component": "album_art" }
      }
      ''';
      final manifest = LayoutManifest.parse(jsonText, sourceUrl: 'test://x');
      expect(manifest, isNotNull);
      expect(manifest!.id, 'json_layout');
    });

    test('returns null when id/name/root are missing', () {
      expect(
        LayoutManifest.parse('name: Missing Id\nroot: {type: column}',
            sourceUrl: 'x'),
        isNull,
      );
      expect(
        LayoutManifest.parse('id: no_root\nname: X', sourceUrl: 'x'),
        isNull,
      );
    });

    test('returns null for malformed YAML rather than throwing', () {
      expect(LayoutManifest.parse('not: [valid', sourceUrl: 'x'), isNull);
      expect(LayoutManifest.parse('just a plain string', sourceUrl: 'x'),
          isNull);
    });
  });

  group('DeclarativeLayoutRenderer', () {
    testWidgets(
        'renders the actual shipped sample layout (layouts/sample_minimal)',
        (tester) async {
      // Uses the real file a user would import, not a hand-typed source
      // string — proves the shipped template genuinely works with the
      // renderer, the same way plugin_system_test.dart runs the real
      // sample_logger plugin.dart through dart_eval instead of inspecting
      // it by eye. Loaded once in setUpAll(), not here — see its comment.
      final manifest =
          LayoutManifest.parse(sampleLayoutText, sourceUrl: 'local')!;
      final data = _dataFor(AppSettings.instance);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                DeclarativeLayoutRenderer.renderRoot(context, data, manifest),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('renders a valid manifest and shows real track data',
        (tester) async {
      final manifest = LayoutManifest.parse(_validYaml, sourceUrl: 'test://x')!;
      final data = _dataFor(AppSettings.instance);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                DeclarativeLayoutRenderer.renderRoot(context, data, manifest),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('an unknown component type degrades to empty, not a crash',
        (tester) async {
      final manifest = LayoutManifest.parse('''
id: weird
name: Weird
root:
  type: column
  children:
    - { type: component, component: does_not_exist }
    - { type: some_unknown_container }
    - { type: component, component: track_info }
''', sourceUrl: 'x')!;
      final data = _dataFor(AppSettings.instance);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                DeclarativeLayoutRenderer.renderRoot(context, data, manifest),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('defines_own_gestures wraps the layout in a working gesture '
        'detector', (tester) async {
      var playPauseCalls = 0;
      var nextCalls = 0;
      final manifest = LayoutManifest.parse('''
id: gestures
name: Gestures
defines_own_gestures: true
root:
  type: center
  child: { type: component, component: track_info }
''', sourceUrl: 'x')!;
      final data = PlayerLayoutData(
        track: _track(),
        position: Duration.zero,
        duration: const Duration(seconds: 180),
        playing: false,
        buffering: false,
        settings: AppSettings.instance,
        pluginManager: PluginManager(),
        lyricsPlugin: null,
        equalizerPlugin: null,
        visualizerPlugin: null,
        sleepTimerPlugin: null,
        lyricText: null,
        crossfadeStatusText: null,
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
        loopAMarker: null,
        abRepeatRange: null,
        onPlayPause: () => playPauseCalls++,
        onNext: () => nextCalls++,
        onPrevious: () {},
        onSeek: (_) {},
        onOpenEqualizer: () {},
        onEditLyrics: () {},
        onActivateVisualizer: () {},
        onStartSleepTimer: () {},
        onToggleShuffle: () {},
        onCycleRepeat: () {},
        onCycleAbRepeat: () {},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                DeclarativeLayoutRenderer.renderRoot(context, data, manifest),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector));
      expect(playPauseCalls, 1);

      await tester.fling(
          find.byType(GestureDetector), const Offset(-300, 0), 1000);
      expect(nextCalls, 1);
    });
  });

  group('LayoutInstaller + LayoutManager', () {
    late String tempDir;

    setUp(() async {
      tempDir = (await Directory.systemTemp.createTemp('omnis_layout_test')).path;
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
    });

    test('readFromFile + persist round-trips through listInstalled',
        () async {
      final source = File('${tempDir}_src.yaml');
      await source.writeAsString(_validYaml);
      addTearDown(() => source.delete());

      final installer = LayoutInstaller();
      final text = await installer.readFromFile(source.path);
      final manifest = LayoutManifest.parse(text, sourceUrl: source.path)!;
      await installer.persist(manifest, text);

      final listed = await installer.listInstalled();
      expect(listed.map((m) => m.id), contains('test_layout'));
    });

    test(
        'LayoutManager.installFromFile rejects invalid content before '
        'writing anything to disk', () async {
      final source = File('${tempDir}_bad.yaml');
      await source.writeAsString('not a valid layout at all');
      addTearDown(() => source.delete());

      final manager = LayoutManager();
      await manager.loadInstalled();
      expect(
        () => manager.installFromFile(source.path),
        throwsA(isA<LayoutInstallException>()),
      );

      // Nothing should have reached disk — a second manager loading fresh
      // must not find anything either.
      final reloaded = LayoutManager();
      await reloaded.loadInstalled();
      expect(reloaded.allLayouts.length, manager.allLayouts.length);
    });

    test('uninstall removes a previously installed layout', () async {
      final source = File('${tempDir}_src2.yaml');
      await source.writeAsString(_validYaml);
      addTearDown(() => source.delete());

      final installer = LayoutInstaller();
      final text = await installer.readFromFile(source.path);
      final manifest = LayoutManifest.parse(text, sourceUrl: source.path)!;
      await installer.persist(manifest, text);
      expect((await installer.listInstalled()).map((m) => m.id),
          contains('test_layout'));

      await installer.uninstall('test_layout');
      expect((await installer.listInstalled()).map((m) => m.id),
          isNot(contains('test_layout')));
    });

    test('LayoutManager merges installed layouts with the bundled six',
        () async {
      final source = File('${tempDir}_src3.yaml');
      await source.writeAsString(_validYaml);
      addTearDown(() => source.delete());

      final manager = LayoutManager();
      await manager.loadInstalled();
      final before = manager.allLayouts.length;

      await manager.installFromFile(source.path);
      expect(manager.allLayouts.length, before + 1);
      expect(manager.allLayouts.any((l) => l.id == 'test_layout'), isTrue);
      expect(manager.resolve('test_layout'), isA<DeclarativeLayout>());
    });

    test('LayoutManager rejects an import that collides with a bundled id',
        () async {
      final source = File('${tempDir}_src4.yaml');
      await source.writeAsString('''
id: standard
name: Fake Standard
root: { type: component, component: album_art }
''');
      addTearDown(() => source.delete());

      final manager = LayoutManager();
      await manager.loadInstalled();

      expect(
        () => manager.installFromFile(source.path),
        throwsA(isA<LayoutInstallException>()),
      );
      // The real bundled "standard" must still resolve to a non-declarative
      // layout — the rejected import must not have snuck in anyway.
      expect(manager.resolve('standard'), isNot(isA<DeclarativeLayout>()));
    });

    test('resolve() falls back to the first bundled layout for an unknown id',
        () async {
      final manager = LayoutManager();
      await manager.loadInstalled();
      expect(manager.resolve('does_not_exist').id,
          manager.allLayouts.first.id);
    });
  });
}
