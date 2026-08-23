import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart' show ThumbState;
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:omnis_plugins/ratings_plugin.dart';
import 'package:omnis_plugin_api/smart_playlist_rule.dart';
import 'package:omnis_plugins/smart_playlist_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real registration/cross-plugin wiring for §42's `rating:` condition —
/// `RatingsPlugin` and `SmartPlaylistPlugin` are two separate plugins with
/// no direct dependency on each other; this proves `SmartPlaylistPlugin`
/// can actually reach rating data through a real `PluginManager` +
/// `PluginContext` + `ServiceRegistry`, not just through a
/// caller-supplied fake `ratingOf` closure the way
/// `smart_playlist_rule_test.dart`'s unit tests do. Promised in
/// `ratings_plugin_test.dart`'s "IRatingsProvider (item 42)" test doc.
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
    List<String> genres = const [],
  }) =>
      BaseTrack(
        id: id,
        title: 'T$id',
        artists: const ['Artist'],
        album: 'Album',
        duration: 180,
        type: TrackType.local,
        genres: genres,
      );

  Future<PluginManager> managerWith(List plugins) async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    for (final plugin in plugins) {
      manager.register(plugin);
    }
    await manager.initializeAll();
    return manager;
  }

  test('a saved rule with a rating: condition matches through the real '
      'registered IRatingsProvider, not just a caller-supplied lookup',
      () async {
    final ratings = RatingsPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    await managerWith([ratings, smartPlaylist]);

    await ratings.setRating('loved', 5);
    await ratings.setRating('meh', 2);

    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'well-rated',
      name: 'Well Rated',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.rating,
          operator: RuleOperator.greaterThanOrEqual,
          value: '4',
        ),
      ],
    ));

    final tracks = [
      track(id: 'loved'),
      track(id: 'meh'),
      track(id: 'unrated'),
    ];

    final result = smartPlaylist.buildQueueForRule(tracks, 'well-rated');
    expect(result.map((t) => t.id), ['loved']);
  });

  test('disabling RatingsPlugin unregisters IRatingsProvider, so a '
      'rating: condition stops matching without SmartPlaylistPlugin '
      'itself changing', () async {
    final ratings = RatingsPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    final manager = await managerWith([ratings, smartPlaylist]);

    await ratings.setRating('loved', 5);
    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'well-rated',
      name: 'Well Rated',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.rating,
          operator: RuleOperator.greaterThanOrEqual,
          value: '4',
        ),
      ],
    ));

    final ratingsManaged = manager.byId('ratings')!;
    await manager.disablePlugin(ratingsManaged);

    final result = smartPlaylist
        .buildQueueForRule([track(id: 'loved')], 'well-rated');
    expect(result, isEmpty);
  });

  test('a rule combining a genre condition with a rating condition '
      "(ALL) only matches tracks satisfying both — proves the two "
      "plugins' data genuinely composes, not just each in isolation",
      () async {
    final ratings = RatingsPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    await managerWith([ratings, smartPlaylist]);

    await ratings.setRating('rock-loved', 5);
    await ratings.setRating('rock-meh', 1);

    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'loved-rock',
      name: 'Loved Rock',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
            field: RuleField.genre,
            operator: RuleOperator.equals,
            value: 'rock'),
        RuleCondition(
            field: RuleField.rating,
            operator: RuleOperator.greaterThanOrEqual,
            value: '4'),
      ],
    ));

    final tracks = [
      track(id: 'rock-loved', genres: ['Rock']),
      track(id: 'rock-meh', genres: ['Rock']),
      track(id: 'pop-loved', genres: ['Pop']),
    ];

    final result = smartPlaylist.buildQueueForRule(tracks, 'loved-rock');
    expect(result.map((t) => t.id), ['rock-loved']);
  });

  test('a saved rule with a favorite: condition matches through the real '
      'registered IFavoritesProvider, not just a caller-supplied lookup',
      () async {
    final favorites = FavoritesPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    await managerWith([favorites, smartPlaylist]);

    await favorites.setFavorite('loved', true);

    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'my-favorites',
      name: 'My Favorites',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.favorite,
          operator: RuleOperator.equals,
          value: 'true',
        ),
      ],
    ));

    final tracks = [track(id: 'loved'), track(id: 'not-loved')];

    final result = smartPlaylist.buildQueueForRule(tracks, 'my-favorites');
    expect(result.map((t) => t.id), ['loved']);
  });

  test('disabling FavoritesPlugin unregisters IFavoritesProvider, so a '
      'favorite: condition stops matching without SmartPlaylistPlugin '
      'itself changing', () async {
    final favorites = FavoritesPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    final manager = await managerWith([favorites, smartPlaylist]);

    await favorites.setFavorite('loved', true);
    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'my-favorites',
      name: 'My Favorites',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.favorite,
          operator: RuleOperator.equals,
          value: 'true',
        ),
      ],
    ));

    final favoritesManaged = manager.byId('favorites')!;
    await manager.disablePlugin(favoritesManaged);

    final result = smartPlaylist
        .buildQueueForRule([track(id: 'loved')], 'my-favorites');
    expect(result, isEmpty);
  });

  test('a saved rule with a thumbUp: condition matches through the real '
      'registered IThumbsProvider, not just a caller-supplied lookup — '
      'item 36', () async {
    final ratings = RatingsPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    await managerWith([ratings, smartPlaylist]);

    await ratings.setThumb('liked', ThumbState.up);
    await ratings.setThumb('disliked', ThumbState.down);

    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'liked-tracks',
      name: 'Liked Tracks',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.thumbUp,
          operator: RuleOperator.equals,
          value: 'true',
        ),
      ],
    ));

    final tracks = [
      track(id: 'liked'),
      track(id: 'disliked'),
      track(id: 'neutral'),
    ];

    final result = smartPlaylist.buildQueueForRule(tracks, 'liked-tracks');
    expect(result.map((t) => t.id), ['liked']);
  });

  test('disabling RatingsPlugin unregisters IThumbsProvider too, so a '
      'thumbUp: condition stops matching without SmartPlaylistPlugin '
      'itself changing — proves both interfaces share the same '
      'enable/disable lifecycle, not just IRatingsProvider', () async {
    final ratings = RatingsPlugin();
    final smartPlaylist = SmartPlaylistPlugin();
    final manager = await managerWith([ratings, smartPlaylist]);

    await ratings.setThumb('liked', ThumbState.up);
    await smartPlaylist.saveRule(const SmartPlaylistRule(
      id: 'liked-tracks',
      name: 'Liked Tracks',
      matchType: RuleMatchType.all,
      conditions: [
        RuleCondition(
          field: RuleField.thumbUp,
          operator: RuleOperator.equals,
          value: 'true',
        ),
      ],
    ));

    final ratingsManaged = manager.byId('ratings')!;
    await manager.disablePlugin(ratingsManaged);

    final result = smartPlaylist
        .buildQueueForRule([track(id: 'liked')], 'liked-tracks');
    expect(result, isEmpty);
  });
}
