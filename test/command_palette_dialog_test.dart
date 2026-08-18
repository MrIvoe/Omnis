import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/command_palette_dialog.dart';
import 'package:omnis_plugin_api/playlist.dart';

BaseTrack _track(String id, {String title = 'Title'}) => BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

Playlist _playlist(String id, String name) => Playlist(
      id: id,
      name: name,
      trackIds: const [],
      createdAt: DateTime(2025),
    );

void main() {
  testWidgets('every default command renders when the query is empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);

    // The dialog's own ListView is height-constrained, so the last item
    // isn't necessarily built until scrolled into view — same
    // `dragUntilVisible` pattern this codebase already uses for the same
    // underlying cause elsewhere (e.g. plugins_page_test.dart).
    await tester.dragUntilVisible(
      find.text('Scan library'),
      find.byType(ListView),
      const Offset(0, -100),
    );
    expect(find.text('Scan library'), findsOneWidget);
  });

  testWidgets('typing a query filters the list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'shuffle');
    await tester.pumpAndSettle();

    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a query matching nothing shows an explicit message',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyzzy');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches "xyzzy".'), findsOneWidget);
  });

  testWidgets('tapping a command runs its action and closes the dialog',
      (tester) async {
    var played = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: {
            'play': () => played = true,
          }),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(played, isTrue);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a command with no matching action in the map is a harmless '
      'no-op, not a crash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
  });

  testWidgets('pressing Enter runs the first matching command',
      (tester) async {
    var scanned = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: {
            'scan_library': () => scanned = true,
          }),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'scan');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(scanned, isTrue);
  });

  testWidgets(
      'a non-empty query also surfaces matching songs/playlists/moods, '
      'grouped under section headers', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(
            context,
            actions: const {},
            tracks: [_track('t1', title: 'Blue Skies')],
            playlists: [_playlist('p1', 'Blue Road Trip')],
            moods: const ['Blue Mood'],
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pumpAndSettle();

    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Blue Skies'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Blue Road Trip'), findsOneWidget);
    expect(find.text('Moods'), findsOneWidget);
    expect(find.text('Blue Mood'), findsOneWidget);
  });

  testWidgets('tapping a song result calls onSelectTrack with that track '
      'and closes the dialog', (tester) async {
    BaseTrack? selected;
    final track = _track('t1', title: 'Blue Skies');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(
            context,
            actions: const {},
            tracks: [track],
            onSelectTrack: (t) => selected = t,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Skies'));
    await tester.pumpAndSettle();

    expect(selected, track);
    expect(find.text('Blue Skies'), findsNothing);
  });

  testWidgets('tapping a playlist result calls onSelectPlaylist with that '
      'playlist', (tester) async {
    Playlist? selected;
    final playlist = _playlist('p1', 'Road Trip');
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(
            context,
            actions: const {},
            playlists: [playlist],
            onSelectPlaylist: (p) => selected = p,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'road');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road Trip'));
    await tester.pumpAndSettle();

    expect(selected, playlist);
  });

  testWidgets('tapping a mood result calls onSelectMood with that mood '
      'string', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(
            context,
            actions: const {},
            moods: const ['Chill'],
            onSelectMood: (m) => selected = m,
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chill');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chill'));
    await tester.pumpAndSettle();

    expect(selected, 'Chill');
  });
}
