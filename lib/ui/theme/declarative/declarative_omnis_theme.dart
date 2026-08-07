import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/theme/omnis_theme.dart';

/// Adapts a parsed [ThemeManifest] into the [ThemeData] built by
/// [OmnisTheme] — an imported theme flows through the *exact same*
/// `ColorScheme`/typography/shape pipeline as a built-in preset via
/// [OmnisTheme.build]'s override parameters, so nothing else in the app
/// ever needs to special-case "is this theme declarative or built-in,"
/// matching `DeclarativeLayout`'s own stated goal for layouts.
class DeclarativeOmnisTheme {
  DeclarativeOmnisTheme._();

  static ThemeData build(ThemeManifest manifest) {
    final scheme = _colorScheme(manifest);
    return OmnisTheme.build(
      brightness: manifest.brightness,
      // `preset`/`accentColor` are irrelevant once `colorSchemeOverride`
      // is supplied — `OmnisTheme.build` only falls back to deriving a
      // scheme from them when the override is null. `classic` + the
      // manifest's own primary keeps the two in sync regardless.
      preset: AppThemePreset.classic,
      accentColor: manifest.colors['primary'] ?? Colors.deepPurple,
      colorSchemeOverride: scheme,
      fontKey: manifest.fontKey,
      textScale: manifest.textScale,
      cornerRadius: manifest.cornerRadius,
    );
  }

  /// Applies [manifest]'s motion style globally (see
  /// `OmnisMotion.styleMultiplier`) — call this whenever [manifest]
  /// becomes the active theme, not from [build] itself, since [build] can
  /// be called speculatively (e.g. a settings preview) without actually
  /// switching the app's motion feel.
  static void applyMotionStyle(ThemeManifest manifest) {
    OmnisMotion.styleMultiplier = switch (manifest.motionStyle) {
      ThemeMotionStyle.snappy => 0.6,
      ThemeMotionStyle.gentle => 1.6,
      ThemeMotionStyle.standard => 1.0,
    };
  }

  /// Builds a full [ColorScheme] from [manifest]'s (partial, closed-set)
  /// `colors:` map — `ColorScheme.fromSeed` on the required `primary`
  /// fills in every role the manifest didn't specify, then `copyWith`
  /// overrides exactly the roles it did, so a minimal theme file (just
  /// `primary`) still produces a complete, usable scheme.
  static ColorScheme _colorScheme(ThemeManifest manifest) {
    final colors = manifest.colors;
    final seeded = ColorScheme.fromSeed(
      seedColor: colors['primary']!,
      brightness: manifest.brightness,
      secondary: colors['secondary'],
    );
    return seeded.copyWith(
      primary: colors['primary'],
      secondary: colors['secondary'],
      surface: colors['surface'],
      error: colors['error'],
      onPrimary: colors['onPrimary'],
      onSecondary: colors['onSecondary'],
      onSurface: colors['onSurface'],
      onError: colors['onError'],
    );
  }
}
