import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/plugins/favorites_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op stand-in for AudioEngine — FavoritesPlugin never touches
/// playback, so this only exists to satisfy PluginContext's constructor.
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

  BaseTrack track(String id) => BaseTrack(
        id: id,
        title: 'T$id',
        artists: const ['Artist'],
        album: 'Album',
        duration: 180,
        type: TrackType.local,
      );

  test('a track is not a favorite until marked', () {
    final plugin = FavoritesPlugin();
    expect(plugin.isFavorite('t1'), isFalse);
  });

  test('toggleFavorite flips state and persists across a fresh instance', () async {
    final plugin = FavoritesPlugin();
    await plugin.toggleFavorite('t1');
    expect(plugin.isFavorite('t1'), isTrue);

    final freshInstance = FavoritesPlugin();
    expect(freshInstance.isFavorite('t1'), isTrue);

    await freshInstance.toggleFavorite('t1');
    expect(plugin.isFavorite('t1'), isFalse);
  });

  test('favoritesFrom filters and orders by the input track list, not insertion order', () async {
    final plugin = FavoritesPlugin();
    final tracks = [track('a'), track('b'), track('c')];

    await plugin.setFavorite('c', true);
    await plugin.setFavorite('a', true);

    final favorites = plugin.favoritesFrom(tracks);
    expect(favorites.map((t) => t.id), ['a', 'c']);
  });

  test('setFavorite(false) on a non-favorite track is a harmless no-op', () async {
    final plugin = FavoritesPlugin();
    await plugin.setFavorite('t1', false);
    expect(plugin.isFavorite('t1'), isFalse);
  });

  test('setFavorite emits FavoriteChangedEvent on the shared event bus, '
      'so an unrelated page can react without polling', () async {
    final plugin = FavoritesPlugin();
    final events = EventBus();
    plugin.attach(PluginContext(
      audioEngine: _FakeEngine(),
      services: ServiceRegistry(),
      events: events,
    ));
    final received = <FavoriteChangedEvent>[];
    final sub = events.on<FavoriteChangedEvent>().listen(received.add);

    await plugin.setFavorite('t1', true);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.trackId, 't1');
    expect(received.single.isFavorite, isTrue);
    await sub.cancel();
  });

  test('a no-op setFavorite (already in the requested state) does not emit', () async {
    final plugin = FavoritesPlugin();
    final events = EventBus();
    plugin.attach(PluginContext(
      audioEngine: _FakeEngine(),
      services: ServiceRegistry(),
      events: events,
    ));
    final received = <FavoriteChangedEvent>[];
    final sub = events.on<FavoriteChangedEvent>().listen(received.add);

    await plugin.setFavorite('t1', false); // already false
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
  });
}
