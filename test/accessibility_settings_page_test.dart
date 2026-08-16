import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/accessibility_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// §58's "high contrast" accessibility requirement's toggle — the theme
/// logic itself (`OmnisTheme.build`'s `highContrast` param) is covered by
/// reading the code directly rather than a dedicated widget/unit test
/// here: it pulls in `google_fonts` via `OmnisTypography.build`, which
/// kicks off a fire-and-forget real font-fetch Future that reliably
/// leaks an uncaught async error across test boundaries under
/// `TestWidgetsFlutterBinding` — the same class of test-infrastructure
/// dead end `library_page_test.dart`'s own search-feature coverage hit
/// earlier in this project's history (see that file's history for the
/// precedent of relying on `flutter analyze` + the existing suite
/// staying green instead of a dedicated harness). This page never
/// touches `OmnisTheme.build`, so it has none of that risk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  testWidgets('High contrast toggle renders, defaults off, and persists '
      'when flipped', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AccessibilitySettingsPage(),
    ));
    await tester.pump();

    expect(find.text('High contrast'), findsOneWidget);
    final tileBefore =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'High contrast'));
    expect(tileBefore.value, isFalse);

    await tester.tap(find.text('High contrast'));
    await tester.pump();

    expect(AppSettings.instance.highContrastEnabled, isTrue);
    final tileAfter =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'High contrast'));
    expect(tileAfter.value, isTrue);
  });

  testWidgets('opening with highlightField: "high_contrast" scrolls to '
      'and flashes that row without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AccessibilitySettingsPage(highlightField: 'high_contrast'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('High contrast'), findsOneWidget);
  });
}
