import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Static, non-dynamic color palette for each built-in theme preset —
/// pulled out of what used to be inline in `AppSettings.themeData()` so
/// [OmnisTheme] and a declarative (user-imported) theme both build off the
/// same named colors instead of duplicating the hex values.
class OmnisPalette {
  OmnisPalette._();

  static const midnightPrimary = Color(0xFF7C93FF);
  static const midnightSecondary = Color(0xFF5DE2FF);
  static const auroraPrimary = Color(0xFF26C281);
  static const auroraSecondary = Color(0xFF6D8CFF);
  static const sunsetPrimary = Color(0xFFFF8A4C);
  static const sunsetSecondary = Color(0xFFFF5F7D);

  static const darkSurface = Color(0xFF101218);
  static const darkElevated = Color(0xFF171A22);
  static const darkBorder = Color(0xFF2A3040);
  static const lightSurface = Color(0xFFF7F7FB);
  static const lightElevated = Colors.white;
  static const lightBorder = Color(0xFFE7EAF5);
}

/// Derives a [ColorScheme] from a track's album artwork, so Now Playing
/// can tint itself to match what's on screen — Android 12-style "dynamic
/// color," but seeded from art instead of wallpaper.
///
/// Extraction genuinely costs something (`palette_generator` decodes and
/// samples the whole image), so every result is cached by track id +
/// brightness. Now Playing rebuilds on every playback position tick; this
/// must never re-run on those rebuilds, only once per track actually
/// changing.
class DynamicColorExtractor {
  DynamicColorExtractor._();

  static final Map<String, Future<ColorScheme?>> _cache = {};

  /// Extracts a [ColorScheme] from [artBytes] (the same JPEG/PNG bytes
  /// `ArtworkProvider.forTrack` already resolves), cached by [trackId].
  /// Returns `null` — never throws — when there's no artwork or
  /// extraction fails, so callers can always fall back to the static
  /// preset scheme without special-casing errors themselves.
  static Future<ColorScheme?> forTrack({
    required String trackId,
    required Uint8List? artBytes,
    required Brightness brightness,
  }) {
    if (artBytes == null || artBytes.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(
      '$trackId-${brightness.name}',
      () => _extract(artBytes, brightness),
    );
  }

  static Future<ColorScheme?> _extract(
      Uint8List artBytes, Brightness brightness) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(artBytes),
        maximumColorCount: 24,
      );
      final seed = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color;
      if (seed == null) return null;
      return ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    } catch (_) {
      // A corrupt/unusual image must fall back to the static theme, not
      // crash Now Playing over what's ultimately a cosmetic feature.
      return null;
    }
  }

  /// Drops a track's cached scheme (both brightnesses) — call after its
  /// artwork changes (e.g. a tag-editor write) so the next lookup
  /// re-extracts instead of returning stale colors, mirroring
  /// `ArtworkProvider.invalidate`.
  static void invalidate(String trackId) {
    _cache.removeWhere((key, _) => key.startsWith('$trackId-'));
  }
}
