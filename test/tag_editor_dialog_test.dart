import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/tag_editor_dialog.dart';
import 'package:omnis_plugins/tag_editor_plugin.dart';

/// No widget test previously existed for `TagEditorDialog` itself (only
/// `tag_editor_plugin_test.dart`, which covers `TagEditorPlugin`'s
/// read/write logic directly). This file is scoped narrowly to the one
/// thing task 7 changed: the dialog's content width now scales with the
/// viewport instead of being pinned to a fixed 420.
BaseTrack _track({required String id, required String localPath}) =>
    BaseTrack(
      id: id,
      title: 'Title',
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
      localPath: localPath,
    );

void main() {
  late Directory tempDir;
  late File audioFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('omnis_tag_editor_dialog');
    audioFile = File('${tempDir.path}/song.mp3')
      ..writeAsBytesSync(List.filled(200, 0xFF));
  });

  tearDown(() {
    // Best-effort: the native tag-reading plugin can briefly hold the file
    // open past the widget's own disposal on Windows.
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> openAt(WidgetTester tester, double width,
      {double height = 800}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => TagEditorDialog.show(
            context,
            _track(id: '1', localPath: audioFile.path),
            plugin: TagEditorPlugin(),
          ),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    // Not pumpAndSettle: the dialog shows an indeterminate
    // CircularProgressIndicator while `_load()`'s readTags await is in
    // flight, and an indeterminate progress indicator schedules frames
    // forever, so pumpAndSettle never returns. A bounded pump gives the
    // real (fast, local-file) read time to finish instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  double contentWidth(WidgetTester tester) => tester
      .widgetList<SizedBox>(find.byType(SizedBox))
      .firstWhere((s) => s.width != null && s.height == 480)
      .width!;

  group('dialog width scales with the viewport instead of staying pinned '
      'to the old fixed 420', () {
    testWidgets('at a narrow phone width, the dialog shrinks below the old '
        'fixed 420 instead of overflowing or staying pinned', (tester) async {
      await openAt(tester, 320);

      expect(contentWidth(tester), 320,
          reason: 'below the 420 ceiling and above the 280 floor, the '
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
        '420 rather than growing to fill the window', (tester) async {
      await openAt(tester, 1600, height: 1000);

      expect(contentWidth(tester), 420);
      expect(tester.takeException(), isNull);
    });
  });
}
