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
    );

void main() {
  testWidgets('a library with nothing to flag shows the "nothing to clean '
      'up" state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryCleanupReportPage(
        tracks: [_track(id: '1', coverArt: '/art.jpg', year: 2000, trackNumber: 1)],
        onEditTags: (_) async {},
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
}
