import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

class LyricLine {
  const LyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

/// A bundled lyrics plugin that stores simple or timed lyric lines per track ID.
class LyricsPlugin extends MusicPlugin {
  final Map<String, String> _lyrics = {};
  final Map<String, List<LyricLine>> _timedLyrics = {};

  String? lyricFor(BaseTrack track) => _lyrics[track.id];

  List<LyricLine> timedLyricFor(BaseTrack track) {
    final lyrics = _timedLyrics[track.id];
    if (lyrics == null || lyrics.isEmpty) {
      return [];
    }
    return List.unmodifiable(lyrics);
  }

  void setLyric(String trackId, String lyric) {
    _lyrics[trackId] = lyric;
  }

  void setTimedLyric(String trackId, List<LyricLine> lyrics) {
    _timedLyrics[trackId] = List.unmodifiable(lyrics);
  }

  String currentLyricFor(BaseTrack track, Duration position) {
    final timedLines = timedLyricFor(track);
    if (timedLines.isNotEmpty) {
      final match = timedLines.lastWhere(
        (line) => line.timestamp <= position,
        orElse: () => timedLines.first,
      );
      return match.text;
    }

    return lyricFor(track) ?? '♪ ${track.title} ♪';
  }

  @override
  String get id => 'lyrics';

  @override
  String get name => 'Lyrics';

  @override
  String get description => 'Adds lightweight track-specific lyrics for the player screen.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {}

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}
