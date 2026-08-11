import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/l10n/generated/app_localizations.dart';
import 'package:omnis/ui/home_page.dart';
import 'package:omnis/ui/onboarding/onboarding_page.dart';
import 'package:omnis/ui/theme/declarative/declarative_omnis_theme.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/theme/omnis_theme.dart';

export 'package:omnis/core/bootstrap.dart' show ensureCoreReady, locator;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only AppSettings is awaited before the first frame — it's a single
  // SharedPreferences read, fast enough that skipping it would just
  // trade one flicker (default theme, then a jump to the real one) for
  // another. The heavy part of startup — the audio engine, plugin
  // manager, and installed-plugin/layout disk I/O inside ensureCoreReady
  // and ensureLayoutManagerReady — used to run here too, which meant the
  // OS saw nothing but a blank window until all of it finished. Neither
  // is needed to paint the first frame: HomePage already gates on
  // _coreReady (a plain spinner, not a branded splash) and calls both
  // itself in initState, so they now run *after* something is on screen
  // instead of *before*.
  await AppSettings.instance.initialize();
  runApp(const OmnisApp());
}

/// Main Omnis application.
class OmnisApp extends StatefulWidget {
  const OmnisApp({super.key});

  @override
  State<OmnisApp> createState() => _OmnisAppState();
}

class _OmnisAppState extends State<OmnisApp> {
  ThemeManager? _themeManager;
  StreamSubscription<List<ThemeManifest>>? _themesSub;

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_refresh);
    _loadThemeManager();
  }

  // Fire-and-forget, same "flicker once, then correct" tradeoff this
  // file's own top comment already accepts for AppSettings — a custom
  // theme (if any) applies a frame or two after first paint instead of
  // main() blocking on plugin-backed disk I/O before the first frame.
  Future<void> _loadThemeManager() async {
    final manager = await ensureThemeManagerReady();
    if (!mounted) return;
    setState(() => _themeManager = manager);
    _themesSub = manager.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_refresh);
    _themesSub?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final customId = settings.customThemeId;
    final customTheme =
        customId == null ? null : _themeManager?.resolve(customId);

    if (customTheme != null) {
      DeclarativeOmnisTheme.applyMotionStyle(customTheme);
    } else {
      OmnisMotion.styleMultiplier = 1.0;
    }

    // A declarative theme commits to one brightness (its `brightness:`
    // field) rather than offering separate light/dark variants — so when
    // one is active, both `theme` and `darkTheme` render it identically
    // and `themeMode`'s light/dark distinction is moot until the user
    // clears `customThemeId` and goes back to a built-in preset.
    final lightTheme = customTheme != null
        ? DeclarativeOmnisTheme.build(customTheme)
        : OmnisTheme.build(
            brightness: Brightness.light,
            preset: settings.themePreset,
            accentColor: settings.accentColor,
          );
    final darkTheme = customTheme != null
        ? DeclarativeOmnisTheme.build(customTheme)
        : OmnisTheme.build(
            brightness: Brightness.dark,
            preset: settings.themePreset,
            accentColor: settings.accentColor,
          );

    return MaterialApp(
      title: 'Omnis Music Engine',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      // Scaffolding only for now (English-only, see l10n.yaml/lib/l10n/) —
      // wired through the new Settings search and onboarding screens,
      // not retrofitted across the rest of the app yet.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Evaluated once, at cold start — correct for a "gate the very
      // first launch" flow. OnboardingPage's own finish action navigates
      // onward via pushReplacement rather than relying on this rebuilding.
      home: settings.hasCompletedOnboarding
          ? const HomePage()
          : const OnboardingPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
