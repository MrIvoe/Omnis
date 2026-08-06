/// Result of enriching one track against external metadata sources.
///
/// Lives in `lib/plugin_api/` (not inside a plugin file) because
/// [IMetadataProvider] needs a return type both the implementing plugin
/// and any caller can name — same reason [PlayRecord] moved out of
/// `scrobble_plugin.dart`.
class EnrichmentResult {
  /// Canonical title/artist/album a provider reports, if it found a match.
  final String? canonicalTitle;
  final String? canonicalArtist;
  final String? canonicalAlbum;
  final int? year;

  /// Merged genre tags from whichever sources contributed something.
  final List<String> genres;

  /// A single mood word, if a source's tags/labels included one. `null`
  /// when nothing looked mood-like — this is a best-effort heuristic on
  /// free-text tags, not an authoritative label.
  final String? mood;

  /// Which sources actually contributed something (for UI/debugging).
  final List<String> sourcesUsed;

  const EnrichmentResult({
    this.canonicalTitle,
    this.canonicalArtist,
    this.canonicalAlbum,
    this.year,
    this.genres = const [],
    this.mood,
    this.sourcesUsed = const [],
  });

  bool get isEmpty =>
      canonicalTitle == null &&
      canonicalArtist == null &&
      canonicalAlbum == null &&
      year == null &&
      genres.isEmpty &&
      mood == null;
}
