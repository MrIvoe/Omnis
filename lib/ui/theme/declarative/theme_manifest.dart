import 'package:flutter/material.dart';
import 'package:omnis/ui/theme/omnis_icon_style.dart';
import 'package:omnis/ui/theme/omnis_typography.dart';
import 'package:yaml/yaml.dart';

/// The three motion "speeds" a declarative theme can pick from — a fixed
/// preset, not an arbitrary duration/curve pair. See [ThemeManifest]'s
/// doc comment for why that closed-set discipline matters.
enum ThemeMotionStyle { standard, snappy, gentle }

/// A parsed, user-authored theme description.
///
/// Mirrors `LayoutManifest` exactly: a single flat YAML/JSON file
/// describing a **fixed, closed** set of targets — a `ColorScheme` role,
/// a font from [OmnisTypography.allowedFonts], a [ThemeMotionStyle]
/// preset — never raw Dart code, an arbitrary asset path, or a network
/// URL beyond the initial fetch. That's what makes a theme file safely
/// importable with no sandbox, no permission dialog, and no code
/// execution: it cannot describe anything [DeclarativeOmnisTheme] doesn't
/// already know how to build, the same guarantee `layout_manifest.dart`
/// documents for layouts. Resist adding a "custom font URL" or "custom
/// animation curve" field — either would reopen the sandboxing question
/// this closed-schema design exists to avoid.
///
/// ### File format (`omnis_theme.yaml`)
///
/// ```yaml
/// id: sunset_glass
/// name: Sunset Glass
/// description: Warm gradient theme with frosted surfaces
/// author: Your Name
/// version: 1.0.0
/// brightness: dark                # 'dark' | 'light'
/// colors:
///   primary: "#FF6B6B"
///   secondary: "#4ECDC4"
///   surface: "#1A1A2E"
///   background: "#16213E"
///   error: "#FF3860"
///   onPrimary: "#FFFFFF"
///   onSurface: "#EAEAEA"
/// typography:
///   fontFamily: poppins            # a key of OmnisTypography.allowedFonts
///   scale: 1.0                     # clamped to 0.8–1.3
/// shape:
///   cornerRadius: 16               # clamped to 0–32
/// motion:
///   style: standard                # 'standard' | 'snappy' | 'gentle'
/// icons:
///   style: filled                  # 'filled' | 'outlined' | 'rounded' | 'sharp'
/// background:                      # optional
///   type: gradient                 # 'color' | 'gradient'
///   colors: ["#16213E", "#0F0F1E"]
/// ```
class ThemeManifest {
  final String id;
  final String name;
  final String description;
  final String author;
  final String version;
  final Brightness brightness;

  /// Only the recognized `ColorScheme` role names below survive parsing —
  /// any other key in the file's `colors:` map is silently dropped, not
  /// an error, the same "unknown things are ignored, not rejected"
  /// posture `DeclarativeLayoutRenderer` takes on an unrecognized
  /// component type.
  final Map<String, Color> colors;

  final String fontKey;
  final double textScale;
  final double cornerRadius;
  final ThemeMotionStyle motionStyle;

  /// A key of [OmnisIconStyle.allowedStyles] — which of a glyph's four
  /// bundled renderings (filled/outlined/rounded/sharp) `icons.style`
  /// selects for [OmnisIconCatalog]-driven call sites. Closed vocabulary,
  /// same discipline as [fontKey]: any value [parse] doesn't recognize
  /// falls back to [OmnisIconStyle.defaultStyleKey] rather than being
  /// rejected outright, and never opens the door to a "custom icon pack"
  /// field — see this class's own doc comment.
  final String iconStyle;

  /// `{'type': 'color'|'gradient', 'colors': ['#...', ...]}` — same shape
  /// `LayoutManifest.background` already uses, reused rather than
  /// reinvented. Interpreted by whatever renders Now Playing's
  /// background, not by this class.
  final Map<String, dynamic>? background;

  /// Where this was installed from (a URL, or `local`/`file://...`).
  final String sourceUrl;

  const ThemeManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.version,
    required this.brightness,
    required this.colors,
    required this.fontKey,
    required this.textScale,
    required this.cornerRadius,
    required this.motionStyle,
    required this.iconStyle,
    required this.background,
    required this.sourceUrl,
  });

  /// The closed set of `colors:` keys this recognizes — every one maps
  /// 1:1 to a [ColorScheme] role consumed by [DeclarativeOmnisTheme].
  static const recognizedColorKeys = {
    'primary',
    'secondary',
    'surface',
    'background',
    'error',
    'onPrimary',
    'onSecondary',
    'onSurface',
    'onError',
  };

  /// Parse a theme file's raw text (YAML or JSON). Returns `null` for
  /// anything that doesn't have at least `id`, `name`, and a `primary`
  /// color — never throws.
  static ThemeManifest? parse(String text, {required String sourceUrl}) {
    try {
      final doc = loadYaml(text);
      if (doc is! Map) return null;
      final id = _asString(doc['id']);
      final name = _asString(doc['name']);
      final colorsRaw = doc['colors'];
      if (id == null || id.isEmpty || name == null || colorsRaw is! Map) {
        return null;
      }

      final colors = <String, Color>{};
      for (final key in recognizedColorKeys) {
        final hex = _asString(colorsRaw[key]);
        final color = hex == null ? null : _parseHexColor(hex);
        if (color != null) colors[key] = color;
      }
      if (!colors.containsKey('primary')) return null;

      final typography = doc['typography'];
      final rawFontKey = typography is Map ? _asString(typography['fontFamily']) : null;
      final fontKey = (rawFontKey != null &&
              OmnisTypography.allowedFonts.containsKey(rawFontKey))
          ? rawFontKey
          : OmnisTypography.defaultFont;
      final rawScale =
          typography is Map ? _asDouble(typography['scale']) : null;
      final textScale = (rawScale ?? 1.0).clamp(0.8, 1.3);

      final shape = doc['shape'];
      final rawRadius = shape is Map ? _asDouble(shape['cornerRadius']) : null;
      final cornerRadius = (rawRadius ?? 16.0).clamp(0.0, 32.0);

      final motion = doc['motion'];
      final rawStyle = motion is Map ? _asString(motion['style']) : null;
      final motionStyle = switch (rawStyle) {
        'snappy' => ThemeMotionStyle.snappy,
        'gentle' => ThemeMotionStyle.gentle,
        _ => ThemeMotionStyle.standard,
      };

      final icons = doc['icons'];
      final rawIconStyle = icons is Map ? _asString(icons['style']) : null;
      final iconStyle = (rawIconStyle != null &&
              OmnisIconStyle.allowedStyles.containsKey(rawIconStyle))
          ? rawIconStyle
          : OmnisIconStyle.defaultStyleKey;

      return ThemeManifest(
        id: id,
        name: name,
        description: _asString(doc['description']) ?? 'No description',
        author: _asString(doc['author']) ?? 'Unknown',
        version: _asString(doc['version']) ?? '0.0.1',
        brightness: _asString(doc['brightness']) == 'light'
            ? Brightness.light
            : Brightness.dark,
        colors: colors,
        fontKey: fontKey,
        textScale: textScale.toDouble(),
        cornerRadius: cornerRadius.toDouble(),
        motionStyle: motionStyle,
        iconStyle: iconStyle,
        background: _asMap(doc['background']),
        sourceUrl: sourceUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _asString(dynamic value) => value is String ? value : null;

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static Color? _parseHexColor(String hex) {
    var normalized = hex.trim();
    if (normalized.startsWith('#')) normalized = normalized.substring(1);
    if (normalized.length == 6) normalized = 'FF$normalized';
    if (normalized.length != 8) return null;
    final value = int.tryParse(normalized, radix: 16);
    return value == null ? null : Color(value);
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    final converted = _deepConvert(value);
    return converted is Map<String, dynamic> ? converted : null;
  }

  static dynamic _deepConvert(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _deepConvert(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _deepConvert(item)];
    }
    return value;
  }
}
