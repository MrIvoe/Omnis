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
  });
}
