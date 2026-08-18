/// One line of time-synced lyrics: the position it starts at, and its
/// text.
///
/// Lives in `omnis_plugin_api` (not `lyrics_plugin.dart`, where it used to
/// be defined) because `ILyricsProvider.syncedLyricsFor` needs a return
/// type both the plugin that implements it and any caller (the Now
/// Playing lyrics panel, the Karaoke Gestures layout) can import — the
/// same reason `PlayRecord` (`play_record.dart`) and `EnrichmentResult`
/// (`enrichment_result.dart`) moved out of their owning plugin files
/// before this.
class LyricLine {
  const LyricLine({
    required this.timestamp,
    required this.text,
    this.wordTimings,
  });

  /// When this line starts, relative to the track's own start.
  final Duration timestamp;

  /// This line's full text.
  final String text;

  /// Per-word timestamps within this line, for word-level ("enhanced
  /// LRC") karaoke highlighting — each entry is one word's own start time
  /// paired with its text, in order.
  ///
  /// `null` when the source only carried this line's line-level
  /// timestamp ([timestamp] above) — the common case for plain synced
  /// LRC, and every line `parseLrc` (in the `Omnis-Plugins` repo's
  /// `lyrics_plugin.dart`) produces today, since it only extracts the
  /// `[mm:ss.xx]` line prefix, not lrclib.net's inline `<mm:ss.xx>word`
  /// per-word tags some "enhanced" LRC responses also carry. A renderer
  /// must fall back to highlighting the whole line via [timestamp] when
  /// this is `null` — and must never fabricate word timings by
  /// interpolating evenly across the line's duration, which is
  /// frequently wrong and reads as a bug, not a feature.
  final List<(Duration, String)>? wordTimings;
}
