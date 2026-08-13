import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/ui/settings/backup_settings_page.dart';

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
}
