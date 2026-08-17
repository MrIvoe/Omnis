import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_rules.dart';

BaseTrack _track(String id,
        {String artist = 'Artist',
        String? albumArtist,
        String album = 'Album'}) =>
    BaseTrack(
      id: id,
      title: 'Title $id',
      artists: [artist],
      albumArtist: albumArtist,
      album: album,
      duration: 180,
      type: TrackType.local,
    );

void main() {
  group('QueueRuleConstraints', () {
    test('none is inactive', () {
      expect(QueueRuleConstraints.none.isActive, isFalse);
    });

    test('default constructor with both gaps at 0 is inactive', () {
      expect(const QueueRuleConstraints().isActive, isFalse);
    });

    test('a positive minArtistGap alone is active', () {
      expect(const QueueRuleConstraints(minArtistGap: 1).isActive, isTrue);
    });

    test('a positive minAlbumGap alone is active', () {
      expect(const QueueRuleConstraints(minAlbumGap: 1).isActive, isTrue);
    });
  });

  group('applyQueueRules — no-op cases', () {
    test('an empty list stays empty', () {
      final result = applyQueueRules(
          const [], const QueueRuleConstraints(minArtistGap: 1));
      expect(result, isEmpty);
    });

    test('a single-track list is returned unchanged', () {
      final tracks = [_track('a')];
      final result =
          applyQueueRules(tracks, const QueueRuleConstraints(minArtistGap: 1));
      expect(result, tracks);
    });

    test('inactive constraints leave the order untouched', () {
      final tracks = [
        _track('a', artist: 'X'),
        _track('b', artist: 'X'),
        _track('c', artist: 'X'),
      ];
      final result = applyQueueRules(tracks, QueueRuleConstraints.none);
      expect(result.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('does not mutate the input list', () {
      final tracks = [
        _track('a', artist: 'X'),
        _track('b', artist: 'Y'),
        _track('a2', artist: 'X'),
      ];
      final original = List<BaseTrack>.of(tracks);
      applyQueueRules(tracks, const QueueRuleConstraints(minArtistGap: 1));
      expect(tracks.map((t) => t.id), original.map((t) => t.id));
    });
  });

  group('applyQueueRules — artist gap', () {
    test('swaps forward to resolve an adjacent same-artist conflict', () {
      final tracks = [
        _track('a1', artist: 'X'),
        _track('a2', artist: 'X'),
        _track('b1', artist: 'Y'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1));

      expect(result.map((t) => t.id).toList(), ['a1', 'b1', 'a2']);
    });

    test('a pool with no conflicts is unchanged', () {
      final tracks = [
        _track('a1', artist: 'X'),
        _track('b1', artist: 'Y'),
        _track('c1', artist: 'Z'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1));

      expect(result.map((t) => t.id), ['a1', 'b1', 'c1']);
    });

    test('minArtistGap > 1 requires more separation than one track', () {
      final tracks = [
        _track('a1', artist: 'X'),
        _track('b1', artist: 'Y'),
        _track('a2', artist: 'X'),
        _track('c1', artist: 'Z'),
      ];

      // minArtistGap: 2 means at least two other tracks must separate two
      // X tracks — 'a1', 'b1', 'a2' only has one track (b1) between them,
      // which violates the rule, so a2 must move past c1.
      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 2));

      final aIndex1 = result.indexWhere((t) => t.id == 'a1');
      final aIndex2 = result.indexWhere((t) => t.id == 'a2');
      expect((aIndex2 - aIndex1).abs(), greaterThanOrEqualTo(3));
    });

    test(
        'an artist-dominated pool leaves an unresolved violation without '
        'throwing or looping forever', () {
      final tracks = [
        _track('a1', artist: 'X'),
        _track('a2', artist: 'X'),
        _track('a3', artist: 'X'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1));

      expect(result.map((t) => t.id).toSet(), {'a1', 'a2', 'a3'});
      expect(result.length, 3);
    });

    test('groupByAlbumArtist compares albumArtist instead of the first '
        'performer', () {
      final tracks = [
        _track('a1', artist: 'Feat A', albumArtist: 'Various Artists'),
        _track('a2', artist: 'Feat B', albumArtist: 'Various Artists'),
        _track('b1', artist: 'Solo', albumArtist: 'Solo'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1),
          groupByAlbumArtist: true);

      expect(result.map((t) => t.id).toList(), ['a1', 'b1', 'a2']);
    });
  });

  group('applyQueueRules — album gap', () {
    test('swaps forward to resolve an adjacent same-album conflict', () {
      final tracks = [
        _track('a1', artist: 'X', album: 'Album1'),
        _track('a2', artist: 'Y', album: 'Album1'),
        _track('b1', artist: 'Z', album: 'Album2'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minAlbumGap: 1));

      expect(result.map((t) => t.id).toList(), ['a1', 'b1', 'a2']);
    });

    test('albums with the same title but different albumArtists do not '
        'conflict', () {
      final tracks = [
        _track('a1', artist: 'X', albumArtist: 'X', album: 'Greatest Hits'),
        _track('a2', artist: 'Y', albumArtist: 'Y', album: 'Greatest Hits'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minAlbumGap: 1));

      expect(result.map((t) => t.id), ['a1', 'a2']);
    });
  });

  group('applyQueueRules — combined constraints', () {
    test('both artist and album gaps applied together', () {
      final tracks = [
        _track('a1', artist: 'X', album: 'Album1'),
        _track('a2', artist: 'X', album: 'Album2'),
        _track('b1', artist: 'Y', album: 'Album3'),
      ];

      final result = applyQueueRules(tracks,
          const QueueRuleConstraints(minArtistGap: 1, minAlbumGap: 1));

      expect(result.map((t) => t.id).toList(), ['a1', 'b1', 'a2']);
    });
  });

  group('applyQueueRules — precedingContext', () {
    test('blocks a repeat against tracks not in the list being repaired',
        () {
      final precedingContext = [_track('prev', artist: 'X')];
      final tracks = [
        _track('a1', artist: 'X'),
        _track('b1', artist: 'Y'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1),
          precedingContext: precedingContext);

      expect(result.map((t) => t.id).toList(), ['b1', 'a1']);
    });

    test('an empty precedingContext behaves like the default', () {
      final tracks = [
        _track('a1', artist: 'X'),
        _track('b1', artist: 'Y'),
      ];

      final result = applyQueueRules(
          tracks, const QueueRuleConstraints(minArtistGap: 1),
          precedingContext: const []);

      expect(result.map((t) => t.id), ['a1', 'b1']);
    });
  });
}
