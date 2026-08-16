import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/library_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Item 5/spec §8's "filesystem watchers" gap — the settings toggle
/// only, not the watcher itself (that's `test/library_watcher_test.dart`,
/// pure logic with an injectable watch function). Deliberately never
/// taps "Pick folder" — that opens a real native file_picker dialog no
/// automated test can interact with, the same caution
/// `backup_settings_page_test.dart` already documents for a different
/// page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  testWidgets('Watch folder toggle renders, defaults off, and persists '
      'when flipped', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LibrarySettingsPage(),
    ));
    await tester.pump();

    expect(find.text('Watch folder for changes'), findsOneWidget);
    final tileBefore = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Watch folder for changes'));
    expect(tileBefore.value, isFalse);

    await tester.tap(find.text('Watch folder for changes'));
    await tester.pump();

    expect(AppSettings.instance.libraryWatcherEnabled, isTrue);
    final tileAfter = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Watch folder for changes'));
    expect(tileAfter.value, isTrue);
  });

  testWidgets('opening with highlightField: "library_watcher" scrolls '
      'to and flashes that row without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LibrarySettingsPage(highlightField: 'library_watcher'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Watch folder for changes'), findsOneWidget);
  });

  group('item 5, scheduled scan', () {
    testWidgets(
        'Scheduled scan toggle renders, defaults off, and hides the '
        'frequency/last-run rows until enabled', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LibrarySettingsPage(),
      ));
      await tester.pump();

      expect(find.text('Scheduled scan'), findsOneWidget);
      final tileBefore = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Scheduled scan'));
      expect(tileBefore.value, isFalse);
      expect(find.text('Scan frequency'), findsNothing);
      expect(find.text('Last scheduled scan'), findsNothing);

      await tester.tap(find.text('Scheduled scan'));
      await tester.pump();

      expect(AppSettings.instance.autoScanEnabled, isTrue);
      expect(find.text('Scan frequency'), findsOneWidget);
      final lastRun = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Last scheduled scan'));
      expect((lastRun.subtitle as Text).data, 'Never yet');
    });

    testWidgets('changing scan frequency persists the chosen interval',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LibrarySettingsPage(),
      ));
      await tester.pump();
      await tester.tap(find.text('Scheduled scan'));
      await tester.pump();

      expect(AppSettings.instance.autoScanIntervalHours, 6);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      expect(AppSettings.instance.autoScanIntervalHours, 24);
    });

    testWidgets('opening with highlightField: "auto_scan" scrolls to and '
        'flashes that row without throwing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LibrarySettingsPage(highlightField: 'auto_scan'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Scheduled scan'), findsOneWidget);
    });
  });
}
