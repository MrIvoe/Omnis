import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/theme/declarative/theme_editor_page.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/theme/omnis_typography.dart';
import 'package:omnis/ui/widgets/color_picker_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same fake path_provider pattern as layout_editor_page_test.dart, so
/// ThemeManager's real installFromText -> ThemeInstaller -> disk path
/// runs against a throwaway temp directory instead of the real one.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

/// A font-network-free stand-in for [DeclarativeOmnisTheme.build], passed
/// as [ThemeEditorPage.previewThemeBuilder] in every test here. The real
/// builder flows through `OmnisTypography.build` -> `google_fonts`, which
/// attempts a genuine network fetch that this sandboxed test environment
/// can never complete — see [ThemeEditorPage.previewThemeBuilder]'s own
/// doc comment for the full story. This still exercises the exact
/// `ColorScheme.fromSeed(...).copyWith(...)` derivation
/// `DeclarativeOmnisTheme.build` itself uses, so a color picker's effect
/// on the live preview is still proven against real production logic —
/// only the font-loading half is swapped out.
ThemeData _fakePreviewTheme(ThemeManifest manifest) {
  final colors = manifest.colors;
  final scheme = ColorScheme.fromSeed(
    seedColor: colors['primary']!,
    brightness: manifest.brightness,
    secondary: colors['secondary'],
  ).copyWith(
    primary: colors['primary'],
    secondary: colors['secondary'],
    surface: colors['surface'],
    error: colors['error'],
    onPrimary: colors['onPrimary'],
    onSecondary: colors['onSecondary'],
    onSurface: colors['onSurface'],
    onError: colors['onError'],
  );
  final base = manifest.brightness == Brightness.dark
      ? ThemeData.dark()
      : ThemeData.light();
  return base.copyWith(colorScheme: scheme);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;
  late ThemeManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir =
        (await Directory.systemTemp.createTemp('omnis_theme_editor_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    manager = ThemeManager();
    await manager.loadInstalled();
  });

  // A much taller-than-default viewport, the same "give the page enough
  // room instead of scrolling around a too-short one" fix this project's
  // own test suite already uses elsewhere (e.g. playlist_page_test.dart)
  // — `theme_editor_controls_list` is a plain `ListView(children: [...])`
  // (not `.builder`), and at the default 800x600 test size most of its
  // rows sit below the fold *and* outside the sliver's cache extent, so
  // they're not really built yet at all; `tester.ensureVisible`/
  // `tester.scrollUntilVisible` both proved unreliable against that (the
  // latter threw a spurious "Bad state: No element" even for a
  // demonstrably-existing near-top target) — a tall enough viewport
  // sidesteps the whole scroll-simulation question by making every
  // control simply present without needing to scroll to it at all.
  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ThemeEditorPage(
          themeManager: manager, previewThemeBuilder: _fakePreviewTheme),
    ));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Finder sliderFor(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Slider),
      );

  // Every control already fits on-screen at pumpEditor's tall viewport —
  // this now just hands the finder back unchanged, kept as a named step
  // (rather than inlining `find.byKey(...)` everywhere below) so a
  // future genuinely-scrolling need has one place to add it back.
  Future<Finder> scrollTo(WidgetTester tester, Finder finder) async {
    return finder;
  }

  testWidgets('renders one color picker per ThemeManifest.recognizedColorKeys',
      (tester) async {
    await pumpEditor(tester);

    for (final key in ThemeManifest.recognizedColorKeys) {
      final finder = await scrollTo(
          tester, find.byKey(ValueKey('theme_color_$key')));
      expect(finder, findsOneWidget,
          reason: 'missing a picker for the "$key" role');
    }
  });

  testWidgets(
      'font dropdown only offers keys from OmnisTypography.allowedFonts, '
      'never a free-text value', (tester) async {
    await pumpEditor(tester);

    final finder =
        await scrollTo(tester, find.byKey(const ValueKey('font_dropdown')));
    final dropdown = tester.widget<DropdownButton<String>>(finder);
    final offered = dropdown.items!.map((item) => item.value).toSet();

    expect(offered, OmnisTypography.allowedFonts.keys.toSet());
    expect(dropdown.value, OmnisTypography.defaultFont,
        reason: 'defaults to the same fallback ThemeManifest.parse uses');
  });

  testWidgets('choosing a preset color for Primary updates the live preview',
      (tester) async {
    await pumpEditor(tester);

    final before = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(before.color, isNot(Colors.blue));

    await tester
        .tap(await scrollTo(tester, find.byKey(const ValueKey('theme_color_primary'))));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Blue'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final after = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(after.color, Colors.blue,
        reason: 'the preview\'s progress bar is painted with '
            'colorScheme.primary, which should now be the picked color');
  });

  testWidgets('a hex color entry is reflected in the live preview',
      (tester) async {
    await pumpEditor(tester);

    await tester
        .tap(await scrollTo(tester, find.byKey(const ValueKey('theme_color_primary'))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('color_picker_hex_field')), '#123456');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.color, const Color(0xFF123456));
  });

  testWidgets('text scale slider stays clamped to 0.8-1.3 even dragged '
      'far past either edge', (tester) async {
    await pumpEditor(tester);
    final slider = await scrollTo(tester, sliderFor('scale_slider'));

    await tester.drag(slider, const Offset(-5000, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, closeTo(0.8, 0.001));

    await tester.drag(slider, const Offset(5000, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, closeTo(1.3, 0.001));
  });

  testWidgets(
      'corner radius slider stays clamped to 0-32 even dragged far past '
      'either edge', (tester) async {
    await pumpEditor(tester);
    final slider = await scrollTo(tester, sliderFor('corner_radius_slider'));

    await tester.drag(slider, const Offset(-5000, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, closeTo(0, 0.001));

    await tester.drag(slider, const Offset(5000, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, closeTo(32, 0.001));
  });

  testWidgets(
      'a gradient background starts with two stops and neither can be '
      'removed below that; Add stop adds a third that can', (tester) async {
    await pumpEditor(tester);

    await tester.tap(
        await scrollTo(tester, find.byKey(const ValueKey('background_toggle'))));
    await tester.pump();
    await tester.tap(await scrollTo(
        tester,
        find.descendant(
            of: find.byKey(const ValueKey('background_type_selector')),
            matching: find.text('Gradient'))));
    await tester.pump();

    expect(find.byKey(const ValueKey('background_gradient_stop_0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('background_gradient_stop_1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('background_gradient_stop_2')),
        findsNothing);
    expect(find.byKey(const ValueKey('remove_gradient_stop_0')), findsNothing,
        reason: 'exactly the minimum 2 stops — neither is removable');

    await tester.tap(await scrollTo(
        tester, find.byKey(const ValueKey('add_gradient_stop_button'))));
    await tester.pump();

    expect(find.byKey(const ValueKey('background_gradient_stop_2')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('remove_gradient_stop_0')), findsOneWidget,
        reason: 'above the minimum now, so stops become removable');
  });

  testWidgets('Save is refused with an empty name', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, '');

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Give your theme a name.'), findsOneWidget);
    expect(find.byType(ThemeEditorPage), findsOneWidget);
  });

  testWidgets(
      'Save builds a manifest that round-trips exactly through '
      'ThemeManifest.parse, installs it, and selects it', (tester) async {
    // Same tall-viewport reasoning as pumpEditor — this test builds its
    // own widget tree (via Navigator.push) instead of using that helper,
    // so it needs the same fix applied directly.
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ThemeEditorPage(
                themeManager: manager, previewThemeBuilder: _fakePreviewTheme),
          )),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Name.
    await tester.enterText(
        find.byType(TextField).first, 'My Round Trip Theme');
    await tester.pump();

    // Brightness -> light.
    await tester.tap(await scrollTo(
        tester,
        find.descendant(
            of: find.byKey(const ValueKey('brightness_toggle')),
            matching: find.text('Light'))));
    await tester.pump();

    // Every recognized color role gets its own distinct, deterministic
    // hex value via the dialog's hex-entry field, so the round trip can
    // be asserted exactly rather than approximately.
    const testHexes = {
      'primary': '#112233',
      'secondary': '#223344',
      'surface': '#334455',
      'background': '#445566',
      'error': '#556677',
      'onPrimary': '#667788',
      'onSecondary': '#778899',
      'onSurface': '#8899AA',
      'onError': '#99AABB',
    };
    for (final entry in testHexes.entries) {
      await tester.tap(await scrollTo(
          tester, find.byKey(ValueKey('theme_color_${entry.key}'))));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('color_picker_hex_field')), entry.value);
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
    }

    // Font.
    await tester
        .tap(await scrollTo(tester, find.byKey(const ValueKey('font_dropdown'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poppins').last);
    await tester.pumpAndSettle();

    // Text scale -> drag to the max (1.3), then read back whatever the
    // slider actually settled on rather than assuming an exact value.
    final scaleSlider = await scrollTo(tester, sliderFor('scale_slider'));
    await tester.drag(scaleSlider, const Offset(5000, 0));
    await tester.pump();
    final expectedScale = tester.widget<Slider>(scaleSlider).value;

    // Corner radius -> drag to the min (0).
    final radiusSlider =
        await scrollTo(tester, sliderFor('corner_radius_slider'));
    await tester.drag(radiusSlider, const Offset(-5000, 0));
    await tester.pump();
    final expectedRadius = tester.widget<Slider>(radiusSlider).value;

    // Motion style -> snappy.
    await tester.tap(await scrollTo(
        tester,
        find.descendant(
            of: find.byKey(const ValueKey('motion_selector')),
            matching: find.text('Snappy'))));
    await tester.pump();

    // Background -> gradient, two stops with their own distinct hexes.
    await tester.tap(await scrollTo(
        tester, find.byKey(const ValueKey('background_toggle'))));
    await tester.pump();
    await tester.tap(await scrollTo(
        tester,
        find.descendant(
            of: find.byKey(const ValueKey('background_type_selector')),
            matching: find.text('Gradient'))));
    await tester.pump();

    await tester.tap(await scrollTo(
        tester, find.byKey(const ValueKey('background_gradient_stop_0'))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('color_picker_hex_field')), '#AABBCC');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    await tester.tap(await scrollTo(
        tester, find.byKey(const ValueKey('background_gradient_stop_1'))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('color_picker_hex_field')), '#DDEEFF');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final before = manager.allThemes.length;

    // Save triggers real dart:io File writes (ThemeInstaller ->
    // RemoteTextStore.persist, against the faked path_provider temp
    // dir) — same runAsync shape layout_editor_page_test.dart's own
    // save test already established for this exact reason.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(manager.allThemes.length, before + 1);
    final saved =
        manager.allThemes.firstWhere((t) => t.name == 'My Round Trip Theme');

    // Every field round-trips exactly through the real
    // ThemeManifest.parse the save flow validated against, not just
    // whatever the in-memory editor state happened to hold.
    expect(saved.brightness, Brightness.light);
    for (final entry in testHexes.entries) {
      expect(saved.colors[entry.key],
          ColorPickerDialog.colorFromHex(entry.value),
          reason: 'color role "${entry.key}" did not round-trip');
    }
    expect(saved.fontKey, 'poppins');
    expect(saved.textScale, closeTo(expectedScale, 0.001));
    expect(saved.cornerRadius, closeTo(expectedRadius, 0.001));
    expect(saved.motionStyle, ThemeMotionStyle.snappy);
    expect(saved.background, isNotNull);
    expect(saved.background!['type'], 'gradient');
    final bgColors = (saved.background!['colors'] as List).cast<String>();
    expect(bgColors, ['#AABBCC', '#DDEEFF']);

    // Selected as the active custom theme, and the editor popped.
    expect(AppSettings.instance.customThemeId, saved.id);
    expect(find.byType(ThemeEditorPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
