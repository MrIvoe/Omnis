import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/backup_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deliberately rendering-only — no test here taps "Backup Omnis" or
/// "Restore Omnis". `file_picker`'s desktop implementations (this repo
/// targets Windows) register a real platform implementation outside the
/// usual plugin-registration path used on mobile, so calling
/// `FilePicker.platform.saveFile`/`pickFiles` in a plain `flutter_test`
/// run can attempt to open an actual native OS file dialog — confirmed
/// while writing this test: it left real, hung `dart.exe` processes
/// behind waiting on a dialog no automated test can interact with. No
/// other test in this app's suite exercises `file_picker` interactions
/// either. `BackupSettingsPage`'s actual save/restore logic
/// (`BackupService`) already has thorough coverage in
/// `test/backup_service_test.dart`; this file only verifies the page
/// itself renders correctly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders both actions with explanatory text', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Backup Omnis'), findsOneWidget);
    expect(find.text('Restore Omnis'), findsOneWidget);
    expect(find.textContaining('Settings, themes, layouts, and plugin '
        'credentials are not included.'), findsOneWidget);
  });

  group('automatic backups (item 4/50)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();
    });

    testWidgets('the section renders, off by default with no frequency '
        'picker shown', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Automatic backups'), findsOneWidget);
      expect(find.text('Enable automatic backups'), findsOneWidget);
      final toggle =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
      expect(find.text('Frequency'), findsNothing);
      expect(find.text('Last automatic backup'), findsNothing);
    });

    testWidgets('enabling it reveals the frequency picker and last-run '
        'row, defaulting to Weekly and "Never yet"', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);
      expect(find.text('Last automatic backup'), findsOneWidget);
      expect(find.text('Never yet'), findsOneWidget);
      expect(AppSettings.instance.autoBackupEnabled, isTrue);
    });

    testWidgets('changing frequency persists the chosen interval',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      expect(AppSettings.instance.autoBackupIntervalDays, 1);
    });
  });
}
