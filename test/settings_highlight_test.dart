import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  Color? backgroundOf(WidgetTester tester, Finder finder) {
    final box = tester.widget<DecoratedBox>(finder);
    final decoration = box.decoration as BoxDecoration;
    return decoration.color;
  }

  testWidgets('starts transparent and flash() decays back to transparent',
      (tester) async {
    final key = GlobalKey<SettingsHighlightState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsHighlight(key: key, child: const Text('Row')),
      ),
    ));

    final finder = find.byType(DecoratedBox);
    expect(backgroundOf(tester, finder), Colors.transparent);

    key.currentState!.flash();
    await tester.pump(); // apply value=1.0
    expect(backgroundOf(tester, finder), isNot(Colors.transparent));

    await tester.pumpAndSettle();
    expect(backgroundOf(tester, finder), Colors.transparent);
  });

  testWidgets(
      'with reduce motion enabled, flash() still shows visible feedback '
      'instead of no feedback at all', (tester) async {
    AppSettings.instance.reduceMotionEnabled = true;
    final key = GlobalKey<SettingsHighlightState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsHighlight(key: key, child: const Text('Row')),
      ),
    ));

    final finder = find.byType(DecoratedBox);
    key.currentState!.flash();
    await tester.pump();

    // Reduced motion collapses the decay to a hold-then-drop rather than
    // an animated fade — but "row briefly highlighted" must still happen,
    // not silently do nothing.
    expect(backgroundOf(tester, finder), isNot(Colors.transparent));

    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(backgroundOf(tester, finder), Colors.transparent);
  });

  testWidgets('scrollToAndFlashSetting is a no-op with a null key',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(() => scrollToAndFlashSetting(null), returnsNormally);
  });
}
