import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/ui/settings/controls_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  tearDown(PlatformCapabilities.resetOverridesForTesting);

  Future<void> pumpControls(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ControlsSettingsPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows Gesture mode and Enable player gestures when not '
      'desktop-primary', (tester) async {
    PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
    await pumpControls(tester);

    expect(find.text('Gesture mode'), findsOneWidget);
    expect(find.text('Enable player gestures'), findsOneWidget);
    // Button layout and auto-hide nav are unrelated to swipe-as-a-shortcut
    // and must stay visible on every platform.
    expect(find.text('Button layout'), findsOneWidget);
    expect(find.text('Auto-hide bottom navigation'), findsOneWidget);
  });

  testWidgets(
      'hides Gesture mode and Enable player gestures entirely on a '
      'desktop-primary platform — swipe is not a shortcut desktop users '
      'reach for', (tester) async {
    PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
    await pumpControls(tester);

    expect(find.text('Gesture mode'), findsNothing);
    expect(find.text('Enable player gestures'), findsNothing);
    // Everything unrelated to swipe gestures stays put.
    expect(find.text('Button layout'), findsOneWidget);
    expect(find.text('Auto-hide bottom navigation'), findsOneWidget);
  });
}
