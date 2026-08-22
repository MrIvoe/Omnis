import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugin_api/event_bus.dart';
import 'package:omnis_plugin_api/repeat_mode.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same fake path_provider `plugin_system_test.dart` uses — the scoped
/// storage bridge goes through the real `PluginStorage`/`SharedPreferences`
/// path, and `setMockInitialValues` alone is enough for that; this is only
/// here because `PluginManager`'s wider install path also touches
/// `getApplicationDocumentsPath` for other plugins in the same file.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Records every mutating call the queue/volume/gain/repeat/shuffle/event
/// bridge functions can make, and backs the ones that need a real return
/// value (volume, events) with a real value instead of a bare recording —
/// the same "only stub what's actually exercised, noSuchMethod the rest"
/// pattern `plugin_system_test.dart`'s `_RecordingPlaybackContext` uses.
class _RecordingContext implements PluginContext {
  final List<String> calls = [];
  final EventBus _events = EventBus();

  @override
  EventBus get events => _events;

  @override
  double volume = 0.5;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    calls.add('setQueue:${tracks.length}:$startIndex');
  }

  @override
  Future<void> addTrack(BaseTrack track) async {
    calls.add('addTrack:${track.id}');
  }

  @override
  Future<void> playNext(BaseTrack track) async {
    calls.add('playNext:${track.id}');
  }

  @override
  Future<void> removeTrack(int index) async {
    calls.add('removeTrack:$index');
  }

  @override
  Future<void> playAt(int index) async {
    calls.add('playAt:$index');
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    calls.add('setVolume:$volume');
  }

  @override
  Future<void> setGain(String source, double multiplier) async {
    calls.add('setGain:$source:$multiplier');
  }

  @override
  Future<void> clearGain(String source) async {
    calls.add('clearGain:$source');
  }

  @override
  Future<void> setRepeatMode(RepeatMode mode) async {
    calls.add('setRepeatMode:${mode.name}');
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    calls.add('setShuffleEnabled:$enabled');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProvider(Directory.systemTemp.path);
  });

  // Every guest source below routes its argument values through `arg`
  // (the hook's own host-supplied parameter) rather than writing them as
  // Dart literals inline in the guest source. That's not incidental
  // style — dart_eval 0.8.3 has a real compiler bug where boxing a fresh
  // String/Map/List *literal constant* inside an async function's body,
  // once already past an `await`, crashes the interpreter
  // (`BoxString`/`BoxList` "type 'Null' is not a subtype" deep inside
  // dart_eval's own bytecode ops) — reproduced here in isolation against
  // bare dart_eval with no Omnis code involved, and confirmed to affect
  // *any* literal in that position, not anything specific to the new
  // bridge functions this file tests. Indexing into an existing runtime
  // `$Value` (like `arg['key']`) takes a different, unaffected bytecode
  // path — the same pattern the pre-existing httpGet tests already use
  // (`track['url'] as String`, never a bare string literal). See
  // docs/PLUGIN_GUIDE.md's sandbox section for the plugin-author-facing
  // version of this warning.
  group('Queue mutation bridge (queue permission)', () {
    test('setQueue is denied without the queue permission', () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';
dynamic createPlugin(dynamic api) {
  return {'id': 'q', 'name': 'q', 'hooks': ['run']};
}
dynamic run(dynamic arg) async {
  await setQueue(arg['tracks'], arg['startIndex']);
  return 'ok';
}
''',
        declaredPermissions: const [],
        getContext: () => context,
      );
      expect(
        () => runtime.callHook('run', [
          {'tracks': [], 'startIndex': 0}
        ]),
        throwsA(isA<PluginRuntimeException>().having(
          (e) => e.message,
          'message',
          contains("Permission 'omnis.queue' denied"),
        )),
      );
    });

    test('setQueue/addTrack/playNext/removeTrackAt/playAt forward to context',
        () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'q', 'name': 'q', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  await setQueue(arg['queue'], arg['startIndex']);
  await addTrack(arg['trackB']);
  await playNextTrack(arg['trackC']);
  await removeTrackAt(arg['removeIndex']);
  await playAt(arg['playIndex']);
  return 'done';
}
''',
        declaredPermissions: const ['queue'],
        getContext: () => context,
      );

      Map<String, dynamic> track(String id) => {
            'id': id,
            'title': id,
            'artists': ['x'],
            'genres': const [],
            'album': 'al',
            'duration': 1,
            'type': 'local',
            'localPath': '/$id.mp3',
          };

      final result = runtime.callHook('run', [
        {
          'queue': [track('a')],
          'startIndex': 0,
          'trackB': track('b'),
          'trackC': track('c'),
          'removeIndex': 2,
          'playIndex': 0,
        }
      ]);
      expect(result, isA<Future>());
      return (result as Future).then((_) {
        expect(context.calls, [
          'setQueue:1:0',
          'addTrack:b',
          'playNext:c',
          'removeTrack:2',
          'playAt:0',
        ]);
      });
    });
  });

  group('Volume/gain bridge (volume permission)', () {
    test('getVolume/setVolume/setGain/clearGain forward to context, gain '
        'keyed by the plugin\'s own id', () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'replay_gain_test', 'name': 'g', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  final v = getVolume();
  await setVolume(arg['volume']);
  await setGain(arg['multiplier']);
  await clearGain();
  return v;
}
''',
        declaredPermissions: const ['volume'],
        getContext: () => context,
      );

      final result = runtime.callHook('run', [
        {'volume': 0.75, 'multiplier': 1.5}
      ]);
      expect(result, isA<Future>());
      return (result as Future).then((v) {
        expect(v, 0.5);
        expect(context.calls, [
          'setVolume:0.75',
          'setGain:replay_gain_test:1.5',
          'clearGain:replay_gain_test',
        ]);
      });
    });
  });

  group('Repeat/shuffle bridge (playback permission)', () {
    test('setRepeatMode parses the mode name and setShuffleEnabled forwards',
        () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 's', 'name': 's', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  await setRepeatMode(arg['mode']);
  await setShuffleEnabled(arg['enabled']);
  return 'ok';
}
''',
        declaredPermissions: const ['playback'],
        getContext: () => context,
      );

      final result = runtime.callHook('run', [
        {'mode': 'one', 'enabled': true}
      ]);
      expect(result, isA<Future>());
      return (result as Future).then((_) {
        expect(context.calls, ['setRepeatMode:one', 'setShuffleEnabled:true']);
      });
    });

    test('setRepeatMode throws on an unknown mode name', () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 's', 'name': 's', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  await setRepeatMode(arg['mode']);
  return 'ok';
}
''',
        declaredPermissions: const ['playback'],
        getContext: () => context,
      );

      expect(
        () => runtime.callHook('run', [
          {'mode': 'nonsense'}
        ]),
        throwsA(isA<PluginRuntimeException>().having(
          (e) => e.message,
          'message',
          contains('unknown mode "nonsense"'),
        )),
      );
    });
  });

  group('Scoped plugin storage bridge (state permission)', () {
    test('set then get round-trips a String value, namespaced by plugin id',
        () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'storage_test_plugin', 'name': 's', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  await pluginStorageSetString(arg['key'], arg['value']);
  return await pluginStorageGetString(arg['key']);
}
''',
        declaredPermissions: const ['state'],
        getContext: () => context,
      );

      final result = runtime.callHook('run', [
        {'key': 'greeting', 'value': 'hello'}
      ]);
      expect(result, isA<Future>());
      return (result as Future).then((v) => expect(v, 'hello'));
    });

    test('storage functions are denied without the state permission', () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'storage_test_plugin_2', 'name': 's', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  return await pluginStorageGetString(arg['key']);
}
''',
        declaredPermissions: const [],
        getContext: () => context,
      );

      expect(
        () => runtime.callHook('run', [
          {'key': 'x'}
        ]),
        throwsA(isA<PluginRuntimeException>().having(
          (e) => e.message,
          'message',
          contains("Permission 'omnis.state' denied"),
        )),
      );
    });
  });

  group('Outbound event emission (events permission)', () {
    test('emitEvent("favorite_changed", ...) emits a real FavoriteChangedEvent',
        () async {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'e', 'name': 'e', 'hooks': ['run']};
}

dynamic run(dynamic arg) async {
  emitEvent(arg['type'], arg['data']);
  return 'ok';
}
''',
        declaredPermissions: const ['events'],
        getContext: () => context,
      );

      final future = context.events.on<FavoriteChangedEvent>().first;
      runtime.callHook('run', [
        {
          'type': 'favorite_changed',
          'data': {'trackId': 't1', 'isFavorite': true},
        }
      ]);
      final event = await future;
      expect(event.trackId, 't1');
      expect(event.isFavorite, true);
    });

    test('emitEvent is denied without the events permission', () {
      final context = _RecordingContext();
      final runtime = PluginRuntime.create(
        '''
import 'package:omnis/sandbox_api.dart';

dynamic createPlugin(dynamic api) {
  return {'id': 'e2', 'name': 'e2', 'hooks': ['run']};
}

dynamic run(dynamic arg) {
  emitEvent('favorite_changed', {'trackId': 't1', 'isFavorite': true});
  return 'ok';
}
''',
        declaredPermissions: const [],
        getContext: () => context,
      );

      expect(() => runtime.callHook('run', const []), throwsA(anything));
    });
  });

  group('New provides: ServiceRegistry adapters', () {
    late PluginManager manager;

    setUp(() {
      manager = PluginManager();
    });

    Future<Directory> writeProvidesPlugin(
      String tempRoot,
      String dirName, {
      required List<String> provides,
      required List<String> hooks,
      required String extraSource,
    }) async {
      final pluginDir = Directory(p.join(tempRoot, dirName));
      await pluginDir.create(recursive: true);
      final providesYaml = provides.map((c) => '  - $c').join('\n');
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml')).writeAsString('''
id: $dirName
name: $dirName
description: Test plugin
version: 1.0.0
author: Test
entrypoint: plugin.dart
provides:
$providesYaml
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

    test('favorites: registers IFavoritesProvider from the declared hooks',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dir = await writeProvidesPlugin(
        tempDir.path,
        'fav_plugin',
        provides: const ['favorites'],
        hooks: const ['favoritesIsFavorite', 'favoritesFavoriteIds'],
        extraSource: '''
dynamic favoritesIsFavorite(dynamic trackId) => trackId == 't1';
dynamic favoritesFavoriteIds() => ['t1', 't2'];
''',
      );

      await manager.installFromPath(dir.path, sourceUrl: 'local');
      final provider = manager.services.get<IFavoritesProvider>();
      expect(provider, isNotNull);
      expect(provider!.isFavorite('t1'), true);
      expect(provider.isFavorite('other'), false);
      expect(provider.favoriteIds(), ['t1', 't2']);
    });

    test('ratings: registers IRatingsProvider', () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dir = await writeProvidesPlugin(
        tempDir.path,
        'ratings_plugin',
        provides: const ['ratings'],
        hooks: const ['ratingsRatingOf'],
        extraSource: "dynamic ratingsRatingOf(dynamic trackId) => 4;",
      );

      await manager.installFromPath(dir.path, sourceUrl: 'local');
      final provider = manager.services.get<IRatingsProvider>();
      expect(provider!.ratingOf('anything'), 4);
    });

    test('thumbs: registers IThumbsProvider, degrading to none on a bad value',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dir = await writeProvidesPlugin(
        tempDir.path,
        'thumbs_plugin',
        provides: const ['thumbs'],
        hooks: const ['thumbsThumbOf'],
        extraSource: "dynamic thumbsThumbOf(dynamic trackId) => 'up';",
      );

      await manager.installFromPath(dir.path, sourceUrl: 'local');
      final provider = manager.services.get<IThumbsProvider>();
      expect(provider!.thumbOf('t1'), ThumbState.up);
    });

    test(
        'online_search: registers IOnlineSearchProvider, using the plugin '
        'name and awaiting an async search hook', () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dir = await writeProvidesPlugin(
        tempDir.path,
        'search_plugin',
        provides: const ['online_search'],
        hooks: const ['onlineSearchIsConfigured', 'onlineSearchSearch'],
        extraSource: '''
dynamic onlineSearchIsConfigured() => true;
dynamic onlineSearchSearch(dynamic query, dynamic limit) async {
  return [
    {'id': 'r1', 'title': 'Result for \$query', 'artists': ['x'], 'genres': [], 'album': 'al', 'duration': 1, 'type': 'local', 'localPath': '/r1.mp3'}
  ];
}
''',
      );

      await manager.installFromPath(dir.path, sourceUrl: 'local');
      final provider = manager.services.get<IOnlineSearchProvider>();
      expect(provider!.providerName, 'search_plugin');
      expect(provider.isConfigured, true);
      final results = await provider.search('abc');
      expect(results, hasLength(1));
      expect(results.first.title, 'Result for abc');
    });

    test('a manifest claiming a provides: capability without the matching '
        'hook is never registered', () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dir = await writeProvidesPlugin(
        tempDir.path,
        'half_broken_plugin',
        provides: const ['favorites'],
        hooks: const [],
        extraSource: '',
      );

      await manager.installFromPath(dir.path, sourceUrl: 'local');
      expect(manager.services.has<IFavoritesProvider>(), false);
    });
  });
}
