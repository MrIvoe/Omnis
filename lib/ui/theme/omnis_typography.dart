import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// `google_fonts`-based [TextTheme] builder, layered over Material's
/// default type scale rather than replacing it outright — every
/// `GoogleFonts.xTextTheme` helper only swaps `fontFamily`/weights on the
/// [TextTheme] it's handed and leaves `fontSize` alone, so system
/// text-scale (`MediaQuery.textScaler`) keeps working exactly as it does
/// for the un-fonted default theme.
class OmnisTypography {
  OmnisTypography._();

  /// Fonts selectable from a declarative (user-imported) theme's
  /// `typography.fontFamily` field — a **closed allow-list**, not an
  /// arbitrary Google Fonts name. Letting a theme manifest name any font
  /// string would mean fetching an arbitrary font file at theme-load time
  /// from wherever `google_fonts` decides to resolve it, which reopens
  /// exactly the "network access from a data file" question
  /// `ThemeManifest`'s closed-schema design exists to avoid — see its doc
  /// comment.
  static final Map<String, TextTheme Function(TextTheme)> allowedFonts = {
    'inter': (t) => GoogleFonts.interTextTheme(t),
    'poppins': (t) => GoogleFonts.poppinsTextTheme(t),
    'roboto': (t) => GoogleFonts.robotoTextTheme(t),
    'manrope': (t) => GoogleFonts.manropeTextTheme(t),
    'jetbrainsMono': (t) => GoogleFonts.jetBrainsMonoTextTheme(t),
  };

  static const String defaultFont = 'inter';

  /// Builds a [TextTheme] for [brightness] using [fontKey] (falls back to
  /// [defaultFont] if it's not a key of [allowedFonts]), scaled by [scale]
  /// — a declarative theme's `typography.scale`, expected to already be
  /// clamped to a sane range by [ThemeManifest.parse] before it reaches
  /// here.
  static TextTheme build({
    required Brightness brightness,
    String fontKey = defaultFont,
    double scale = 1.0,
  }) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;
    final withFont = (allowedFonts[fontKey] ?? allowedFonts[defaultFont]!)(base);
    if (scale == 1.0) return withFont;
    return withFont.apply(fontSizeFactor: scale);
  }
}
