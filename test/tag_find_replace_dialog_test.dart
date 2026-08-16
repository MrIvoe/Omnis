import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/tag_find_replace.dart';
import 'package:omnis/ui/tag_find_replace_dialog.dart';

BaseTrack _track({required String id, String title = 'Title'}) => BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
      localPath: '/music/$id.mp3',
    );

void main() {
  testWidgets('Apply is disabled until a find pattern actually matches '
      'something', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              TagFindReplaceDialog.show(context, [_track(id: '1')]),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('No changes yet.'), findsOneWidget);
    final applyButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
    expect(applyButton.onPressed, isNull);
  });

  testWidgets('typing a matching Find pattern enables Apply and shows a '
      'live preview', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => TagFindReplaceDialog.show(
              context, [_track(id: '1', title: 'Live at Wembley')]),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'Live');
    await tester.pump();

    expect(find.textContaining('1 change'), findsOneWidget);
    expect(find.textContaining('"Live at Wembley" → "Live at Wembley"'),
        findsNothing);
    final applyButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
    expect(applyButton.onPressed, isNotNull);
  });

  testWidgets('tapping Apply pops the dialog with the built rule',
      (tester) async {
    TagFindReplaceRule? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await TagFindReplaceDialog.show(
                context, [_track(id: '1', title: 'Live at Wembley')]);
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'Live');
    await tester.enterText(
        find.widgetWithText(TextField, 'Replace with'), 'Recorded');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.find, 'Live');
    expect(result!.replace, 'Recorded');
    expect(result!.fields, {TagFindReplaceField.title});
  });

  testWidgets('tapping Cancel pops with null and applies nothing',
      (tester) async {
    TagFindReplaceRule? result;
    var awaited = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await TagFindReplaceDialog.show(
                context, [_track(id: '1', title: 'Live')]);
            awaited = true;
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'Live');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(awaited, isTrue);
    expect(result, isNull);
  });

  testWidgets('toggling a field chip off removes it from the built rule',
      (tester) async {
    TagFindReplaceRule? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await TagFindReplaceDialog.show(
                context, [_track(id: '1', title: 'Live')]);
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // "Title" starts selected by default; also select "Album" so the
    // rule is non-empty after deselecting Title below.
    await tester.tap(find.widgetWithText(FilterChip, 'Album'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'Title'));
    await tester.pump();

    // "Album" (the fixture's default album value) itself is the
    // pattern, so it matches regardless of which field ends up
    // selected -- only field *selection* is under test here.
    await tester.enterText(find.widgetWithText(TextField, 'Find'), 'Album');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result?.fields, {TagFindReplaceField.album});
  });

  testWidgets('enabling Use regex switches matching to real regex '
      'syntax', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              TagFindReplaceDialog.show(context, [_track(id: '1', title: 'Track 001')]),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Find'), r'\s\d+$');
    await tester.pump();
    expect(find.text('No changes yet.'), findsOneWidget,
        reason: 'not a regex yet, so the literal backslash pattern '
            'matches nothing');

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Use regex'));
    await tester.pump();

    expect(find.textContaining('1 change'), findsOneWidget);
  });
}
