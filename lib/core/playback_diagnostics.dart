import 'package:omnis/core/playback_state.dart';

/// What kind of underlying problem the watchdog detected.
///
/// This mirrors §2 of the Omnis 2.0 product spec ("New requirement:
/// playback watchdog") — each detection path maps to one concrete failure
/// type so the recovery policy can choose the right response instead of blindly
/// retrying the same thing forever.
enum PlaybackFailureType {
  /// The player spent too long in `loading`/`buffering` without reaching `ready`.
  stuckLoading,

  /// Playback was active but position stopped advancing for a suspicious
  /// amount of wall-clock time (a wedged decoder, or an output device that
  /// vanished mid-track).
  positionStalled,

  /// The duration reported for the current track is invalid (zero or
  /// negative for something actually playing) — makes seek/UI/progress all
  /// untrustworthy.
  invalidDuration,

  /// The current position is beyond the track's reported duration, which
  /// should be impossible for a healthy player.
  impossiblePosition,

  /// The native player threw (just_audio error event).
  /// (corrupt/missing/unsupported file)
  decoderException,

  /// The loop advancing through the queue failed enough times to trip
  /// the consecutive-error limit (queue corruption / every track unplayable).
  repeatedQueueFailure,

  /// The output device vanished mid-playback (headphones unplugged,
  /// Bluetooth dropped, DAC removed).
  outputDeviceLost,

  /// Generic catch-all for anything the watchdog can't classify.
  unknown,
}

/// One snapshot of the playback subsystem's health at a moment in time.
///
/// The [PlaybackWatchdog] produces these; the app surfaces the interesting
/// ones to the UI (a subtle "recovered playback" chip, the plugin-health-style
/// diagnostic view) and keeps a rolling buffer so a support report can show
/// exactly what happened. Everything is immutable — diagnostics are a record,
/// not mutable state.
class PlaybackDiagnostic {
  /// What actually went wrong.
  final PlaybackFailureType type;

  /// Human-readable summary — deliberately user-facing phrasing ("We couldn't
  /// play this song" style, per §55 of the UI spec), but with the technical
  /// detail always appended so power users can dig in.
  final String message;

  /// UTC timestamp of the event.
  final DateTime occurredAt;

  /// The index in the queue of the track involved, if any.
  final int? queueIndex;

  /// The track involved, if any — recorded by id so a diagnostic remains
  /// meaningful even if the in-memory track is long gone by the time
  /// someone reads it.
  final String? trackId;

  /// Whether playback automatically recovered without user action.
  final bool recovered;

  /// What the recovery policy actually did (e.g. "advanced to next track",
  /// "reloaded source", "stopped after repeated failures").
  final String? recoveryAction;

  /// Constructor.
  PlaybackDiagnostic({
    required this.type,
    required this.message,
    required this.occurredAt,
    this.queueIndex,
    this.trackId,
    this.recovered = false,
    this.recoveryAction,
  });

  /// Whether this diagnostic describes a hard failure (vs a benign
  /// warning) — i.e. whether the user should ever actually see it.
  bool get isHardFailure => recovered == false;

  factory PlaybackDiagnostic.fromSnapshot(
    PlaybackState snapshot,
    PlaybackFailureType type, {
    required String message,
    required DateTime occurredAt,
    bool recovered = false,
    String? recoveryAction,
  }) {
    return PlaybackDiagnostic(
      type: type,
      message: message,
      occurredAt: occurredAt,
      queueIndex: snapshot.currentIndex,
      trackId: snapshot.currentTrack?.id,
      recovered: recovered,
      recoveryAction: recoveryAction,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'message': message,
        'occurredAt': occurredAt.toIso8601String(),
        'queueIndex': queueIndex,
        'trackId': trackId,
        'recovered': recovered,
        'recoveryAction': recoveryAction,
      };

  factory PlaybackDiagnostic.fromJson(Map<String, dynamic> json) {
    return PlaybackDiagnostic(
      type: PlaybackFailureType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => PlaybackFailureType.unknown,
      ),
      message: json['message'] as String? ?? 'Unknown playback failure',
      occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? '') ??
          DateTime.now().toUtc(),
      queueIndex: json['queueIndex'] as int?,
      trackId: json['trackId'] as String?,
      recovered: json['recovered'] as bool? ?? false,
      recoveryAction: json['recoveryAction'] as String?,
    );
  }
}

/// Holds a rolling window of [PlaybackDiagnostic]s — the "record
/// diagnostic" half of the recovery flow from the product spec.
class PlaybackDiagnosticsStore {
  /// Maximum number of diagnostics retained in memory.
  final int capacity;

  final List<PlaybackDiagnostic> _items = [];
  final List<PlaybackDiagnostic> _unmodifiableView = [];

  PlaybackDiagnosticsStore({this.capacity = 50});

  /// Record a diagnostic, trimming to [capacity] oldest-first.
  void add(PlaybackDiagnostic diagnostic) {
    _items.add(diagnostic);
    if (_items.length > capacity) {
      _items.removeAt(0);
    }
    _unmodifiableView
      ..clear()
      ..addAll(_items);
  }

  /// The diagnostics recorded so far, oldest first (read-only view).
  List<PlaybackDiagnostic> get diagnostics =>
      List.unmodifiable(_unmodifiableView);

  /// The most recent diagnostic, if any.
  PlaybackDiagnostic? get latest => _items.isEmpty ? null : _items.last;

  /// Most recent diagnostic of [type], if any.
  PlaybackDiagnostic? latestOf(PlaybackFailureType type) {
    for (var i = _items.length - 1; i >= 0; i--) {
      if (_items[i].type == type) return _items[i];
    }
    return null;
  }

  /// How many failures of [type] occurred within [within].
  int countInLast(Duration within, {bool onlyHard = false}) {
    final cutoff = DateTime.now().toUtc().subtract(within);
    var count = 0;
    for (final d in _items) {
      if (d.occurredAt.isBefore(cutoff)) continue;
      if (onlyHard && d.recovered) continue;
      if (d.type == PlaybackFailureType.unknown) continue;
      count++;
    }
    return count;
  }

  /// Clear all diagnostics (e.g. after a clean stop).
  void clear() {
    _items.clear();
    _unmodifiableView.clear();
  }
}
