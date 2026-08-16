import 'package:omnis/core/base_track.dart';

/// Aggregate counts/sizes over a scanned library — spec §35's "Library
/// Statistics" dashboard, the "Library" subsection specifically (total
/// tracks/albums/artists/genres, duration, bitrate, lossless/hi-res
/// ratios). Deliberately excludes §35's "Listening"/"Time"/"Charts"
/// subsections (streaks, hourly/daily histograms) — those need
/// per-play timestamp granularity `PlayHistoryStore` doesn't store
/// today, a real follow-on rather than something this can honestly
/// compute from already-loaded tracks.
///
/// Computed purely from tracks already resident in memory — no new
/// file I/O, the same "work from what's already loaded" contract
/// `LibraryCleanupAnalyzer.analyze` already establishes for its own
/// synchronous pass.
class LibraryStatistics {
  final int trackCount;
  final int albumCount;
  final int artistCount;
  final int genreCount;

  final Duration totalDuration;

  /// `null` when no track in the library has a known bitrate.
  final int? averageBitrateKbps;

  /// `null` for an empty library.
  final Duration? averageTrackLength;

  /// Tracks whose [BaseTrack.codec] is a known-lossless format (FLAC,
  /// WAV — the two lossless labels `AudioFormatReader` actually
  /// produces). `AAC/ALAC (M4A)` is deliberately excluded from both
  /// [losslessCount] and [lossyCount]: M4A is a container, not a codec,
  /// and can hold either lossy AAC or lossless ALAC — guessing which
  /// would misreport real data as a fabricated certainty.
  final int losslessCount;

  /// Tracks whose [BaseTrack.codec] is a known-lossy format (MP3, Ogg,
  /// Ogg Vorbis, Opus, WMA, AAC).
  final int lossyCount;

  /// Tracks meeting a common "hi-res" threshold: 24-bit depth or a
  /// 48kHz+ sample rate (either one, not both — matches the
  /// industry-common "hi-res audio" definition, not a stricter
  /// intersection).
  final int hiResCount;

  const LibraryStatistics({
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.genreCount,
    required this.totalDuration,
    required this.averageBitrateKbps,
    required this.averageTrackLength,
    required this.losslessCount,
    required this.lossyCount,
    required this.hiResCount,
  });

  static const _losslessCodecs = {'FLAC', 'WAV'};
  static const _lossyCodecs = {'MP3', 'Ogg', 'Ogg Vorbis', 'Opus', 'WMA', 'AAC'};

  static LibraryStatistics compute(List<BaseTrack> tracks) {
    if (tracks.isEmpty) {
      return const LibraryStatistics(
        trackCount: 0,
        albumCount: 0,
        artistCount: 0,
        genreCount: 0,
        totalDuration: Duration.zero,
        averageBitrateKbps: null,
        averageTrackLength: null,
        losslessCount: 0,
        lossyCount: 0,
        hiResCount: 0,
      );
    }

    final albums = <String>{};
    final artists = <String>{};
    final genres = <String>{};
    var totalSeconds = 0;
    var bitrateSum = 0;
    var bitrateCount = 0;
    var lossless = 0;
    var lossy = 0;
    var hiRes = 0;

    for (final track in tracks) {
      if (track.album.trim().isNotEmpty) albums.add(track.album);
      for (final artist in track.artists) {
        if (artist.trim().isNotEmpty) artists.add(artist);
      }
      for (final genre in track.genres) {
        if (genre.trim().isNotEmpty) genres.add(genre);
      }
      totalSeconds += track.duration;

      final bitrate = track.bitrateKbps;
      if (bitrate != null) {
        bitrateSum += bitrate;
        bitrateCount++;
      }

      final codec = track.codec;
      if (codec != null) {
        if (_losslessCodecs.contains(codec)) {
          lossless++;
        } else if (_lossyCodecs.contains(codec)) {
          lossy++;
        }
      }

      final bitDepth = track.bitDepth;
      final sampleRateHz = track.sampleRateHz;
      if ((bitDepth != null && bitDepth >= 24) ||
          (sampleRateHz != null && sampleRateHz >= 48000)) {
        hiRes++;
      }
    }

    return LibraryStatistics(
      trackCount: tracks.length,
      albumCount: albums.length,
      artistCount: artists.length,
      genreCount: genres.length,
      totalDuration: Duration(seconds: totalSeconds),
      averageBitrateKbps:
          bitrateCount == 0 ? null : (bitrateSum / bitrateCount).round(),
      averageTrackLength:
          Duration(seconds: (totalSeconds / tracks.length).round()),
      losslessCount: lossless,
      lossyCount: lossy,
      hiResCount: hiRes,
    );
  }
}
