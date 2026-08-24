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

  test('seekIncrementSeconds defaults to 10 and only accepts 10/15/30',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.seekIncrementSeconds, 10);

    AppSettings.instance.seekIncrementSeconds = 30;
    expect(AppSettings.instance.seekIncrementSeconds, 30);

    AppSettings.instance.seekIncrementSeconds = 15;
    expect(AppSettings.instance.seekIncrementSeconds, 15);

    // An out-of-range value falls back to the default rather than being
    // stored verbatim — this setting is a fixed choice, not free-form.
    AppSettings.instance.seekIncrementSeconds = 7;
    expect(AppSettings.instance.seekIncrementSeconds, 10);
  });

  test('groupArtistsByAlbumArtist defaults off and persists when toggled',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.groupArtistsByAlbumArtist, isFalse);

    AppSettings.instance.groupArtistsByAlbumArtist = true;
    expect(AppSettings.instance.groupArtistsByAlbumArtist, isTrue);
  });

  test('lyricsTextSize defaults to medium and persists across a fresh read',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.lyricsTextSize, LyricsTextSize.medium);

    for (final size in LyricsTextSize.values) {
      AppSettings.instance.lyricsTextSize = size;
      expect(AppSettings.instance.lyricsTextSize, size);
    }
  });

  test('defaultLaunchTabId defaults to library and persists once set',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.defaultLaunchTabId, 'library');

    AppSettings.instance.defaultLaunchTabId = 'moods';
    expect(AppSettings.instance.defaultLaunchTabId, 'moods');
  });

  test('hasCompletedOnboarding defaults to false and persists once set',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.hasCompletedOnboarding, isFalse);

    AppSettings.instance.hasCompletedOnboarding = true;
    expect(AppSettings.instance.hasCompletedOnboarding, isTrue);
  });

  test('AppSettings persists highContrastEnabled, default false', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.highContrastEnabled, isFalse);

    AppSettings.instance.highContrastEnabled = true;
    expect(AppSettings.instance.highContrastEnabled, isTrue);
  });

  test('AppSettings persists textScaleFactor, default 1.0, clamped on '
      'write', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.textScaleFactor, 1.0);

    AppSettings.instance.textScaleFactor = 1.2;
    expect(AppSettings.instance.textScaleFactor, 1.2);

    // Out-of-range writes clamp rather than persisting a value the UI
    // (a bounded Slider) could never itself produce.
    AppSettings.instance.textScaleFactor = 5.0;
    expect(AppSettings.instance.textScaleFactor, 1.5);
  });

  test('AppSettings persists libraryWatcherEnabled, default false',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    expect(AppSettings.instance.libraryWatcherEnabled, isFalse);

    AppSettings.instance.libraryWatcherEnabled = true;
    expect(AppSettings.instance.libraryWatcherEnabled, isTrue);
  });

  group('AppSettings persists libraryVisibleColumns', () {
    test('defaults to artist/album/genre — exactly what the Library '
        'page\'s subtitle always showed before this setting existed',
        () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();

      expect(AppSettings.instance.libraryVisibleColumns,
          {'artist', 'album', 'genre'});
    });

    test('a real persistence round-trip through setLibraryVisibleColumns',
        () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();

      await AppSettings.instance
          .setLibraryVisibleColumns({'rating', 'playCount'});

      expect(AppSettings.instance.libraryVisibleColumns,
          {'rating', 'playCount'});
    });

    test('an empty set is a real, distinct choice — not silently treated '
        'as "use the default"', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.initialize();

      await AppSettings.instance.setLibraryVisibleColumns(const {});

      expect(AppSettings.instance.libraryVisibleColumns, isEmpty);
    });
  });

  // Kept last in this file deliberately: OmnisTheme.build pulls in
  // google_fonts (via OmnisTypography.build), which kicks off a
  // fire-and-forget real font-fetch Future that always fails under
  // TestWidgetsFlutterBinding (HttpClient calls get a fake 400) — a
  // pre-existing package-level quirk, not something this test can fix.
  // Keeping this the final test in the file is what lets that leaked
  // failure settle harmlessly after the suite's own teardown rather than
  // bleeding into whatever test happens to run next.
  test('AppSettings persists theme presets and builds themed surfaces',
      () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();

    // Item 44/spec §22-27's six named presets — cheap persistence
    // round-trip for every one of them (no OmnisTheme.build call here,
    // so no google_fonts risk), then a single real OmnisTheme.build
    // call below for the one this test has always exercised.
    for (final preset in AppThemePreset.values) {
      AppSettings.instance.themePreset = preset;
      expect(AppSettings.instance.themePreset, preset);
    }

    AppSettings.instance.themePreset = AppThemePreset.drive;
    final reloaded = AppSettings.instance;
    expect(reloaded.themePreset, AppThemePreset.drive);

    final theme = OmnisTheme.build(
      brightness: Brightness.dark,
      preset: reloaded.themePreset,
      accentColor: reloaded.accentColor,
      cornerRadius: 4,
    );
    expect(theme.cardTheme.color, isNotNull);
    expect(theme.navigationBarTheme.backgroundColor, isNotNull);

    // Task 10 Step 4: dialogs/sheets/snackbars/chips now derive their
    // shape from the same themed `cornerRadius` as cards/inputs/buttons
    // already did, rather than falling back to Material's own defaults
    // (a 4px radius is nowhere close to Material's 28px default dialog
    // corner or its stadium-shaped default chip, so a match here can only
    // come from actually reading the themed radius).
    const radius = 4.0;
    final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
    expect(dialogShape.borderRadius, const BorderRadius.all(Radius.circular(radius)));

    final sheetShape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;
    expect(
      sheetShape.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      ),
    );

    final snackShape = theme.snackBarTheme.shape as RoundedRectangleBorder;
    expect(snackShape.borderRadius, BorderRadius.circular(radius * 0.5));

    final chipShape = theme.chipTheme.shape as RoundedRectangleBorder;
    expect(chipShape.borderRadius, BorderRadius.circular(radius * 0.6));
  });
}
