import 'package:flutter/material.dart';

/// The closed set of icon "renderings" a theme can pick between.
///
/// This is deliberately **not** icon-pack swapping (`docs/ARCHITECTURE.md`'s
/// "Out of scope for now" section is explicit that app icon-pack
/// swapping — trusting an externally-hosted image asset at runtime — isn't
/// implemented, and for good reason: an image asset can misrepresent
/// itself, balloon in size, or simply be inappropriate content in a way a
/// closed enum value can't). Every value here instead just selects which
/// one of the *same* glyph's four bundled renderings
/// (`Icons.xxx`/`Icons.xxx_outlined`/`Icons.xxx_rounded`/`Icons.xxx_sharp`)
/// to draw — all four already ship inside Flutter's own `MaterialIcons`
/// font (present because `pubspec.yaml` sets `uses-material-design: true`),
/// so picking one never fetches, downloads, or bundles anything new.
enum OmnisIconStyleKind { filled, outlined, rounded, sharp }

/// Single source of truth for the active [OmnisIconStyleKind] plus the
/// closed string vocabulary a declarative theme's `icons.style` field is
/// validated against — see [ThemeManifest]'s own doc comment (in
/// `lib/ui/theme/declarative/theme_manifest.dart`) for why that field
/// stays a fixed allow-list rather than an arbitrary string.
///
/// Mirrors [OmnisMotion.styleMultiplier] (`lib/ui/theme/omnis_motion.dart`)
/// exactly: a plain static field read directly by whatever widget needs
/// it, not a `BuildContext`-based lookup — this project deliberately has
/// no `InheritedWidget`/Provider/Riverpod plumbing (see that class's own
/// doc comment), so every icon call site just reads
/// `OmnisIconStyle.current` the same way every animation already reads
/// `OmnisMotion.styleMultiplier`.
class OmnisIconStyle {
  OmnisIconStyle._();

  /// `icons.style` values a theme file may name, mapped to the
  /// [OmnisIconStyleKind] each selects — the same
  /// "closed map, anything else falls back to the default" shape
  /// `OmnisTypography.allowedFonts` already uses for `typography.fontFamily`.
  static const Map<String, OmnisIconStyleKind> allowedStyles = {
    'filled': OmnisIconStyleKind.filled,
    'outlined': OmnisIconStyleKind.outlined,
    'rounded': OmnisIconStyleKind.rounded,
    'sharp': OmnisIconStyleKind.sharp,
  };

  /// The `icons.style` string a theme lacking that field (or naming an
  /// unrecognized value) falls back to — `'filled'` matches every icon's
  /// un-suffixed `Icons.xxx` constant, i.e. exactly what every call site
  /// already rendered before this field existed, so a theme silently
  /// missing this field never changes how the app looks.
  static const String defaultStyleKey = 'filled';

  /// Set by whatever applies the active theme (built-in default, or a
  /// declarative import's `icons.style`) — see
  /// `DeclarativeOmnisTheme.applyIconStyle`.
  static OmnisIconStyleKind current = OmnisIconStyleKind.filled;
}

/// One glyph's four bundled style renderings, so a call site can ask for
/// "the current style's version of this icon" instead of hand-writing a
/// switch at every call site. Every field must be a real `Icons.xxx`
/// constant reference (not looked up dynamically by string) so Flutter's
/// icon tree-shaker — which only keeps glyphs it can see referenced as a
/// literal constant — retains all four variants of every catalog entry.
class ThemedIcon {
  final IconData filled;
  final IconData outlined;
  final IconData rounded;
  final IconData sharp;

  const ThemedIcon({
    required this.filled,
    required this.outlined,
    required this.rounded,
    required this.sharp,
  });

  /// The glyph for [style] (defaults to [OmnisIconStyle.current]).
  IconData resolve([OmnisIconStyleKind? style]) {
    return switch (style ?? OmnisIconStyle.current) {
      OmnisIconStyleKind.filled => filled,
      OmnisIconStyleKind.outlined => outlined,
      OmnisIconStyleKind.rounded => rounded,
      OmnisIconStyleKind.sharp => sharp,
    };
  }
}
