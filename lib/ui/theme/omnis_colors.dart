import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Static, non-dynamic color palette for each built-in theme preset —
/// pulled out of what used to be inline in `AppSettings.themeData()` so
/// [OmnisTheme] and a declarative (user-imported) theme both build off the
/// same named colors instead of duplicating the hex values.
class OmnisPalette {
  OmnisPalette._();

  // Item 44/spec §22-27's six named presets — Classic (accent-color-
  // driven, see `OmnisTheme.build`) plus these five fixed palettes,
  // replacing the earlier invented Midnight/Aurora/Sunset trio so the
  // preset dropdown actually offers the spec's own named set rather
  // than substitutes with no connection to it.
  /// Pure: minimal, near-monochrome — deliberately the least colorful
  /// preset, letting artwork/typography carry the visual weight.
  static const purePrimary = Color(0xFF6B7280);
  static const pureSecondary = Color(0xFF9CA3AF);

  /// Drive: bold, high-contrast — legible at a glance, the same reason
  /// automotive UIs lean on saturated warning-adjacent colors.
  static const drivePrimary = Color(0xFFFF3B30);
  static const driveSecondary = Color(0xFFFFD60A);

  /// Karaoke: warm, spotlight-like — a lyric-focused interface reads
  /// warmer than a plain playback one.
  static const karaokePrimary = Color(0xFFFFB020);
  static const karaokeSecondary = Color(0xFFFF6F91);

  /// Future: cool and restrained — deliberately not a neon-cyberpunk
  /// cliché (the spec explicitly warns against that), just a cooler,
  /// calmer palette than the others.
  static const futurePrimary = Color(0xFF4C9AFF);
  static const futureSecondary = Color(0xFF64E1D0);

  /// Audiophile: desaturated and technical — reads like a measurement
  /// tool, not a mood board.
  static const audiophilePrimary = Color(0xFF5C6B7A);
  static const audiophileSecondary = Color(0xFF8FA3B0);

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
