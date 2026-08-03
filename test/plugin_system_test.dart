import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:path/path.dart' as p;

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

void main() {
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
  });
}
