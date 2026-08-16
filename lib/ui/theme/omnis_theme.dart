import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/theme/omnis_colors.dart';
import 'package:omnis/ui/theme/omnis_typography.dart';

/// Builds the app's [ThemeData] for a given brightness/preset/accent.
///
/// This used to be one long method inline in `AppSettings.themeData()`.
/// Pulled out here so a declarative (user-imported) theme
/// (`DeclarativeOmnisTheme`) can flow through the *exact same*
/// `ColorScheme`/typography/shape pipeline as a built-in preset via
/// [colorSchemeOverride]/[fontKey]/[cornerRadius] — rather than the app
/// needing two separate theme-building code paths that could drift apart.
/// `AppSettings.themeData()` is now a thin call into [build] with no
/// overrides, so every existing call site keeps working unchanged.
class OmnisTheme {
  OmnisTheme._();

  static ThemeData build({
    required Brightness brightness,
    required AppThemePreset preset,
    required Color accentColor,
    ColorScheme? colorSchemeOverride,
    String fontKey = OmnisTypography.defaultFont,
    double textScale = 1.0,
    double cornerRadius = 16,
    bool highContrast = false,
  }) {
    final base =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final isDark = brightness == Brightness.dark;

    final surfaceColor =
        isDark ? OmnisPalette.darkSurface : OmnisPalette.lightSurface;
    final elevatedColor =
        isDark ? OmnisPalette.darkElevated : OmnisPalette.lightElevated;
    // §58's "high contrast" requirement: every preset's default border is
    // a subtle, low-contrast tint against its surface — deliberately, for
    // a calm default look — so high contrast swaps it for a fully-opaque
    // near-black/near-white one instead of just nudging the alpha, the
    // same "opt into a real, visible change" stance every other border/
    // outline swap below takes.
    final borderColor = highContrast
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? OmnisPalette.darkBorder : OmnisPalette.lightBorder);

    final presetColors = switch (preset) {
      AppThemePreset.midnight => (
          primary: OmnisPalette.midnightPrimary,
          secondary: OmnisPalette.midnightSecondary
        ),
      AppThemePreset.aurora => (
          primary: OmnisPalette.auroraPrimary,
          secondary: OmnisPalette.auroraSecondary
        ),
      AppThemePreset.sunset => (
          primary: OmnisPalette.sunsetPrimary,
          secondary: OmnisPalette.sunsetSecondary
        ),
      AppThemePreset.classic => (
          primary: accentColor,
          secondary: accentColor.withValues(alpha: 0.7)
        ),
    };

    // `contrastLevel` is a real Material 3 mechanism (-1.0..1.0) for
    // exactly this — 1.0 is Material's own "maximum contrast" curve, not
    // a hand-picked value. Only applies when deriving from a seed color;
    // a caller-supplied [colorSchemeOverride] (a declarative custom
    // theme) is used as-is, the same "override wins outright" contract
    // every other [build] parameter already has for it.
    final themedScheme = colorSchemeOverride ??
        ColorScheme.fromSeed(
          seedColor: presetColors.primary,
          brightness: brightness,
          secondary: presetColors.secondary,
          contrastLevel: highContrast ? 1.0 : 0.0,
        );

    final radius = cornerRadius.clamp(0.0, 32.0);

    final textTheme = OmnisTypography.build(
      brightness: brightness,
      fontKey: fontKey,
      scale: textScale,
    ).apply(
      bodyColor: themedScheme.onSurface,
      displayColor: themedScheme.onSurface,
    );

    return base.copyWith(
        colorScheme: themedScheme,
        scaffoldBackgroundColor: surfaceColor,
        cardColor: elevatedColor,
        cardTheme: CardTheme(
          color: elevatedColor,
          elevation: 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(color: borderColor)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: surfaceColor,
          foregroundColor: themedScheme.onSurface,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: elevatedColor,
          indicatorColor: themedScheme.secondaryContainer,
          labelTextStyle:
              WidgetStatePropertyAll(TextStyle(color: themedScheme.onSurface)),
          iconTheme: WidgetStatePropertyAll(
              IconThemeData(color: themedScheme.onSurface)),
        ),
        dividerColor: borderColor,
        textTheme: textTheme,
        inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
                borderSide: BorderSide(color: borderColor),
                borderRadius: BorderRadius.circular(radius * 0.5))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                backgroundColor: themedScheme.primary,
                foregroundColor: themedScheme.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius * 0.6)))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: highContrast
                        ? themedScheme.primary
                        : themedScheme.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius * 0.6)))));
  }
}
