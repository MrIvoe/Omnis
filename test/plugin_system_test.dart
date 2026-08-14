import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/core/plugin_sandbox_services.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake path_provider, same pattern as library_repository_test.dart — needed
/// because the sandbox-bridged loadLibraryTracks() reads through the real
/// LibraryRepository singleton.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Writes a minimal external-plugin directory (manifest + plugin.dart) for
/// [PluginManager.installFromPath], with a caller-supplied set of declared
/// permissions/hooks and hook-body source. Shared by every group below that
/// needs a real, installed external plugin rather than a bare
/// `PluginRuntime.create` call.
Future<Directory> writeEventPlugin(
  String tempRoot,
  String dirName, {
  required List<String> permissions,
  required List<String> hooks,
  required String extraSource,
}) async {
  final pluginDir = Directory(p.join(tempRoot, dirName));
  await pluginDir.create(recursive: true);
  final permYaml = permissions.map((perm) => '  - $perm').join('\n');
  await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: $dirName
name: $dirName
description: Test plugin
version: 1.0.0
author: Test
entrypoint: plugin.dart
permissions:
$permYaml
''');
  final hooksLiteral = hooks.map((h) => "'$h'").join(', ');
  await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': '$dirName',
    'name': '$dirName',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': [$hooksLiteral],
  };
}

$extraSource
''');
  return pluginDir;
}

/// A plugin that always throws — used to prove the sandbox isolates crashes.
class _CrashingPlugin extends MusicPlugin {
  @override
  String get id => 'crashy';
  @override
  String get name => 'Crashy';
  @override
  String get description => 'Always throws';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';

  @override
  Future<void> initialize() async => throw StateError('boom');

  @override
  Future<void> onTrackStart(BaseTrack track) async =>
      throw StateError('track boom');

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}

/// A plugin whose attach() throws — used to prove register() isolates a
/// crashing attach() the same way initialize() is already isolated.
class _AttachThrowsPlugin extends MusicPlugin {
  @override
  void attach(PluginContext context) => throw StateError('attach boom');

  @override
  String get id => 'attach_crashy';
  @override
  String get name => 'Attach Crashy';
  @override
  String get description => 'Always throws in attach()';
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
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}

/// A well-behaved plugin that records calls.
class _RecordingPlugin extends MusicPlugin {
  final List<String> calls = [];

  @override
  String get id => 'recorder';
  @override
  String get name => 'Recorder';
  @override
  String get description => 'Records calls';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';

  @override
  Future<void> initialize() async => calls.add('init');

  @override
  Future<void> onTrackStart(BaseTrack track) async =>
      calls.add('track:${track.title}');

  @override
  Future<void> onLibraryScan(String file) async => calls.add('scan:$file');

  @override
  dynamic uiSlot(String locationID) =>
      locationID == 'now_playing_overlay' ? 'overlay-widget' : null;

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A plugin that declares network use, and one that doesn't (the
/// default) — used to prove disableAllNetworkPlugins() only touches the
/// former.
class _NetworkPlugin extends MusicPlugin {
  @override
  bool get usesNetwork => true;

  @override
  String get id => 'network_user';
  @override
  String get name => 'Network User';
  @override
  String get description => 'Reaches the network';
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
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}

/// A no-op stand-in for PluginContext — only used to give register() a
/// non-null context so its attach()-guard path actually runs.
class _FakeContext implements PluginContext {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// A [PluginContext] stand-in for the playback-control sandbox bridge —
/// records every transport call it receives instead of touching a real
/// `AudioEngine` (which needs a platform channel `flutter test` doesn't
/// provide). Only the members the playback bridge functions actually use
/// are stubbed; anything else falls through to noSuchMethod like
/// _FakeContext above.
class _RecordingPlaybackContext implements PluginContext {
  final List<String> calls = [];

  @override
  BaseTrack? currentTrack;
  @override
  List<BaseTrack> queue = const [];
  @override
  bool isPlaying = false;
  @override
  int currentIndex = -1;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<bool> next({bool wrap = false}) async {
    calls.add('next:$wrap');
    return true;
  }

  @override
  Future<bool> previous() async {
    calls.add('previous');
    return true;
  }

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inMilliseconds}');

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

void main() {
  group('PluginManager isolation', () {
    test(
        'registerAll skips a throwing factory instead of crashing, and '
        'logs it to the health dashboard', () {
      final manager = PluginManager();

      manager.registerAll(() => throw StateError('registry boom'));

      expect(manager.plugins, isEmpty);
      expect(manager.sandbox.healthRecords, hasLength(1));
      final rec = manager.sandbox.healthRecords.first;
      expect(rec.pluginId, 'bundled');
      expect(rec.hook, 'construct');
      expect(rec.message, contains('registry boom'));
    });

    test('registerAll registers every plugin a well-behaved factory returns',
        () {
      final manager = PluginManager();

      manager.registerAll(() => [_RecordingPlugin(), _AttachThrowsPlugin()]);

      expect(manager.plugins.map((p) => p.id),
          containsAll(['recorder', 'attach_crashy']));
    });

    test(
        'register() isolates a throwing attach() instead of letting it '
        'abort registration', () {
      final manager = PluginManager()..attachContext(_FakeContext());

      manager.register(_AttachThrowsPlugin());

      // The plugin still ends up registered — only attach() failed, not
      // the whole registration — matching initPlugin()'s existing
      // "a failing hook doesn't block the rest" behavior.
      expect(manager.plugins.any((p) => p.id == 'attach_crashy'), isTrue);
      expect(manager.sandbox.healthRecords, hasLength(1));
      expect(manager.sandbox.healthRecords.first.hook, 'attach');
    });

    test(
        'disableAllNetworkPlugins only disables plugins that declare '
        'network use, leaving the rest untouched', () async {
      final manager = PluginManager();
      manager.register(_NetworkPlugin());
      manager.register(_RecordingPlugin());
      await manager.initializeAll();

      await manager.disableAllNetworkPlugins();

      final network =
          manager.plugins.firstWhere((p) => p.id == 'network_user');
      final recorder = manager.plugins.firstWhere((p) => p.id == 'recorder');
      expect(network.enabled, isFalse);
      expect(recorder.enabled, isTrue);
    });

    test('disableAllNetworkPlugins is a no-op with nothing registered',
        () async {
      final manager = PluginManager();
      await manager.disableAllNetworkPlugins();
      expect(manager.plugins, isEmpty);
    });
  });

  group('PluginSandbox', () {
    test('isolates a crashing plugin and records a health entry', () async {
      final sandbox = PluginSandbox();
      final plugin = _CrashingPlugin();

      final result = await sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'initialize',
        operation: () async {
          await plugin.initialize();
          return null;
        },
      );

      expect(result, isNull);
      expect(sandbox.healthRecords, hasLength(1));
      final rec = sandbox.healthRecords.first;
      expect(rec.pluginId, 'crashy');
      expect(rec.hook, 'initialize');
      expect(rec.message, contains('boom'));
    });

    test('returns the operation result on success', () async {
      final sandbox = PluginSandbox();
      final value = await sandbox.run(
        pluginId: 'ok',
        pluginName: 'Ok',
        hook: 'test',
        operation: () async => 42,
      );
      expect(value, 42);
      expect(sandbox.healthRecords, isEmpty);
    });

    test('clearHealth empties the dashboard', () async {
      final sandbox = PluginSandbox();
      await sandbox.run(
        pluginId: 'x',
        pluginName: 'X',
        hook: 'h',
        operation: () async => throw Exception('fail'),
      );
      expect(sandbox.healthRecords, hasLength(1));
      sandbox.clearHealth();
      expect(sandbox.healthRecords, isEmpty);
    });

    test('abandons a hook that runs past its timeout and records it',
        () async {
      final sandbox = PluginSandbox();
      final result = await sandbox.run<int>(
        pluginId: 'slow',
        pluginName: 'Slow Plugin',
        hook: 'onLibraryScan',
        timeout: const Duration(milliseconds: 20),
        operation: () async {
          // Simulates a plugin hook stuck on a long/blocked await — e.g. a
          // hung network call — rather than a thrown exception.
          await Future.delayed(const Duration(seconds: 5));
          return 1;
        },
      );

      expect(result, isNull);
      expect(sandbox.healthRecords, hasLength(1));
      final rec = sandbox.healthRecords.first;
      expect(rec.pluginId, 'slow');
      expect(rec.hook, 'onLibraryScan');
      expect(rec.message, contains('Timed out'));
      expect(rec.reason, contains('too long'));
    });

    test('timeout: null waits indefinitely instead of using the default',
        () async {
      final sandbox = PluginSandbox();
      final value = await sandbox.run<int>(
        pluginId: 'patient',
        pluginName: 'Patient',
        hook: 'h',
        timeout: null,
        operation: () async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 7;
        },
      );
      expect(value, 7);
      expect(sandbox.healthRecords, isEmpty);
    });
  });

  group('PluginManifest', () {
    test('parses a valid manifest', () {
      const yaml = '''
id: lyrics_provider
name: Lyrics Provider
description: Fetches synced lyrics
version: 1.2.0
author: Jane
entrypoint: plugin.dart
hooks:
  - onTrackStart
permissions:
  - network
''';
      final m = PluginManifest.parse(yaml, sourceUrl: 'https://github.com/x/y');
      expect(m, isNotNull);
      expect(m!.id, 'lyrics_provider');
      expect(m.name, 'Lyrics Provider');
      expect(m.version, '1.2.0');
      expect(m.entrypoint, 'plugin.dart');
      expect(m.hooks, contains('onTrackStart'));
      expect(m.permissions, contains('network'));
    });

    test('returns null for invalid yaml', () {
      expect(PluginManifest.parse('not: [valid', sourceUrl: 'x'), isNull);
    });

    test('parses "provides" alongside "permissions" — the reverse '
        'direction, what the plugin supplies rather than what it needs',
        () {
      const yaml = '''
id: lyrics_provider
name: Lyrics Provider
version: 1.2.0
author: Jane
provides:
  - lyrics
''';
      final m = PluginManifest.parse(yaml, sourceUrl: 'x');
      expect(m!.provides, ['lyrics']);
    });

    test('"provides" defaults to empty when not declared', () {
      const yaml = '''
id: plain
name: Plain
version: 1.0.0
author: Jane
''';
      final m = PluginManifest.parse(yaml, sourceUrl: 'x');
      expect(m!.provides, isEmpty);
    });

    test('parses "dependencies" — other plugin ids this one needs '
        'installed (item 26)', () {
      const yaml = '''
id: enhanced_lyrics
name: Enhanced Lyrics
version: 1.0.0
author: Jane
dependencies:
  - lyrics_provider
  - network_helper
''';
      final m = PluginManifest.parse(yaml, sourceUrl: 'x');
      expect(m!.dependencies, ['lyrics_provider', 'network_helper']);
    });

    test('"dependencies" defaults to empty when not declared', () {
      const yaml = '''
id: plain
name: Plain
version: 1.0.0
author: Jane
''';
      final m = PluginManifest.parse(yaml, sourceUrl: 'x');
      expect(m!.dependencies, isEmpty);
    });
  });

  group('PluginRuntime (dart_eval)', () {
    test('executes a downloaded-style plugin and reads metadata', () {
      // dart_eval 0.8.3 supports returning Maps with primitive values.
      // Hooks are top-level functions declared in the 'hooks' list.
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'external_demo',
    'name': 'External Demo',
    'description': 'A plugin loaded at runtime',
    'version': '0.1.0',
    'author': 'Community',
    'hooks': ['onTrackStart', 'onLibraryScan'],
  };
}

dynamic onTrackStart(dynamic track) {
  return 'track_received';
}

dynamic onLibraryScan(dynamic file) {
  return 'scan_received';
}
''';
      final runtime = PluginRuntime.create(source);
      expect(runtime.id, 'external_demo');
      expect(runtime.name, 'External Demo');
      expect(runtime.version, '0.1.0');
      expect(runtime.author, 'Community');

      // Hooks are declared and callable.
      expect(runtime.hasHook('onTrackStart'), isTrue);
      expect(runtime.hasHook('onLibraryScan'), isTrue);
      expect(runtime.hasHook('uiSlot'), isFalse);

      // Hook execution works — the interpreter runs the top-level function.
      final result = runtime.callHook('onTrackStart', [
        {'title': 'Hello World'},
      ]);
      expect(result, 'track_received');

      final scanResult = runtime.callHook('onLibraryScan', ['/tmp/song.mp3']);
      expect(scanResult, 'scan_received');
    });

    test('throws PluginRuntimeException for invalid plugin', () {
      expect(
        () => PluginRuntime.create('this is not valid dart'),
        throwsA(isA<PluginRuntimeException>()),
      );
    });

    test(
        'sample_logger plugin.dart executes for real, including its uiSlot '
        'declarative-Map hook', () async {
      // Loads a local fixture mirroring the actual shipped example —
      // https://github.com/MrIvoe/Omnis-Plugins/blob/main/sample_logger/plugin.dart,
      // now published in its own repo rather than bundled in this one —
      // through the real dart_eval interpreter (not a hand-typed source
      // string) to prove the declarative uiSlot payload PluginSlotView
      // depends on (a downloaded plugin returning {'type': 'badge', ...}
      // instead of a real Widget) really executes, not just "looks right"
      // by inspection.
      final source = await File(p.join(
              'test', 'fixtures', 'sample_logger_plugin.dart.txt'))
          .readAsString();
      final runtime = PluginRuntime.create(source);

      expect(runtime.id, 'sample_logger');
      expect(runtime.hasHook('uiSlot'), isTrue);

      final overlay = runtime.callHook('uiSlot', ['now_playing_overlay']);
      expect(overlay, isA<Map>());
      expect((overlay as Map)['type'], 'badge');
      expect(overlay['text'], 'Sample Logger active');

      final elsewhere = runtime.callHook('uiSlot', ['settings_page']);
      expect(elsewhere, isNull);
    });

    group('sandbox bridge — loadLibraryTracks', () {
      late String tempDir;

      setUp(() async {
        tempDir =
            (await Directory.systemTemp.createTemp('omnis_plugin_bridge_test'))
                .path;
        PathProviderPlatform.instance = _FakePathProvider(tempDir);
        LibraryRepository.instance.resetForTesting();
      });

      test(
          'a plugin granted "library" permission can await '
          'loadLibraryTracks() and see real, current library data',
          () async {
        await LibraryRepository.instance.save([
          BaseTrack(
            id: 't1',
            title: 'Sunrise',
            artists: const ['Ava'],
            album: 'Morning',
            duration: 180,
            type: TrackType.local,
          ),
        ]);

        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'library_reader',
    'name': 'Library Reader',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) async {
  final tracks = await loadLibraryTracks();
  return {'count': tracks.length, 'firstTitle': tracks[0]['title']};
}
''';
        final runtime = PluginRuntime.create(source, declaredPermissions: [
          'library',
        ]);

        final raw = runtime.callHook('onTrackStart', [
          {'title': 'irrelevant'}
        ]);
        final result = raw is Future ? await raw : raw;

        expect(result, isA<Map>());
        expect((result as Map)['count'], 1);
        expect(result['firstTitle'], 'Sunrise');
      });

      test(
          'a plugin that did NOT declare "library" permission fails loud '
          "(callHook throws) rather than getting silent empty data — the "
          'permission check happens synchronously inside the bridge call, '
          'before the guest\'s own try/catch around the await ever runs, so '
          'this surfaces through PluginManager\'s existing sandbox/health '
          'path exactly like any other hook failure, not as a value the '
          'plugin can quietly swallow', () async {
        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'no_permission_reader',
    'name': 'No Permission Reader',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) async {
  final tracks = await loadLibraryTracks();
  return tracks.length;
}
''';
        // No declaredPermissions at all — 'library' not granted.
        final runtime = PluginRuntime.create(source);

        expect(
          () => runtime.callHook('onTrackStart', [
            {'title': 'irrelevant'}
          ]),
          throwsA(isA<PluginRuntimeException>().having(
            (e) => e.message,
            'message',
            contains("Permission 'omnis.library' denied"),
          )),
        );
      });
    });

    group('sandbox bridge — playback control', () {
      test(
          'a plugin granted "playback" can call play/pause/next/previous/'
          'seek and the real (fake, in test) context receives the calls',
          () async {
        final context = _RecordingPlaybackContext();
        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'transport_user',
    'name': 'Transport User',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) async {
  await playbackPlay();
  await playbackPause();
  final advanced = await playbackNext(false);
  final wentBack = await playbackPrevious();
  await playbackSeek(1500);
  return {'advanced': advanced, 'wentBack': wentBack};
}
''';
        final runtime = PluginRuntime.create(
          source,
          declaredPermissions: const ['playback'],
          getContext: () => context,
        );

        final raw = runtime.callHook('onTrackStart', [
          {'title': 'irrelevant'}
        ]);
        final result = raw is Future ? await raw : raw;

        expect(context.calls, [
          'play',
          'pause',
          'next:false',
          'previous',
          'seek:1500',
        ]);
        expect((result as Map)['advanced'], isTrue);
        expect(result['wentBack'], isTrue);
      });

      test(
          'a plugin without "playback" permission gets a permission error '
          'attempting transport control, not a silent no-op', () async {
        final context = _RecordingPlaybackContext();
        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'no_playback_permission',
    'name': 'No Playback Permission',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) async {
  await playbackPlay();
  return null;
}
''';
        // No 'playback' declared — only unrelated permissions granted.
        final runtime = PluginRuntime.create(
          source,
          declaredPermissions: const ['library'],
          getContext: () => context,
        );

        expect(
          () => runtime.callHook('onTrackStart', [
            {'title': 'irrelevant'}
          ]),
          throwsA(isA<PluginRuntimeException>().having(
            (e) => e.message,
            'message',
            contains("Permission 'omnis.playback' denied"),
          )),
        );
        expect(context.calls, isEmpty);
      });

      test(
          'read-only state (currentTrack/queue/isPlaying/currentIndex) '
          'works with just "library" permission — no "playback" needed',
          () async {
        final context = _RecordingPlaybackContext()
          ..currentTrack = BaseTrack(
            id: 't1',
            title: 'Sunrise',
            artists: const ['Ava'],
            album: 'Morning',
            duration: 180,
            type: TrackType.local,
          )
          ..queue = [
            BaseTrack(
              id: 't1',
              title: 'Sunrise',
              artists: const ['Ava'],
              album: 'Morning',
              duration: 180,
              type: TrackType.local,
            ),
          ]
          ..isPlaying = true
          ..currentIndex = 0;
        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'state_reader',
    'name': 'State Reader',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) {
  final current = getCurrentTrack();
  return {
    'title': current['title'],
    'queueLength': getQueue().length,
    'isPlaying': getIsPlaying(),
    'currentIndex': getCurrentIndex(),
  };
}
''';
        final runtime = PluginRuntime.create(
          source,
          declaredPermissions: const ['library'],
          getContext: () => context,
        );

        final raw = runtime.callHook('onTrackStart', [
          {'title': 'irrelevant'}
        ]);
        final result = raw is Future ? await raw : raw;

        expect((result as Map)['title'], 'Sunrise');
        expect(result['queueLength'], 1);
        expect(result['isPlaying'], isTrue);
        expect(result['currentIndex'], 0);
      });

      test(
          'loadPlaylists() is gated by "library" permission, the same as '
          'loadLibraryTracks()', () async {
        const source = '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {
    'id': 'no_permission_playlists',
    'name': 'No Permission Playlists',
    'version': '0.1.0',
    'author': 'test',
    'hooks': ['onTrackStart'],
  };
}

dynamic onTrackStart(dynamic track) async {
  final playlists = await loadPlaylists();
  return playlists.length;
}
''';
        final runtime = PluginRuntime.create(source);

        expect(
          () => runtime.callHook('onTrackStart', [
            {'title': 'irrelevant'}
          ]),
          throwsA(isA<PluginRuntimeException>().having(
            (e) => e.message,
            'message',
            contains("Permission 'omnis.library' denied"),
          )),
        );
      });
    });
  });

  group('In-process plugins (MusicPlugin)', () {
    test('recording plugin receives hook calls', () async {
      final plugin = _RecordingPlugin();
      await plugin.initialize();
      await plugin.onTrackStart(BaseTrack(
        id: '1',
        title: 'Test Song',
        artists: const ['Test'],
        album: 'Test',
        duration: 100,
        type: TrackType.local,
      ));
      await plugin.onLibraryScan('/tmp/file.mp3');
      await plugin.dispose();
      expect(plugin.calls,
          ['init', 'track:Test Song', 'scan:/tmp/file.mp3', 'dispose']);
    });
  });

  group('Plugin manager local install', () {
    test('can install and register a plugin from a local directory', () async {
      final tempRoot = await Directory.systemTemp.createTemp('omnis_local_plugin');
      addTearDown(() async => tempRoot.delete(recursive: true));

      final pluginDir = Directory(p.join(tempRoot.path, 'hello_world_plugin'));
      await pluginDir.create(recursive: true);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: hello_world
name: Hello World
description: A simple hello plugin
version: 1.0.0
author: Test
entrypoint: plugin.dart
hooks:
  - onTrackStart
permissions:
  - settings
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'hello_world',
    'name': 'Hello World',
    'description': 'A simple hello plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': ['onTrackStart'],
    'permissions': ['settings'],
  };
}

dynamic onTrackStart(dynamic track) {
  return 'hello';
}
''');

      final manager = PluginManager();
      final managed = await manager.installFromPath(pluginDir.path, sourceUrl: 'local');

      expect(managed.id, 'hello_world');
      expect(manager.plugins.any((plugin) => plugin.id == 'hello_world'), isTrue);
      expect(manager.plugins.singleWhere((plugin) => plugin.id == 'hello_world').enabled, isTrue);
    });
  });

  group('Plugin dependency resolution (item 26)', () {
    /// Writes a minimal external-plugin directory declaring [dependsOn]
    /// in its manifest — the local counterpart to `writeEventPlugin`
    /// above, which has no `dependencies:` slot.
    Future<Directory> writeDependentPlugin(
      String tempRoot,
      String dirName, {
      List<String> dependsOn = const [],
    }) async {
      final pluginDir = Directory(p.join(tempRoot, dirName));
      await pluginDir.create(recursive: true);
      final depsYaml =
          dependsOn.isEmpty ? '' : dependsOn.map((d) => '  - $d').join('\n');
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: $dirName
name: $dirName
description: Test plugin
version: 1.0.0
author: Test
entrypoint: plugin.dart
${dependsOn.isEmpty ? '' : 'dependencies:\n$depsYaml'}
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': '$dirName',
    'name': '$dirName',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': [],
  };
}
''');
      return pluginDir;
    }

    test('installing a plugin whose dependency is not yet installed '
        'fails with a message naming the missing dependency, rather '
        'than installing into a broken state', () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_dep_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeDependentPlugin(tempRoot, 'dependent',
          dependsOn: ['base_plugin']);
      final manager = PluginManager();

      await expectLater(
        manager.installFromPath(dir.path, sourceUrl: 'local'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('base_plugin'), contains('dependent')),
        )),
      );
      expect(manager.byId('dependent'), isNull);
    });

    test('installing a plugin whose dependency is already installed '
        'succeeds', () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_dep_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final baseDir = await writeDependentPlugin(tempRoot, 'base_plugin');
      final dependentDir = await writeDependentPlugin(tempRoot, 'dependent',
          dependsOn: ['base_plugin']);
      final manager = PluginManager();

      await manager.installFromPath(baseDir.path, sourceUrl: 'local');
      final managed =
          await manager.installFromPath(dependentDir.path, sourceUrl: 'local');

      expect(managed.id, 'dependent');
      expect(manager.byId('dependent'), isNotNull);
    });

    test('missingDependenciesFor detects a dependency that was later '
        'uninstalled — item 26\'s "detection of a dependency '
        'disappearing" gap, not just a one-time install-time gate',
        () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_dep_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final baseDir = await writeDependentPlugin(tempRoot, 'base_plugin');
      final dependentDir = await writeDependentPlugin(tempRoot, 'dependent',
          dependsOn: ['base_plugin']);
      final manager = PluginManager();

      await manager.installFromPath(baseDir.path, sourceUrl: 'local');
      await manager.installFromPath(dependentDir.path, sourceUrl: 'local');
      final dependent = manager.byId('dependent')!;
      expect(manager.missingDependenciesFor(dependent), isEmpty);

      await manager.uninstallPlugin(manager.byId('base_plugin')!);

      expect(manager.missingDependenciesFor(dependent), ['base_plugin']);
    });

    test('missingDependenciesFor is empty for a plugin that declares no '
        'dependencies', () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_dep_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeDependentPlugin(tempRoot, 'standalone');
      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      expect(
        manager.missingDependenciesFor(manager.byId('standalone')!),
        isEmpty,
      );
    });
  });

  group('PluginManager event forwarding', () {
    test(
        'emitting FavoriteChangedEvent forwards to an enabled external '
        'plugin that declared "events" permission and an onPluginEvent hook',
        () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_event_fwd_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'event_listener',
        permissions: ['events'],
        hooks: ['onPluginEvent', 'getLastEvent'],
        extraSource: '''
class EventHolder {
  dynamic value;
}

final holder = EventHolder();

dynamic onPluginEvent(dynamic event) {
  holder.value = event;
  return null;
}

dynamic getLastEvent(dynamic arg) {
  return holder.value;
}
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      manager.events.emit(const FavoriteChangedEvent('track42', true));
      // The listener fires asynchronously off the event stream — this is
      // a plain test() (no fake-async binding), so a real microtask/event
      // turn is enough to let it actually run.
      await Future.delayed(Duration.zero);

      final plugin = manager.byId('event_listener')!;
      final received = plugin.external!.callHook('getLastEvent', [null]);

      expect(received, isA<Map>());
      expect((received as Map)['type'], 'FavoriteChanged');
      expect(received['trackId'], 'track42');
      expect(received['isFavorite'], isTrue);
    });

    test(
        'a plugin that did NOT declare "events" permission never receives '
        'forwarded events, even with a matching onPluginEvent hook',
        () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_event_fwd_denied_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'no_events_permission',
        permissions: [],
        hooks: ['onPluginEvent', 'getLastEvent'],
        extraSource: '''
class EventHolder {
  dynamic value;
}

final holder = EventHolder();

dynamic onPluginEvent(dynamic event) {
  holder.value = event;
  return null;
}

dynamic getLastEvent(dynamic arg) {
  return holder.value;
}
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      manager.events.emit(const FavoriteChangedEvent('track42', true));
      await Future.delayed(Duration.zero);

      final plugin = manager.byId('no_events_permission')!;
      final received = plugin.external!.callHook('getLastEvent', [null]);

      expect(received, isNull);
    });

    test('a plugin without an onPluginEvent hook is skipped without error',
        () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_event_fwd_no_hook_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'no_hook',
        permissions: ['events'],
        hooks: ['onTrackStart'],
        extraSource: '''
dynamic onTrackStart(dynamic track) => null;
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      expect(
        () => manager.events.emit(const FavoriteChangedEvent('t', true)),
        returnsNormally,
      );
    });
  });

  group('PluginManager.uiSlot — plugin id stamping', () {
    test(
        'an external plugin\'s Map result gets stamped with its real '
        '_pluginId, clobbering any guest-supplied value', () async {
      final tempRoot =
          (await Directory.systemTemp.createTemp('omnis_stamp_test')).path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'spoofer',
        permissions: const [],
        hooks: const ['uiSlot'],
        extraSource: '''
dynamic uiSlot(dynamic locationId) {
  return {'type': 'button', 'text': 'Go', 'hook': 'h', '_pluginId': 'not-me'};
}
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      final items = await manager.uiSlot('now_playing_overlay');

      expect(items, hasLength(1));
      expect((items.single as Map)['_pluginId'], 'spoofer');
    });
  });

  group('PluginManager.callPluginHook', () {
    test('invokes the declared hook on the named external plugin and '
        'emits on changes', () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_call_hook_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'toggle_plugin',
        permissions: const [],
        hooks: const ['onToggle', 'getState'],
        extraSource: '''
class StateHolder {
  dynamic value = false;
}

final state = StateHolder();

dynamic onToggle(dynamic newValue) {
  state.value = newValue;
  return null;
}

dynamic getState(dynamic arg) {
  return state.value;
}
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      var changeEvents = 0;
      manager.changes.listen((_) => changeEvents++);

      await manager.callPluginHook('toggle_plugin', 'onToggle', [true]);
      // StreamController delivers to listeners via a microtask, not
      // synchronously on .add() — give it a turn before checking.
      await Future.delayed(Duration.zero);

      final plugin = manager.byId('toggle_plugin')!;
      expect(plugin.external!.callHook('getState', [null]), isTrue);
      // At least one — install itself also emits, this just proves
      // callPluginHook adds its own on top rather than being silent.
      expect(changeEvents, greaterThan(0));
    });

    test('a hook the plugin never declared is silently skipped, not an '
        'error', () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_call_hook_missing_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final dir = await writeEventPlugin(
        tempRoot,
        'no_such_hook',
        permissions: const [],
        hooks: const ['onTrackStart'],
        extraSource: '''
dynamic onTrackStart(dynamic track) => null;
''',
      );

      final manager = PluginManager();
      await manager.installFromPath(dir.path, sourceUrl: 'local');

      expect(
        () => manager.callPluginHook('no_such_hook', 'notDeclared', []),
        returnsNormally,
      );
    });

    test('an unknown plugin id is silently skipped, not an error', () async {
      final manager = PluginManager();
      expect(
        () => manager.callPluginHook('does_not_exist', 'anyHook', []),
        returnsNormally,
      );
    });

    test('is a no-op for a bundled (in-process) plugin — no dynamic '
        'dispatch mechanism exists for one', () async {
      final manager = PluginManager();
      manager.register(_RecordingPlugin());

      expect(
        () => manager.callPluginHook('recorder', 'uiSlot', []),
        returnsNormally,
      );
    });
  });

  group('SandboxedLyricsProvider / SandboxedQueueBuilder (unit)', () {
    test('SandboxedLyricsProvider forwards to provideLyrics and returns '
        'its result', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'lyrics_test',
    'name': 'Lyrics Test',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['provideLyrics'],
  };
}

dynamic provideLyrics(dynamic track, dynamic positionMs) {
  return 'La la la at \$positionMs ms for \${track['title']}';
}
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedLyricsProvider(runtime);
      final track = BaseTrack(
        id: 't1',
        title: 'Sunrise',
        artists: const ['Ava'],
        album: 'Morning',
        duration: 180,
        type: TrackType.local,
      );

      final lyric =
          provider.currentLyricFor(track, const Duration(seconds: 5));

      expect(lyric, 'La la la at 5000 ms for Sunrise');
    });

    test('SandboxedLyricsProvider degrades to the safe default when the '
        'hook throws or returns something unexpected', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'lyrics_broken',
    'name': 'Lyrics Broken',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['provideLyrics'],
  };
}

dynamic provideLyrics(dynamic track, dynamic positionMs) {
  throw 'boom';
}
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedLyricsProvider(runtime);
      final track = BaseTrack(
        id: 't1',
        title: 'Sunrise',
        artists: const ['Ava'],
        album: 'Morning',
        duration: 180,
        type: TrackType.local,
      );

      final lyric = provider.currentLyricFor(track, Duration.zero);

      expect(lyric, 'No lyrics added for this track yet.');
    });

    test('SandboxedQueueBuilder forwards to buildQueueFor and parses the '
        'returned tracks', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'queue_test',
    'name': 'Queue Test',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['queueBuilderSupportedQueries', 'buildQueueFor'],
  };
}

dynamic queueBuilderSupportedQueries() {
  return ['chill'];
}

dynamic buildQueueFor(dynamic tracks, dynamic query) {
  return [
    {
      'id': 'picked',
      'title': 'Picked Track',
      'artists': ['Someone'],
      'album': 'An Album',
      'duration': 100,
      'genres': [],
      'type': 'local',
    }
  ];
}
''';
      final runtime = PluginRuntime.create(source);
      final queries = SandboxedQueueBuilder.fetchSupportedQueries(runtime);
      final builder = SandboxedQueueBuilder(runtime, queries);

      expect(builder.supportedQueries, ['chill']);
      final result = builder.buildQueueFor(const [], 'chill');
      expect(result, hasLength(1));
      expect(result.single.title, 'Picked Track');
    });

    test('SandboxedQueueBuilder degrades to an empty list on failure', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'queue_broken',
    'name': 'Queue Broken',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['queueBuilderSupportedQueries', 'buildQueueFor'],
  };
}

dynamic queueBuilderSupportedQueries() {
  return ['chill'];
}

dynamic buildQueueFor(dynamic tracks, dynamic query) {
  throw 'boom';
}
''';
      final runtime = PluginRuntime.create(source);
      final builder = SandboxedQueueBuilder(runtime, const ['chill']);

      expect(builder.buildQueueFor(const [], 'chill'), isEmpty);
    });

    test('SandboxedPlayHistoryProvider forwards to all three hooks and '
        'parses their results', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'history_test',
    'name': 'History Test',
    'version': '1.0.0',
    'author': 'test',
    'hooks': [
      'playHistoryRecentlyPlayed',
      'playHistoryMostPlayedIds',
      'playHistoryPlayCountFor',
    ],
  };
}

dynamic playHistoryRecentlyPlayed(dynamic limit) {
  return [
    {
      'trackId': 't1',
      'title': 'Song One',
      'artist': 'Artist',
      'playedAtMs': 1000,
    }
  ];
}

dynamic playHistoryMostPlayedIds(dynamic limit) {
  return [
    ['t1', 5],
    ['t2', 3],
  ];
}

dynamic playHistoryPlayCountFor(dynamic trackId) {
  return trackId == 't1' ? 5 : 0;
}
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedPlayHistoryProvider(runtime);

      final recent = provider.recentlyPlayed(limit: 10);
      expect(recent, hasLength(1));
      expect(recent.single.trackId, 't1');
      expect(recent.single.title, 'Song One');

      final mostPlayed = provider.mostPlayedIds(limit: 10);
      expect(mostPlayed.map((e) => e.key), ['t1', 't2']);
      expect(mostPlayed.map((e) => e.value), [5, 3]);

      expect(provider.playCountFor('t1'), 5);
      expect(provider.playCountFor('t2'), 0);
    });

    test('SandboxedPlayHistoryProvider degrades to empty/zero when a hook '
        'throws', () {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'history_broken',
    'name': 'History Broken',
    'version': '1.0.0',
    'author': 'test',
    'hooks': [
      'playHistoryRecentlyPlayed',
      'playHistoryMostPlayedIds',
      'playHistoryPlayCountFor',
    ],
  };
}

dynamic playHistoryRecentlyPlayed(dynamic limit) => throw 'boom';
dynamic playHistoryMostPlayedIds(dynamic limit) => throw 'boom';
dynamic playHistoryPlayCountFor(dynamic trackId) => throw 'boom';
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedPlayHistoryProvider(runtime);

      expect(provider.recentlyPlayed(), isEmpty);
      expect(provider.mostPlayedIds(), isEmpty);
      expect(provider.playCountFor('t1'), 0);
    });

    test('SandboxedArtistImageProvider forwards to artistImageUrlFor and '
        'returns its result', () async {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'artist_image_test',
    'name': 'Artist Image Test',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['artistImageUrlFor'],
  };
}

dynamic artistImageUrlFor(dynamic artistName) =>
    'https://example.com/\$artistName.jpg';
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedArtistImageProvider(runtime);

      expect(provider.isAvailable, isTrue);
      final url = await provider.imageUrlFor('queen');
      expect(url, 'https://example.com/queen.jpg');
    });

    test('SandboxedArtistImageProvider degrades to null when the hook '
        'throws or returns something unexpected', () async {
      const source = '''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'artist_image_broken',
    'name': 'Artist Image Broken',
    'version': '1.0.0',
    'author': 'test',
    'hooks': ['artistImageUrlFor'],
  };
}

dynamic artistImageUrlFor(dynamic artistName) => throw 'boom';
''';
      final runtime = PluginRuntime.create(source);
      final provider = SandboxedArtistImageProvider(runtime);

      expect(await provider.imageUrlFor('queen'), isNull);
    });
  });

  group('PluginManager — service registration (provides:)', () {
    test(
        'a plugin declaring provides: [lyrics] with a matching hook is '
        'registered under ILyricsProvider', () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_provides_lyrics_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final pluginDir = Directory(p.join(tempRoot, 'lyrics_plugin'));
      await pluginDir.create(recursive: true);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: lyrics_plugin
name: Lyrics Plugin
description: Test
version: 1.0.0
author: Test
entrypoint: plugin.dart
provides:
  - lyrics
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'lyrics_plugin',
    'name': 'Lyrics Plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': ['provideLyrics'],
  };
}

dynamic provideLyrics(dynamic track, dynamic positionMs) => 'sandboxed lyric';
''');

      final manager = PluginManager();
      await manager.installFromPath(pluginDir.path, sourceUrl: 'local');

      final provider = manager.services.get<ILyricsProvider>();
      expect(provider, isNotNull);
      final track = BaseTrack(
        id: 't1',
        title: 'X',
        artists: const ['Y'],
        album: 'Z',
        duration: 100,
        type: TrackType.local,
      );
      expect(provider!.currentLyricFor(track, Duration.zero),
          'sandboxed lyric');
    });

    test(
        'a plugin declaring provides: [play_history] with matching hooks '
        'is registered under IPlayHistoryProvider — proves the end-to-end '
        'manifest -> registration -> ServiceRegistry pipeline works for a '
        'capability added after lyrics/queue_builder, not just those two',
        () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_provides_history_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final pluginDir = Directory(p.join(tempRoot, 'history_plugin'));
      await pluginDir.create(recursive: true);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: history_plugin
name: History Plugin
description: Test
version: 1.0.0
author: Test
entrypoint: plugin.dart
provides:
  - play_history
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'history_plugin',
    'name': 'History Plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': [
      'playHistoryRecentlyPlayed',
      'playHistoryMostPlayedIds',
      'playHistoryPlayCountFor',
    ],
  };
}

dynamic playHistoryRecentlyPlayed(dynamic limit) => [];
dynamic playHistoryMostPlayedIds(dynamic limit) => [];
dynamic playHistoryPlayCountFor(dynamic trackId) => 7;
''');

      final manager = PluginManager();
      await manager.installFromPath(pluginDir.path, sourceUrl: 'local');

      final provider = manager.services.get<IPlayHistoryProvider>();
      expect(provider, isNotNull);
      expect(provider!.playCountFor('anything'), 7);
    });

    test(
        'a manifest claiming provides: [lyrics] without the matching hook '
        'is never registered', () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_provides_no_hook_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final pluginDir = Directory(p.join(tempRoot, 'fake_lyrics_plugin'));
      await pluginDir.create(recursive: true);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: fake_lyrics_plugin
name: Fake Lyrics Plugin
description: Test
version: 1.0.0
author: Test
entrypoint: plugin.dart
provides:
  - lyrics
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'fake_lyrics_plugin',
    'name': 'Fake Lyrics Plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': [],
  };
}
''');

      final manager = PluginManager();
      await manager.installFromPath(pluginDir.path, sourceUrl: 'local');

      expect(manager.services.get<ILyricsProvider>(), isNull);
    });

    test('disabling the plugin unregisters its service; re-enabling '
        're-registers it', () async {
      final tempRoot = (await Directory.systemTemp
              .createTemp('omnis_provides_disable_test'))
          .path;
      addTearDown(() => Directory(tempRoot).delete(recursive: true));

      final pluginDir = Directory(p.join(tempRoot, 'toggle_lyrics_plugin'));
      await pluginDir.create(recursive: true);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: toggle_lyrics_plugin
name: Toggle Lyrics Plugin
description: Test
version: 1.0.0
author: Test
entrypoint: plugin.dart
provides:
  - lyrics
''');
      await File(p.join(pluginDir.path, 'plugin.dart')).writeAsString('''
dynamic createPlugin(dynamic api) {
  return {
    'id': 'toggle_lyrics_plugin',
    'name': 'Toggle Lyrics Plugin',
    'version': '1.0.0',
    'author': 'Test',
    'hooks': ['provideLyrics'],
  };
}

dynamic provideLyrics(dynamic track, dynamic positionMs) => 'x';
''');

      final manager = PluginManager();
      final managed =
          await manager.installFromPath(pluginDir.path, sourceUrl: 'local');
      expect(manager.services.get<ILyricsProvider>(), isNotNull);

      await manager.disablePlugin(managed);
      expect(manager.services.get<ILyricsProvider>(), isNull);

      await manager.enablePlugin(managed);
      expect(manager.services.get<ILyricsProvider>(), isNotNull);
    });
  });

  group('BaseTrack unified schema', () {
    test('local and streaming tracks share the same object', () {
      final local = BaseTrack(
        id: '1',
        title: 'Local Song',
        artists: const ['A'],
        album: 'Album',
        duration: 1000,
        type: TrackType.local,
        localPath: '/tmp/song.mp3',
      );
      final stream = BaseTrack(
        id: '2',
        title: 'Stream Song',
        artists: const ['B'],
        album: 'Album',
        duration: 2000,
        type: TrackType.youtube,
        streamUrl: 'https://example.com/stream',
      );

      expect(local.type, TrackType.local);
      expect(stream.type, TrackType.youtube);
      expect(stream.streamUrl, isNotNull);
      expect(local.localPath, isNotNull);

      // JSON round-trip works for both.
      final restored = BaseTrack.fromJson(stream.toJson());
      expect(restored.title, 'Stream Song');
      expect(restored.type, TrackType.youtube);
    });

    test('audio-format fields (codec/sampleRateHz/bitDepth/bitrateKbps/'
        'channels) round-trip through JSON', () {
      final track = BaseTrack(
        id: '3',
        title: 'Lossless Song',
        artists: const ['C'],
        album: 'Album',
        duration: 300,
        type: TrackType.local,
        localPath: '/tmp/song.flac',
        codec: 'FLAC',
        sampleRateHz: 96000,
        bitDepth: 24,
        bitrateKbps: 2304,
        channels: 2,
      );

      final restored = BaseTrack.fromJson(track.toJson());

      expect(restored.codec, 'FLAC');
      expect(restored.sampleRateHz, 96000);
      expect(restored.bitDepth, 24);
      expect(restored.bitrateKbps, 2304);
      expect(restored.channels, 2);
      // Not `expect(restored, track)`: BaseTrack's `==` compares list
      // fields (artists/genres) with plain `==`, which Dart's List
      // doesn't override for content equality — a pre-existing gap this
      // test isn't the place to fix, so it checks scalar fields instead,
      // matching the pattern the test above already uses.
      expect(restored.id, track.id);
      expect(restored.title, track.title);
    });

    test('audio-format fields decode as null from JSON written before '
        'they existed — an additive field, not a breaking one', () {
      final legacyJson = {
        'id': '4',
        'title': 'Old Scan',
        'artists': ['D'],
        'album': 'Album',
        'duration': 180,
        'genres': [],
        'type': 'local',
        'localPath': '/tmp/old.mp3',
        // No codec/sampleRateHz/bitDepth/bitrateKbps/channels keys at all.
      };

      final restored = BaseTrack.fromJson(legacyJson);

      expect(restored.codec, isNull);
      expect(restored.sampleRateHz, isNull);
      expect(restored.bitDepth, isNull);
      expect(restored.bitrateKbps, isNull);
      expect(restored.channels, isNull);
    });
  });
}
