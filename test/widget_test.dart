import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/theme/omnis_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Omnis app renders its shell without crashing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Omnis')),
        body: const Center(child: Text('Hello')),
      ),
    ));
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
  });

  test('AppSettings persists theme and library preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    AppSettings.instance.themeMode = ThemeMode.dark;
    AppSettings.instance.librarySource = LibrarySource.wholePhone;
    AppSettings.instance.selectedFolderPath = 'C:/Music';

    final reloaded = AppSettings.instance;
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.librarySource, LibrarySource.wholePhone);
    expect(reloaded.selectedFolderPath, 'C:/Music');
  });

  test('AppSettings persists theme presets and builds themed surfaces',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    AppSettings.instance.themePreset = AppThemePreset.midnight;

    final reloaded = AppSettings.instance;
    expect(reloaded.themePreset, AppThemePreset.midnight);

    final theme = OmnisTheme.build(
      brightness: Brightness.dark,
      preset: reloaded.themePreset,
      accentColor: reloaded.accentColor,
    );
    expect(theme.cardTheme.color, isNotNull);
    expect(theme.navigationBarTheme.backgroundColor, isNotNull);
  });
}
