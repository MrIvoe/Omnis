import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/library_page.dart';

void main() {
  group('library grouping', () {
    test('groups tracks by artist and album when albums mode is enabled', () {
      final tracks = [
        BaseTrack(
          id: '1',
          title: 'Sunrise',
          artists: ['Ava'],
          album: 'Morning',
          duration: 180,
          type: TrackType.local,
        ),
        BaseTrack(
          id: '2',
          title: 'Moonlight',
          artists: ['Ava'],
          album: 'Night',
          duration: 200,
          type: TrackType.local,
        ),
        BaseTrack(
          id: '3',
          title: 'Echo',
          artists: ['Ben'],
          album: 'Night',
          duration: 210,
          type: TrackType.local,
        ),
      ];

      final sections = buildLibrarySections(tracks, viewMode: LibraryViewMode.artists, showAlbums: true);

      expect(sections.length, 2);
      expect(sections.first.title, 'Ava');
      expect(sections.first.children, hasLength(2));
      expect(sections.first.children.first.title, 'Morning');
      expect(sections.first.children.first.children, hasLength(1));
      expect(sections.first.children.first.children.first.title, 'Sunrise');
    });

    test('LibrarySection.allTracks flattens a nested artist/album/track '
        'structure into every real track it covers', () {
      final tracks = [
        BaseTrack(
          id: '1',
          title: 'Sunrise',
          artists: ['Ava'],
          album: 'Morning',
          duration: 180,
          type: TrackType.local,
        ),
        BaseTrack(
          id: '2',
          title: 'Moonlight',
          artists: ['Ava'],
          album: 'Night',
          duration: 200,
          type: TrackType.local,
        ),
        BaseTrack(
          id: '3',
          title: 'Echo',
          artists: ['Ben'],
          album: 'Night',
          duration: 210,
          type: TrackType.local,
        ),
      ];

      final sections = buildLibrarySections(tracks,
          viewMode: LibraryViewMode.artists, showAlbums: true);

      // Ava's top-level section has no direct `tracks` of its own (it's
      // all nested under album children) — allTracks must still surface
      // both of her tracks.
      final ava = sections.firstWhere((s) => s.title == 'Ava');
      expect(ava.tracks, isEmpty);
      expect(ava.allTracks.map((t) => t.id).toSet(), {'1', '2'});
    });

    test('LibrarySection.allTracks on a flat (non-nested) section just '
        'returns its own tracks unchanged', () {
      final tracks = [
        BaseTrack(
          id: '1',
          title: 'Sunrise',
          artists: const ['Ava'],
          album: 'Morning',
          duration: 180,
          type: TrackType.local,
        ),
      ];

      final sections =
          buildLibrarySections(tracks, viewMode: LibraryViewMode.albums, showAlbums: false);

      expect(sections.single.allTracks, sections.single.tracks);
    });

    test('folders mode groups by parent directory, titled by its basename', () {
      final tracks = [
        BaseTrack(
          id: '1',
          title: 'A',
          artists: const ['X'],
          album: 'Album',
          duration: 120,
          type: TrackType.local,
          localPath: '/music/Rock/Disc 1/a.mp3',
        ),
        BaseTrack(
          id: '2',
          title: 'B',
          artists: const ['X'],
          album: 'Album',
          duration: 120,
          type: TrackType.local,
          localPath: '/music/Rock/Disc 1/b.mp3',
        ),
        BaseTrack(
          id: '3',
          title: 'C',
          artists: const ['Y'],
          album: 'Album',
          duration: 120,
          type: TrackType.local,
          localPath: '/music/Jazz/c.mp3',
        ),
        BaseTrack(
          id: '4',
          title: 'D (no local file)',
          artists: const ['Z'],
          album: 'Album',
          duration: 120,
          type: TrackType.youtube,
          streamUrl: 'https://example.com/d',
        ),
      ];

      final sections = buildLibrarySections(tracks,
          viewMode: LibraryViewMode.folders, showAlbums: false);

      final titles = sections.map((s) => s.title).toList();
      expect(titles, containsAll(['Disc 1', 'Jazz', 'Unknown location']));

      final disc1 = sections.firstWhere((s) => s.title == 'Disc 1');
      expect(disc1.tracks.map((t) => t.id), containsAll(['1', '2']));

      final unknown = sections.firstWhere((s) => s.title == 'Unknown location');
      expect(unknown.tracks.map((t) => t.id), ['4']);
    });

    test(
        'groupArtistsByAlbumArtist groups a compilation under one album '
        'artist instead of scattering by each track\'s own performer', () {
      final tracks = [
        BaseTrack(
          id: '1',
          title: 'Track One',
          artists: ['Solo Performer A'],
          album: 'Big Compilation',
          albumArtist: 'Various Artists',
          duration: 180,
          type: TrackType.local,
        ),
        BaseTrack(
          id: '2',
          title: 'Track Two',
          artists: ['Solo Performer B'],
          album: 'Big Compilation',
          albumArtist: 'Various Artists',
          duration: 180,
          type: TrackType.local,
        ),
        // No albumArtist tag — falls back to its own artist, same as the
        // setting being off.
        BaseTrack(
          id: '3',
          title: 'Solo Song',
          artists: ['Independent Artist'],
          album: 'Solo Album',
          duration: 180,
          type: TrackType.local,
        ),
      ];

      final off = buildLibrarySections(tracks,
          viewMode: LibraryViewMode.artists, showAlbums: false);
      expect(off.map((s) => s.title).toSet(),
          {'Solo Performer A', 'Solo Performer B', 'Independent Artist'});

      final on = buildLibrarySections(tracks,
          viewMode: LibraryViewMode.artists,
          showAlbums: false,
          groupArtistsByAlbumArtist: true);
      expect(on.map((s) => s.title).toSet(),
          {'Various Artists', 'Independent Artist'});
      final compilation = on.firstWhere((s) => s.title == 'Various Artists');
      expect(compilation.tracks.map((t) => t.id).toSet(), {'1', '2'});
    });
  });

  group('findDuplicateTracks', () {
    BaseTrack track({
      required String id,
      required String title,
      required String artist,
      int duration = 180,
    }) =>
        BaseTrack(
          id: id,
          title: title,
          artists: [artist],
          album: 'Album',
          duration: duration,
          type: TrackType.local,
        );

    test('groups same title + primary artist regardless of case/spacing', () {
      final tracks = [
        track(id: '1', title: 'Sunrise', artist: 'Ava'),
        track(id: '2', title: '  sunrise  ', artist: 'ava'),
        track(id: '3', title: 'Moonlight', artist: 'Ava'),
      ];

      final groups = findDuplicateTracks(tracks);

      expect(groups, hasLength(1));
      expect(groups.first.map((t) => t.id), containsAll(['1', '2']));
    });

    test('a track with no duplicates produces no group', () {
      final tracks = [
        track(id: '1', title: 'Sunrise', artist: 'Ava'),
        track(id: '2', title: 'Moonlight', artist: 'Ava'),
      ];

      expect(findDuplicateTracks(tracks), isEmpty);
    });

    test('same title but different artist is not a duplicate', () {
      final tracks = [
        track(id: '1', title: 'Sunrise', artist: 'Ava'),
        track(id: '2', title: 'Sunrise', artist: 'Ben'),
      ];

      expect(findDuplicateTracks(tracks), isEmpty);
    });
  });

  group('findShortTracks', () {
    BaseTrack track({required String id, required int duration}) => BaseTrack(
          id: id,
          title: 'T$id',
          artists: const ['Artist'],
          album: 'Album',
          duration: duration,
          type: TrackType.local,
        );

    test('finds tracks at or under the threshold', () {
      final tracks = [
        track(id: '1', duration: 15),
        track(id: '2', duration: 30),
        track(id: '3', duration: 31),
        track(id: '4', duration: 200),
      ];

      final short = findShortTracks(tracks, thresholdSeconds: 30);

      expect(short.map((t) => t.id), containsAll(['1', '2']));
      expect(short, hasLength(2));
    });

    test('duration 0 (unknown) is never treated as short', () {
      final tracks = [track(id: '1', duration: 0)];

      expect(findShortTracks(tracks, thresholdSeconds: 30), isEmpty);
    });
  });
}
