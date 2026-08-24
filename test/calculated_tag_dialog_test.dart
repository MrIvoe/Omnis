import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/calculated_tags.dart';
import 'package:omnis/ui/calculated_tag_dialog.dart';

BaseTrack _track({
  required String id,
  String title = 'Title',
  int? year,
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      year: year,
      type: TrackType.local,
      localPath: '/music/$id.mp3',
    );

void main() {
  testWidgets('Apply is disabled until the template actually changes '
      'something', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => CalculatedTagDialog.show(context, [_track(id: '1')]),
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

  testWidgets('typing a template that resolves differently enables Apply '
      'and shows a live preview', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => CalculatedTagDialog.show(
              context, [_track(id: '1', title: 'Song', year: 1999)]),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Template'), '{title} ({year})');
    await tester.pump();

    expect(find.textContaining('1 track'), findsOneWidget);
    expect(find.textContaining('"Song" → "Song (1999)"'), findsOneWidget);
    final applyButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
    expect(applyButton.onPressed, isNotNull);
  });

  testWidgets('tapping Apply pops the dialog with the built rule',
      (tester) async {
    CalculatedTagRule? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await CalculatedTagDialog.show(
                context, [_track(id: '1', title: 'Song', year: 1999)]);
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Template'), '{title} ({year})');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.template, '{title} ({year})');
    expect(result!.target, CalculatedTagTargetField.title);
  });

  testWidgets('tapping Cancel pops with null and applies nothing',
      (tester) async {
    CalculatedTagRule? result;
    var awaited = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await CalculatedTagDialog.show(context, [_track(id: '1')]);
            awaited = true;
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Template'), '{title}!');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(awaited, isTrue);
    expect(result, isNull);
  });

  testWidgets('switching the target field via the dropdown changes the '
      'built rule\'s target, not just its display', (tester) async {
    CalculatedTagRule? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await CalculatedTagDialog.show(
                context, [_track(id: '1', title: 'Song', year: 1999)]);
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<CalculatedTagTargetField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album').last);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Template'), '{album} ({year})');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result!.target, CalculatedTagTargetField.album);
  });

  testWidgets('tapping a token chip inserts that token into the template '
      'field', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              CalculatedTagDialog.show(context, [_track(id: '1', year: 1999)]),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '{year}'));
    await tester.pump();

    final templateField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Template'));
    expect(templateField.controller?.text, '{year}');
  });

  group('dialog width scales with the viewport instead of staying pinned '
      'to the old fixed 480', () {
    Future<void> openAt(WidgetTester tester, double width,
        {double height = 800}) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                CalculatedTagDialog.show(context, [_track(id: '1')]),
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    double contentWidth(WidgetTester tester) => tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .firstWhere((s) => s.width != null)
        .width!;

    testWidgets('at a narrow phone width, the dialog shrinks below the old '
        'fixed 480 instead of overflowing or staying pinned', (tester) async {
      await openAt(tester, 320);

      expect(contentWidth(tester), 320,
          reason: 'below the 480 ceiling and above the 280 floor, the '
              'width should track the viewport exactly');
      expect(tester.takeException(), isNull);
    });

    testWidgets('below the 280 floor, width clamps to 280 rather than '
        'shrinking further or overflowing', (tester) async {
      await openAt(tester, 250);

      expect(contentWidth(tester), 280);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at a wide desktop width, the dialog caps at the old fixed '
        '480 rather than growing to fill the window', (tester) async {
      await openAt(tester, 1600, height: 1000);

      expect(contentWidth(tester), 480);
      expect(tester.takeException(), isNull);
    });
  });
}
