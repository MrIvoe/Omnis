import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:omnis/core/base_track.dart';
import 'package:path_provider/path_provider.dart';

/// One track's aggregate play stats — not a per-play event log (unlike
/// `ScrobblePlugin`'s `PlayRecord` list, which exists for a different
/// purpose). The Home dashboard only ever needs "how many times, when
/// last, how far in," so storage stays bounded by library size instead of
/// growing forever.
class TrackPlayStats {
  final String trackId;
  final int playCount;
  final DateTime lastPlayedAt;

  /// How far into the track playback last got, for the Continue Listening
  /// section. Reset to zero on every fresh [PlayHistoryStore.recordPlay]
  /// (a new listen starts over), then updated by
  /// [PlayHistoryStore.recordPosition] as that listen progresses.
  final int lastPositionSeconds;

  /// The track's duration as of the last position update — kept alongside
  /// the position (rather than re-reading `BaseTrack.duration`, which is
  /// unreliable for filesystem-scanned tracks) so "10%–90% through" can be
  /// computed without a second lookup.
  final int durationSeconds;

  const TrackPlayStats({
    required this.trackId,
    required this.playCount,
    required this.lastPlayedAt,
    this.lastPositionSeconds = 0,
    this.durationSeconds = 0,
  });

  TrackPlayStats copyWith({
    int? playCount,
    DateTime? lastPlayedAt,
    int? lastPositionSeconds,
    int? durationSeconds,
  }) {
    return TrackPlayStats(
      trackId: trackId,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPositionSeconds: lastPositionSeconds ?? this.lastPositionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'playCount': playCount,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'lastPositionSeconds': lastPositionSeconds,
        'durationSeconds': durationSeconds,
      };

  factory TrackPlayStats.fromJson(Map<String, dynamic> json) {
    return TrackPlayStats(
      trackId: json['trackId'] as String,
      playCount: json['playCount'] as int,
      lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      lastPositionSeconds: json['lastPositionSeconds'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
    );
  }
}

/// Decodes the raw JSON object (trackId -> stats) into a map. A top-level
/// function, same reason `LibraryStore`'s `_decodeTracks` is one:
/// [compute] spawns an isolate, which needs a function with no captured
/// state.
Map<String, TrackPlayStats> _decodeStats(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map(
    (id, value) =>
        MapEntry(id, TrackPlayStats.fromJson(value as Map<String, dynamic>)),
  );
}

String _encodeStats(Map<String, TrackPlayStats> stats) =>
    jsonEncode(stats.map((id, s) => MapEntry(id, s.toJson())));

/// Persists per-track play aggregates so the Home dashboard's Recently
/// Played / Most Played / Continue Listening sections work regardless of
/// whether the optional `ScrobblePlugin` is installed — this is core,
/// always-on infrastructure, not a plugin.
///
/// Same shape as `LibraryStore`: one JSON file under the app's documents
/// directory, no in-memory cache (this is a small file — a few numbers
/// per track, not full metadata — so re-reading it per call costs little
/// and avoids a stale-cache class of bug entirely).
class PlayHistoryStore {
  PlayHistoryStore._();

  static final PlayHistoryStore instance = PlayHistoryStore._();

  // Deliberately not cached, unlike LibraryStore's equivalent — a stale
  // cached path is exactly what makes a singleton like this awkward to
  // test (whoever resolves path_provider first "wins" for the rest of
  // the process). getApplicationDocumentsDirectory() is a cheap, fast
  // platform-channel call; re-resolving it on every call is not a real
  // cost for how infrequently this fires (per play, per pause/track
  // change), and it means each test's own fake path_provider is always
  // actually honored.
  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/omnis_play_history.json');
  }

  Future<Map<String, TrackPlayStats>> _load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      return await compute(_decodeStats, raw);
    } catch (e) {
      // Corrupt or unreadable file: treat as empty, never crash.
      return {};
    }
  }

  Future<void> _save(Map<String, TrackPlayStats> stats) async {
    try {
      final file = await _getFile();
      final json = await compute(_encodeStats, stats);
      await file.writeAsString(json);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Called once per genuinely-started track (see `MainCore`'s
  /// `onTrackStarted` wiring) — increments the play count, stamps "now,"
  /// and resets the position (a fresh listen starts over).
  Future<void> recordPlay(BaseTrack track) async {
    final stats = await _load();
    final existing = stats[track.id];
    stats[track.id] = TrackPlayStats(
      trackId: track.id,
      playCount: (existing?.playCount ?? 0) + 1,
      lastPlayedAt: DateTime.now(),
    );
    await _save(stats);
  }

  /// Updates how far into [trackId] playback got, for Continue Listening.
  /// A no-op if [recordPlay] was never called for this track (nothing to
  /// update) — position tracking only makes sense for a track that's
  /// actually been played at least once.
  Future<void> recordPosition(
    String trackId,
    Duration position,
    Duration duration,
  ) async {
    final stats = await _load();
    final existing = stats[trackId];
    if (existing == null) return;
    stats[trackId] = existing.copyWith(
      lastPositionSeconds: position.inSeconds,
      durationSeconds: duration.inSeconds,
    );
    await _save(stats);
  }

  Future<List<TrackPlayStats>> recentlyPlayed({int limit = 20}) async {
    final stats = (await _load()).values.toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return stats.take(limit).toList();
  }

  Future<List<TrackPlayStats>> mostPlayed({int limit = 20}) async {
    final stats = (await _load()).values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    return stats.take(limit).toList();
  }

  /// Tracks roughly 10%–90% of the way through — far enough in that
  /// resuming makes more sense than replaying from the start, not so far
  /// that it's effectively finished.
  Future<List<TrackPlayStats>> continueListening({int limit = 20}) async {
    final stats = (await _load()).values.where((s) {
      if (s.durationSeconds <= 0) return false;
      final ratio = s.lastPositionSeconds / s.durationSeconds;
      return ratio >= 0.1 && ratio <= 0.9;
    }).toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    return stats.take(limit).toList();
  }

  /// Clears all persisted play history. Not currently exposed in any UI —
  /// exists for tests and as a future "reset my history" settings action.
  Future<void> clear() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
