import 'package:omnis_plugin_api/base_track.dart';

/// Result of enriching one track against external metadata sources.
///
/// Lives in `omnis_plugin_api` (not inside a plugin file) because
/// `IMetadataProvider` needs a return type both the implementing plugin
/// and any caller can name — same reason [PlayRecord] moved out of
/// `scrobble_plugin.dart`.
class EnrichmentResult {
  /// Canonical title/artist/album a provider reports, if it found a match.
  final String? canonicalTitle;
  final String? canonicalArtist;
  final String? canonicalAlbum;
  final int? year;

  /// The release's own artist credit, distinct from [canonicalArtist] (the
  /// *recording*'s artist) — e.g. "Various Artists" for a compilation
  /// whose matched track credits one specific performer. See
  /// [BaseTrack.albumArtist].
  final String? albumArtist;

  /// The kind of release the matched album is, when the source reports
  /// one. See [BaseTrack.releaseType].
  final ReleaseType? releaseType;

  /// Full release date, when the source reports one more precise than
  /// [year]. See [BaseTrack.releaseDate].
  final DateTime? releaseDate;

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
    this.albumArtist,
    this.releaseType,
    this.releaseDate,
    this.genres = const [],
    this.mood,
    this.sourcesUsed = const [],
  });

  bool get isEmpty =>
      canonicalTitle == null &&
      canonicalArtist == null &&
      canonicalAlbum == null &&
      year == null &&
      albumArtist == null &&
      releaseType == null &&
      releaseDate == null &&
      genres.isEmpty &&
      mood == null;
}
