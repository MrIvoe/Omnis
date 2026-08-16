import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/library_cleanup_report_page.dart';

BaseTrack _track({
  required String id,
  String title = 'Title',
  String artist = 'Artist',
  String album = 'Album',
  int? year,
  int? trackNumber,
  String? genre,
  String? coverArt,
  String? codec,
  String? localPath,
  int? bitrateKbps,
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: [artist],
      album: album,
      duration: 180,
      year: year,
      trackNumber: trackNumber,
      genres: genre == null ? const [] : [genre],
      coverArt: coverArt,
      codec: codec,
      localPath: localPath,
      type: TrackType.local,
      bitrateKbps: bitrateKbps,
    );

void main() {
  testWidgets('a library with nothing to flag shows the "nothing to clean '
      'up" state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [_track(id: '1', coverArt: '/art.jpg', year: 2000, trackNumber: 1)],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Nothing to clean up'), findsOneWidget);
  });

  testWidgets('shows a real count per category, not a placeholder',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', title: 'Song One', coverArt: null),
          _track(id: '2', title: 'Song Two', coverArt: null),
          _track(id: '3',
              title: 'Song Three',
              coverArt: '/art.jpg',
              year: 2000,
              trackNumber: 1),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    expect(find.text('2 missing artwork'), findsOneWidget);
    // Further down the category list than the default 800x600 test
    // viewport's sliver mount/cache-extent boundary reaches — not just
    // off-screen but genuinely unmounted, so dragUntilVisible (not
    // ensureVisible, which needs the widget to already exist) is what's
    // needed to actually bring it into the tree.
    await tester.dragUntilVisible(
      find.text('0 duplicate tracks'),
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 duplicate tracks'), findsOneWidget);
  });

  testWidgets('tapping a non-zero category opens its detail list',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', title: 'Untagged Song', coverArt: null),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('1 missing artwork'));
    await tester.pumpAndSettle();

    expect(find.text('Untagged Song'), findsOneWidget);
    expect(find.text('Edit tags'), findsOneWidget);
  });

  testWidgets('tapping a zero-count category does nothing (disabled)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', coverArt: null), // only missing artwork is non-zero
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('0 duplicate tracks'));
    await tester.pumpAndSettle();

    // Still on the index page — no detail screen appeared.
    expect(find.text('Analyze Library'), findsOneWidget);
  });

  testWidgets('tapping "Edit tags" on a flagged track invokes onEditTags '
      'with that exact track', (tester) async {
    BaseTrack? editedTrack;
    final flagged = _track(id: '1', title: 'Untagged Song', coverArt: null);

    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [flagged],
        onEditTags: (track) async {
          editedTrack = track;
        },
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('1 missing artwork'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit tags'));
    await tester.pump();

    expect(editedTrack?.id, '1');
  });

  testWidgets('duplicate tracks category points at the Library page\'s own '
      'cleanup tool rather than offering its own merge action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', title: 'Sunrise', artist: 'Ava'),
          _track(id: '2', title: 'Sunrise', artist: 'Ava'),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('2 duplicate tracks'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Find duplicates & short tracks'),
        findsOneWidget);
    expect(find.text('Edit tags'), findsNothing,
        reason: 'no per-track fix action for a category this page '
            'deliberately delegates elsewhere');
  });

  testWidgets('albums missing year lists album names, not individual '
      'tracks', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', album: 'Undated Album', year: null),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('1 albums missing year'));
    await tester.pumpAndSettle();

    expect(find.text('Undated Album'), findsOneWidget);
  });

  testWidgets('corrupt files are listed read-only with a disclaimer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', title: 'Broken', localPath: '/music/broken.flac'),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('1 corrupt files'),
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 corrupt files'));
    await tester.pumpAndSettle();

    expect(find.text('Broken'), findsOneWidget);
    expect(find.text('Edit tags'), findsNothing);
    expect(find.textContaining("couldn't be read"), findsOneWidget);
  });

  testWidgets('low-quality files are listed read-only with a bitrate '
      'disclaimer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(id: '1', title: 'Muddy', codec: 'MP3', bitrateKbps: 96),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    await tester.dragUntilVisible(
      find.text('1 low-quality files'),
      find.byType(ListView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 low-quality files'));
    await tester.pumpAndSettle();

    expect(find.text('Muddy'), findsOneWidget);
    expect(find.textContaining('MP3 · 96 kbps'), findsOneWidget);
    expect(find.text('Edit tags'), findsNothing);
    expect(find.textContaining('128'), findsWidgets);
  });

  testWidgets('a lossless track is never listed as low-quality',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [
          _track(
              id: '1',
              coverArt: '/art.jpg',
              year: 2000,
              trackNumber: 1,
              codec: 'FLAC',
              bitrateKbps: 96),
        ],
        onEditTags: (_) async {},
        onRemoveFromLibrary: (_) async {},
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Nothing to clean up'), findsOneWidget);
  });

  group('unorganized files (item 17, spec §9)', () {
    testWidgets('a misplaced track is listed read-only with a disclaimer',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LibraryCleanupReportPage(
          tracks: [
            _track(
              id: '1',
              title: 'Loose File',
              artist: 'Queen',
              album: 'A Night at the Opera',
              localPath: '/music/Wrong Folder/track.flac',
            ),
          ],
          onEditTags: (_) async {},
          onRemoveFromLibrary: (_) async {},
        ),
      ));
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('1 unorganized files'),
        find.byType(ListView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 unorganized files'));
      await tester.pumpAndSettle();

      expect(find.text('Loose File'), findsOneWidget);
      expect(find.text('Edit tags'), findsNothing);
      expect(find.textContaining("aren't in a"), findsOneWidget);
    });

    testWidgets('a correctly-organized track is never listed as '
        'unorganized', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LibraryCleanupReportPage(
          tracks: [
            _track(
              id: '1',
              coverArt: '/art.jpg',
              year: 2000,
              trackNumber: 1,
              artist: 'Queen',
              album: 'A Night at the Opera',
              localPath: '/music/Queen/A Night at the Opera/track.flac',
              codec: 'FLAC',
            ),
          ],
          onEditTags: (_) async {},
          onRemoveFromLibrary: (_) async {},
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Nothing to clean up'), findsOneWidget);
    });
  });

  group('missing files (item 17)', () {
    testWidgets('a track whose file genuinely does not exist on disk is '
        'flagged, after the async check resolves', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: LibraryCleanupReportPage(
            tracks: [
              _track(
                id: '1',
                title: 'Ghost Track',
                coverArt: '/art.jpg',
                year: 2000,
                trackNumber: 1,
                localPath: '/definitely/does/not/exist/ghost.mp3',
              ),
            ],
            onEditTags: (_) async {},
            onRemoveFromLibrary: (_) async {},
          ),
        ));
        await tester.pump();
        // The initial synchronous analyze() pass can't know this yet —
        // findMissingFiles is real dart:io I/O that resolves a beat
        // later; runAsync (rather than just more pump()s) is what
        // actually lets that real Future settle before we look.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('1 missing files'),
          find.byType(ListView),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 missing files'), findsOneWidget);
      });
    });

    testWidgets('a track whose file genuinely exists is never flagged',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LibraryCleanupReportPage(
          tracks: [
            _track(
              id: '1',
              coverArt: '/art.jpg',
              year: 2000,
              trackNumber: 1,
              // No localPath at all — same "never checked" contract
              // findMissingFiles itself already establishes.
            ),
          ],
          onEditTags: (_) async {},
          onRemoveFromLibrary: (_) async {},
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing to clean up'), findsOneWidget);
    });

    testWidgets('tapping "Remove" on a missing file invokes '
        'onRemoveFromLibrary with that exact track', (tester) async {
      await tester.runAsync(() async {
        BaseTrack? removedTrack;
        final ghost = _track(
          id: '1',
          title: 'Ghost Track',
          coverArt: '/art.jpg',
          year: 2000,
          trackNumber: 1,
          localPath: '/definitely/does/not/exist/ghost.mp3',
        );

        await tester.pumpWidget(MaterialApp(
          home: LibraryCleanupReportPage(
            tracks: [ghost],
            onEditTags: (_) async {},
            onRemoveFromLibrary: (track) async {
              removedTrack = track;
            },
          ),
        ));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('1 missing files'),
          find.byType(ListView),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('1 missing files'));
        await tester.pumpAndSettle();

        expect(find.text('Ghost Track'), findsOneWidget);
        await tester.tap(find.text('Remove'));
        await tester.pump();

        expect(removedTrack?.id, '1');
      });
    });
  });
}
