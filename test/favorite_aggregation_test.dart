import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/favorite_aggregation.dart';

BaseTrack _track({
  required String id,
  List<String> artists = const ['Artist'],
  String album = 'Album',
  List<String> genres = const [],
  String title = '',
}) =>
    BaseTrack(
      id: id,
      title: title.isEmpty ? 'Title $id' : title,
      artists: artists,
      album: album,
      genres: genres,
      duration: 180,
      type: TrackType.local,
    );

void main() {
  group('topFavoriteGroups', () {
    test('an empty track list returns an empty list', () {
      expect(
        topFavoriteGroups(const [], (_) => false, by: FavoriteGroupBy.artist),
        isEmpty,
      );
    });

    test('no favorited tracks returns an empty list, not zero-count groups',
        () {
      final tracks = [_track(id: '1'), _track(id: '2')];
      expect(
        topFavoriteGroups(tracks, (_) => false, by: FavoriteGroupBy.artist),
        isEmpty,
      );
    });

    test('ranks artists by favorite count, highest first', () {
      final tracks = [
        _track(id: '1', artists: const ['A']),
        _track(id: '2', artists: const ['A']),
        _track(id: '3', artists: const ['B']),
      ];
      final result =
          topFavoriteGroups(tracks, (_) => true, by: FavoriteGroupBy.artist);

      expect(result.map((g) => g.name).toList(), ['A', 'B']);
      expect(result[0].favoriteCount, 2);
      expect(result[1].favoriteCount, 1);
    });

    test('unfavorited tracks do not contribute to any group', () {
      final tracks = [
        _track(id: '1', artists: const ['A']),
        _track(id: '2', artists: const ['B']),
      ];
      bool isFavorite(String id) => id == '1';
      final result =
          topFavoriteGroups(tracks, isFavorite, by: FavoriteGroupBy.artist);

      expect(result.length, 1);
      expect(result.single.name, 'A');
    });

    test('a track with multiple artists contributes to each artist', () {
      final tracks = [_track(id: '1', artists: const ['A', 'B'])];
      final result = topFavoriteGroups(tracks, (_) => true,
          by: FavoriteGroupBy.artist);

      expect(result.map((g) => g.name).toSet(), {'A', 'B'});
      expect(result.every((g) => g.favoriteCount == 1), isTrue);
    });

    test('groups by album using the album field', () {
      final tracks = [
        _track(id: '1', album: 'X'),
        _track(id: '2', album: 'X'),
        _track(id: '3', album: 'Y'),
      ];
      final result =
          topFavoriteGroups(tracks, (_) => true, by: FavoriteGroupBy.album);

      expect(result.first.name, 'X');
      expect(result.first.favoriteCount, 2);
    });

    test('groups by genre, skipping tracks with no genres', () {
      final tracks = [
        _track(id: '1', genres: const ['Rock']),
        _track(id: '2', genres: const []),
      ];
      final result =
          topFavoriteGroups(tracks, (_) => true, by: FavoriteGroupBy.genre);

      expect(result.length, 1);
      expect(result.single.name, 'Rock');
    });

    test('blank names are skipped entirely', () {
      final tracks = [_track(id: '1', album: '   ')];
      final result =
          topFavoriteGroups(tracks, (_) => true, by: FavoriteGroupBy.album);

      expect(result, isEmpty);
    });

    test('ties are broken alphabetically for a deterministic order', () {
      final tracks = [
        _track(id: '1', artists: const ['Zeta']),
        _track(id: '2', artists: const ['Alpha']),
      ];
      final result =
          topFavoriteGroups(tracks, (_) => true, by: FavoriteGroupBy.artist);

      expect(result.map((g) => g.name).toList(), ['Alpha', 'Zeta']);
    });

    test('limit caps the number of groups returned', () {
      final tracks = [
        _track(id: '1', artists: const ['A']),
        _track(id: '2', artists: const ['B']),
        _track(id: '3', artists: const ['C']),
      ];
      final result = topFavoriteGroups(tracks, (_) => true,
          by: FavoriteGroupBy.artist, limit: 2);

      expect(result.length, 2);
    });
  });

  group('topRatedTracks', () {
    test('an empty track list returns an empty list', () {
      expect(topRatedTracks(const [], (_) => 0), isEmpty);
    });

    test('unrated tracks (rating 0) are excluded', () {
      final tracks = [_track(id: '1'), _track(id: '2')];
      expect(topRatedTracks(tracks, (_) => 0), isEmpty);
    });

    test('ranks tracks by rating, highest first', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      int ratingOf(String id) => switch (id) {
            '1' => 3,
            '2' => 5,
            _ => 0,
          };
      final result = topRatedTracks(tracks, ratingOf);

      expect(result.map((t) => t.id).toList(), ['2', '1']);
    });

    test('ties are broken by title for a deterministic order', () {
      final tracks = [
        _track(id: '1', title: 'Zeta'),
        _track(id: '2', title: 'Alpha'),
      ];
      int ratingOf(String id) => 4;
      final result = topRatedTracks(tracks, ratingOf);

      expect(result.map((t) => t.title).toList(), ['Alpha', 'Zeta']);
    });

    test('limit caps the number of tracks returned', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      final result = topRatedTracks(tracks, (_) => 4, limit: 2);

      expect(result.length, 2);
    });
  });
}
