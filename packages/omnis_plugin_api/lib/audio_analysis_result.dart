/// Result of analyzing one track's audio content (BPM/key/mood via real
/// signal analysis, as opposed to [EnrichmentResult]'s web-lookup
/// metadata).
///
/// Lives in `omnis_plugin_api` for the same reason [EnrichmentResult]/
/// [PlayRecord] do: `IAudioAnalysisProvider` needs a return type both the
/// implementing plugin and any caller can name without either importing
/// the other's file.
class AudioAnalysisResult {
  /// Beats per minute.
  final double? bpm;

  /// Musical key, e.g. `"C"`, `"F#"`.
  final String? key;

  /// `"major"` or `"minor"`.
  final String? scale;

  /// A mood label, when the analysis source produces one — `null`
  /// otherwise, not a guess.
  final String? mood;

  /// Genre/mood tags from the same analysis step.
  final List<String> genres;

  const AudioAnalysisResult({
    this.bpm,
    this.key,
    this.scale,
    this.mood,
    this.genres = const [],
  });

  bool get isEmpty =>
      bpm == null && key == null && mood == null && genres.isEmpty;

  /// The combined key+scale as `BaseTrack.key` already expects it
  /// (`"C# Minor"`), or `null` if either half is missing.
  String? get formattedKey {
    if (key == null || scale == null) return null;
    final scaleLabel = scale == 'minor' ? 'Minor' : 'Major';
    return '$key $scaleLabel';
  }
}
