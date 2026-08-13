import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/base_track.dart';

/// Immutable snapshot of the entire playback subsystem at one moment.
///
/// [PlaybackState] is the contract between the pieces that produce playback
/// state ([AudioEngine]), the pieces that persist it ([RecoveryJournal]), and
/// the pieces that restore it ("resume where you left off?"). It deliberately
/// contains everything §42 of the Omnis 2.0 product spec says a recovery
/// journal must persist:
///
///   current track · position · queue · queue index · playback mode ·
///   volume · output
///
/// plus a handful of fields that cost nothing to persist and make resume
/// noticeably closer to seamless (speed, pitch, skip-silence, gapless,
/// crossfade). The model is intentionally a plain data class: the engine
/// produces it, the journal serializes it, the UI reads it — nobody mutates
/// it in place.
class PlaybackState {
  /// The full queue at the moment of capture.
  final List<BaseTrack> queue;

  /// Index into [queue] of the track that was current.
  final int currentIndex;

  /// Position within the current track at capture time.
  final Duration position;

  /// Whether playback was actively playing (vs paused/stopped) at capture.
  final bool wasPlaying;

  /// Shuffle toggle at capture.
  final bool shuffleEnabled;

  /// Repeat mode at capture.
  final RepeatMode repeatMode;

  /// Master volume (0..1) at capture.
  final double volume;

  /// Playback speed multiplier at capture.
  final double speed;

  /// Pitch multiplier at capture.
  final double pitch;

  /// Skip-silence toggle at capture.
  final bool skipSilenceEnabled;

  /// Gapless toggle at capture.
  final bool gaplessEnabled;

  /// Crossfade duration at capture.
  final Duration crossfadeDuration;

  /// Identifier of the active output device. Kept for forward
  /// compatibility with the hardware capability layer (§25 of the spec) —
  /// every platform reports `default` today; a future output controller
  /// writes the real device id here so a resume can land on the same
  /// headphone/DAC the user was using. A device that disappeared simply
  /// falls back to the system default at restore time.
  final String outputDeviceId;

  /// When this snapshot was captured (UTC).
  final DateTime savedAt;

  /// Constructor.
  PlaybackState({
    required this.queue,
    required this.currentIndex,
    required this.position,
    required this.wasPlaying,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.volume,
    required this.speed,
    required this.pitch,
    required this.skipSilenceEnabled,
    required this.gaplessEnabled,
    required this.crossfadeDuration,
    this.outputDeviceId = 'default',
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now().toUtc();

  /// Whether this snapshot carries anything worth restoring (an empty or
  /// entirely-unplayable queue is not a "resume" anyone wants).
  bool get hasResumableContent => queue.isNotEmpty && currentIndex >= 0;

  /// The track that was current at capture, if [currentIndex] is in range.
  BaseTrack? get currentTrack =>
      (currentIndex >= 0 && currentIndex < queue.length)
          ? queue[currentIndex]
          : null;

  /// Serialize to a JSON-compatible map (for [RecoveryJournal]).
  Map<String, dynamic> toJson() => {
        'version': 1,
        'queue': queue.map((t) => t.toJson()).toList(),
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'wasPlaying': wasPlaying,
        'shuffleEnabled': shuffleEnabled,
        'repeatMode': repeatMode.name,
        'volume': volume,
        'speed': speed,
        'pitch': pitch,
        'skipSilenceEnabled': skipSilenceEnabled,
        'gaplessEnabled': gaplessEnabled,
        'crossfadeMs': crossfadeDuration.inMilliseconds,
        'outputDeviceId': outputDeviceId,
        'savedAt': savedAt.toIso8601String(),
      };

  /// Deserialize from JSON, corruption-safe.
  ///
  /// A malformed field is never an exception here: the recovery journal's
  /// whole job is to survive a crash/power-loss/corrupt disk, so a
  /// half-written file must degrade to "no resume available," not to a
  /// crash at startup. Each optional/versioned field is parsed
  /// defensively and bad values fall back to sane defaults.
  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    List<BaseTrack> parseQueue(Object? raw) {
      if (raw is! List) return [];
      final tracks = <BaseTrack>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        try {
          tracks.add(BaseTrack.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          // One corrupt track must not discard the whole snapshot's queue.
          continue;
        }
      }
      return tracks;
    }

    final queue = parseQueue(json['queue']);
    var currentIndex = json['currentIndex'] is int
        ? (json['currentIndex'] as int).clamp(0, queue.length - 1)
        : -1;
    if (queue.isEmpty) currentIndex = -1;

    final repeatRaw =
        json['repeatMode'] is String ? (json['repeatMode'] as String) : 'off';
    final repeat = RepeatMode.values.firstWhere(
      (m) => m.name == repeatRaw,
      orElse: () => RepeatMode.off,
    );

    return PlaybackState(
      queue: queue,
      currentIndex: currentIndex,
      position: Duration(
        milliseconds: json['positionMs'] is int
            ? (json['positionMs'] as int).clamp(0, 1 << 31)
            : 0,
      ),
      wasPlaying:
          json['wasPlaying'] is bool ? (json['wasPlaying'] as bool) : false,
      shuffleEnabled: json['shuffleEnabled'] is bool
          ? (json['shuffleEnabled'] as bool)
          : false,
      repeatMode: repeat,
      volume: json['volume'] is num
          ? (json['volume'] as num).clamp(0.0, 1.0).toDouble()
          : 1.0,
      speed: json['speed'] is num
          ? (json['speed'] as num).clamp(0.25, 2.0).toDouble()
          : 1.0,
      pitch: json['pitch'] is num
          ? (json['pitch'] as num).clamp(0.5, 2.0).toDouble()
          : 1.0,
      skipSilenceEnabled: json['skipSilenceEnabled'] is bool
          ? (json['skipSilenceEnabled'] as bool)
          : false,
      gaplessEnabled: json['gaplessEnabled'] is bool
          ? (json['gaplessEnabled'] as bool)
          : true,
      crossfadeDuration: Duration(
        milliseconds: json['crossfadeMs'] is int
            ? (json['crossfadeMs'] as int).clamp(0, 1 << 31)
            : 0,
      ),
      outputDeviceId: json['outputDeviceId'] is String
          ? (json['outputDeviceId'] as String)
          : 'default',
      savedAt: json['savedAt'] is String
          ? (DateTime.tryParse(json['savedAt'] as String) ??
              DateTime.now().toUtc())
          : DateTime.now().toUtc(),
    );
  }

  /// Create a copy with selected fields replaced.
  PlaybackState copyWith({
    List<BaseTrack>? queue,
    int? currentIndex,
    Duration? position,
    bool? wasPlaying,
    bool? shuffleEnabled,
    RepeatMode? repeatMode,
    double? volume,
    double? speed,
    double? pitch,
    bool? skipSilenceEnabled,
    bool? gaplessEnabled,
    Duration? crossfadeDuration,
    String? outputDeviceId,
    DateTime? savedAt,
  }) {
    return PlaybackState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      wasPlaying: wasPlaying ?? this.wasPlaying,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      skipSilenceEnabled: skipSilenceEnabled ?? this.skipSilenceEnabled,
      gaplessEnabled: gaplessEnabled ?? this.gaplessEnabled,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      outputDeviceId: outputDeviceId ?? this.outputDeviceId,
      savedAt: savedAt ?? DateTime.now().toUtc(),
    );
  }
}
