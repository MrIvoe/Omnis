import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugin_api/event_bus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

class _MinimalContext implements PluginContext {
  final EventBus _events = EventBus();

  @override
  EventBus get events => _events;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

// Every key present unconditionally, even when null — matching what a
// real BaseTrack.toJson() always produces (it never omits a key just
// because the value is null), since the plugin's own field access
// assumes that shape.
Map<String, dynamic> _track(String id,
        {String type = 'local', String? streamUrl}) =>
    {
      'id': id,
      'title': 'Title $id',
      'artists': ['Artist $id'],
      'genres': const [],
      'album': 'Album',
      'duration': 180,
      'type': type,
      'localPath': null,
      'streamUrl': streamUrl,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = _FakePathProvider(Directory.systemTemp.path);
  });

  group('favorites/plugin.dart (downloadable) — direct PluginRuntime', () {
    Future<PluginRuntime> load(PluginContext context) async {
      final source = await File(
              p.join('test', 'fixtures', 'favorites_plugin.dart.txt'))
          .readAsString();
      return PluginRuntime.create(
        source,
        declaredPermissions: const ['events'],
        getContext: () => context,
      );
    }

    test('loads for real, declares the right id and hooks', () async {
      final runtime = await load(_MinimalContext());
      expect(runtime.id, 'favorites');
      expect(runtime.hasHook('uiSlot'), isTrue);
    });

    test('a local track: favorite/unfavorite round-trips through '
        'isFavorite/favoriteIds, and favoritesWithSnapshots finds it by id',
        () async {
      final runtime = await load(_MinimalContext());

      expect(runtime.callHook('favoritesIsFavorite', ['a']), isFalse);

      runtime.callHook('favoritesSetFavorite', ['a', true, _track('a')]);

      expect(runtime.callHook('favoritesIsFavorite', ['a']), isTrue);
      expect(runtime.callHook('favoritesFavoriteIds', const []), ['a']);

      final withSnapshots = runtime
          .callHook('favoritesWithSnapshots', [[_track('a')]]) as List;
      expect(withSnapshots, hasLength(1));
      expect(withSnapshots.first['id'], 'a');

      runtime.callHook('favoritesSetFavorite', ['a', false, null]);
      expect(runtime.callHook('favoritesIsFavorite', ['a']), isFalse);
    });

    test('a non-local track (e.g. a radio station) is favorited but '
        'absent from favoritesWithSnapshots when it isn\'t in the local '
        'tracks list — known v1 limitation, see the file doc comment',
        () async {
      final runtime = await load(_MinimalContext());

      final station = _track('radio:a',
          type: 'radio', streamUrl: 'https://stream.example/a');
      runtime.callHook('favoritesSetFavorite', ['radio:a', true, station]);

      expect(runtime.callHook('favoritesIsFavorite', ['radio:a']), isTrue);
      expect(
          runtime.callHook('favoritesFavoriteIds', const []), ['radio:a']);

      // Not in the local library at all, and there's no snapshot to
      // reconstruct it from in this version.
      final withSnapshots =
          runtime.callHook('favoritesWithSnapshots', [const []]) as List;
      expect(withSnapshots, isEmpty);
    });

    test('favoritesSetFavorite emits a real FavoriteChangedEvent', () async {
      final context = _MinimalContext();
      final runtime = await load(context);

      final future = context.events.on<FavoriteChangedEvent>().first;
      runtime.callHook('favoritesSetFavorite', ['a', true, _track('a')]);
      final event = await future;

      expect(event.trackId, 'a');
      expect(event.isFavorite, true);
    });

    test('uiSlot reports the current favorite count as a badge', () async {
      final runtime = await load(_MinimalContext());
      runtime.callHook('favoritesSetFavorite', ['a', true, _track('a')]);

      final badge = runtime.callHook('uiSlot', ['now_playing_overlay']);
      expect(badge, isA<Map>());
      expect((badge as Map)['type'], 'badge');
      expect(badge['text'], '1 favorited');

      expect(runtime.callHook('uiSlot', ['settings_page']), isNull);
    });
  });

  group('favorites/plugin.dart — full install + ServiceRegistry path', () {
    test('installs, registers IFavoritesProvider, and both reads and '
        'writes work through the real interface', () async {
      final tempDir = await Directory.systemTemp.createTemp('omnis_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pluginDir = Directory(p.join(tempDir.path, 'favorites'));
      await pluginDir.create(recursive: true);
      final fixtureSource = await File(
              p.join('test', 'fixtures', 'favorites_plugin.dart.txt'))
          .readAsString();
      await File(p.join(pluginDir.path, 'plugin.dart'))
          .writeAsString(fixtureSource);
      await File(p.join(pluginDir.path, 'omnis_plugin.yaml'))
          .writeAsString('''
id: favorites
name: Favorites
description: Mark tracks as favorites for quick access.
version: 1.0.0
author: Omnis Team
entrypoint: plugin.dart
hooks: []
permissions:
  - events
provides:
  - favorites
''');

      final manager = PluginManager();
      await manager.installFromPath(pluginDir.path, sourceUrl: 'local');

      final provider = manager.services.get<IFavoritesProvider>();
      expect(provider, isNotNull);
      expect(provider!.isFavorite('a'), isFalse);

      await provider.setFavorite('a', true, track: BaseTrack.fromJson(_track('a')));
      expect(provider.isFavorite('a'), isTrue);
      expect(provider.favoriteIds(), ['a']);

      final results = provider.favoritesWithSnapshots(
          [BaseTrack.fromJson(_track('a'))]);
      expect(results, hasLength(1));
      expect(results.first.id, 'a');
    });
  });
}
