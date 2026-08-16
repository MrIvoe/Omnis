import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/artwork_candidates.dart';
import 'package:omnis/core/base_track.dart';

BaseTrack _track({
  required String id,
  String? coverArt,
  String? localPath,
  TrackType type = TrackType.local,
}) =>
    BaseTrack(
      id: id,
      title: 'Track $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      coverArt: coverArt,
      localPath: localPath,
      type: type,
    );

void main() {
  group('tracksNeedingArtwork', () {
    test('an empty library returns an empty list', () {
      expect(tracksNeedingArtwork(const []), isEmpty);
    });

    test('a local track with no coverArt and a real path is a '
        'candidate', () {
      final tracks = [
        _track(id: '1', coverArt: null, localPath: '/music/a.mp3'),
      ];
      expect(tracksNeedingArtwork(tracks).map((t) => t.id), ['1']);
    });

    test('a local track with a blank coverArt string is still a '
        'candidate — blank is not "has artwork"', () {
      final tracks = [
        _track(id: '1', coverArt: '  ', localPath: '/music/a.mp3'),
      ];
      expect(tracksNeedingArtwork(tracks).map((t) => t.id), ['1']);
    });

    test('a local track that already has real artwork is excluded', () {
      final tracks = [
        _track(id: '1', coverArt: '/art/cover.jpg', localPath: '/music/a.mp3'),
      ];
      expect(tracksNeedingArtwork(tracks), isEmpty);
    });

    test('a local track with no localPath at all is excluded — nothing '
        'to write artwork to', () {
      final tracks = [_track(id: '1', coverArt: null, localPath: null)];
      expect(tracksNeedingArtwork(tracks), isEmpty);
    });

    test('a non-local track is never a candidate, even with no '
        'coverArt and a localPath somehow set', () {
      final tracks = [
        _track(
          id: '1',
          coverArt: null,
          localPath: '/music/a.mp3',
          type: TrackType.spotify,
        ),
      ];
      expect(tracksNeedingArtwork(tracks), isEmpty);
    });

    test('a mixed library only returns the genuinely missing-artwork '
        'local tracks', () {
      final tracks = [
        _track(id: 'needs-it', coverArt: null, localPath: '/music/a.mp3'),
        _track(id: 'has-it',
            coverArt: '/art/cover.jpg', localPath: '/music/b.mp3'),
        _track(id: 'no-path', coverArt: null, localPath: null),
        _track(id: 'not-local',
            coverArt: null, localPath: '/music/c.mp3', type: TrackType.youtube),
      ];
      expect(
          tracksNeedingArtwork(tracks).map((t) => t.id), ['needs-it']);
    });
  });
}
