import 'dart:typed_data';

import 'package:omnis_plugin_api/base_track.dart';

/// Custom `TXXX` key names used for every tag field id3_codec can't write
/// as its own native ID3v2 frame (see the tag-editor implementation's
/// class doc for why). Centralised here — as both a single map used to build the
/// custom fields for a write, and looked up by [TrackTags]'s getters —
/// specifically because using the same literal string in two different
/// places by hand is exactly how a mismatch bug happens: `TrackTags.genre`
/// originally checked only the native `TCON` frame and never the
/// `TXXX:GENRE` key this plugin actually writes genre under, so a value
/// this plugin itself had just written came back as `null` on the very
/// next read. Caught by `test/tag_editor_plugin_test.dart`'s round-trip
/// test, not by inspection — every one of these fields now has a
/// dedicated round-trip test for exactly that reason.
class CustomTagKeys {
  static const genre = 'GENRE';
  static const year = 'YEAR';
  static const track = 'TRACK';
  static const disc = 'DISC';
  static const composer = 'COMPOSER';
  static const comment = 'COMMENT';
  static const albumArtist = 'ALBUMARTIST';
  static const bpm = 'BPM';
  static const initialKey = 'INITIALKEY';
  static const mood = 'MOOD';
  static const lyrics = 'LYRICS';
}

/// One ID3 frame as read from a file, flattened for UI use.
class TagFrame {
  /// The 4-character frame id, e.g. `TIT2`, `TPE1`, `APIC`, or a
  /// synthetic `TXXX:<description>` for custom text frames so each one
  /// gets a distinct, stable key.
  final String id;

  /// Human-readable name (from id3_codec's own frame name tables).
  final String label;

  /// Display value for text-like frames. `null` for binary frames
  /// (artwork) — see [artworkBytes] instead.
  final String? value;

  /// Raw picture bytes, only set for the APIC (artwork) frame.
  final Uint8List? artworkBytes;

  const TagFrame({
    required this.id,
    required this.label,
    this.value,
    this.artworkBytes,
  });

  bool get isArtwork => artworkBytes != null;
}

/// All tags read from one file, in both flattened-list form (for a "show
/// everything, not just the common fields" editor UI) and as convenient
/// named getters for the handful of fields Omnis's own data model
/// (`BaseTrack`) understands directly.
class TrackTags {
  final List<TagFrame> frames;

  const TrackTags(this.frames);

  String? _text(String frameId) {
    for (final f in frames) {
      if (f.id == frameId) return f.value;
    }
    return null;
  }

  /// Custom-key frames this plugin writes (`TXXX:<CustomTagKeys.x>`) are
  /// checked *first*: they reflect what Omnis itself last wrote. The
  /// frame native taggers use is the fallback, so a file tagged by other
  /// software still shows real data before Omnis ever touches it.
  String? _custom(String key, String nativeFrameId) =>
      _text('TXXX:$key') ?? _text(nativeFrameId);

  String? get title => _text('TIT2');
  String? get artist => _text('TPE1');
  String? get albumArtist => _custom(CustomTagKeys.albumArtist, 'TPE2');
  String? get album => _text('TALB');
  String? get genre => _custom(CustomTagKeys.genre, 'TCON');
  String? get year => _custom(CustomTagKeys.year, 'TYER') ?? _text('TDRC');
  String? get track => _custom(CustomTagKeys.track, 'TRCK');
  String? get disc => _custom(CustomTagKeys.disc, 'TPOS');
  String? get composer => _custom(CustomTagKeys.composer, 'TCOM');
  String? get comment => _custom(CustomTagKeys.comment, 'COMM');
  String? get bpm => _custom(CustomTagKeys.bpm, 'TBPM');
  String? get initialKey => _custom(CustomTagKeys.initialKey, 'TKEY');
  String? get mood => _custom(CustomTagKeys.mood, 'TMOO');
  // USLT (the native ID3 lyrics frame) isn't in id3_codec's writable set
  // any more than genre/mood/bpm are — see the class doc on why every
  // field here goes through TXXX instead of native frames where the
  // library doesn't support writing one. 'USLT' is still checked first in
  // case another tagger wrote a real lyrics frame into the file.
  String? get lyrics => _custom(CustomTagKeys.lyrics, 'USLT');

  Uint8List? get artwork {
    for (final f in frames) {
      if (f.isArtwork) return f.artworkBytes;
    }
    return null;
  }

  /// Case-insensitive TXXX lookup — unlike [_custom], which only ever
  /// needs to match the exact key Omnis itself writes, ReplayGain tags
  /// come from whatever external scanner tagged the file (mp3gain,
  /// foobar2000, ...) and those don't reliably agree on casing.
  String? _customCaseInsensitive(String key) {
    final target = 'TXXX:$key'.toLowerCase();
    for (final f in frames) {
      if (f.id.toLowerCase() == target) return f.value;
    }
    return null;
  }

  /// De facto standard ReplayGain tag names — the ones mp3gain,
  /// foobar2000, and most other ReplayGain scanners write as TXXX
  /// frames, e.g. `"-6.50 dB"`.
  String? get replayGainTrackGain =>
      _customCaseInsensitive('REPLAYGAIN_TRACK_GAIN');
  String? get replayGainTrackPeak =>
      _customCaseInsensitive('REPLAYGAIN_TRACK_PEAK');
  String? get replayGainAlbumGain =>
      _customCaseInsensitive('REPLAYGAIN_ALBUM_GAIN');
  String? get replayGainAlbumPeak =>
      _customCaseInsensitive('REPLAYGAIN_ALBUM_PEAK');

  /// Parses a ReplayGain string like `"-6.50 dB"` or `"-6.50"` into a
  /// plain double, or `null` if it isn't parseable.
  static double? _parseGainValue(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned);
  }

  /// All four ReplayGain values bundled together, or `null` if the file
  /// has none of them — the shape `BaseTrack.replayGain` expects.
  ReplayGainValues? get replayGainValues {
    final trackGain = _parseGainValue(replayGainTrackGain);
    final trackPeak = _parseGainValue(replayGainTrackPeak);
    final albumGain = _parseGainValue(replayGainAlbumGain);
    final albumPeak = _parseGainValue(replayGainAlbumPeak);
    if (trackGain == null &&
        trackPeak == null &&
        albumGain == null &&
        albumPeak == null) {
      return null;
    }
    return ReplayGainValues(
      trackGain: trackGain,
      trackPeak: trackPeak,
      albumGain: albumGain,
      albumPeak: albumPeak,
    );
  }

  bool get isEmpty => frames.isEmpty;
}
