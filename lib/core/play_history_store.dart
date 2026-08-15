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

  /// A full `BaseTrack.toJson()` snapshot, captured at [PlayHistoryStore
  /// .recordPlay] time — **only** for a track whose [BaseTrack.type] isn't
  /// [TrackType.local]. Item 41's "a station's history entry is recorded
  /// but never rendered" gap (and the same gap for every other
  /// non-scanned track type — Spotify/YouTube/Jellyfin/Plex/Subsonic/
  /// DLNA/Emby — which shares the identical root cause, not just radio):
  /// `HomeDashboardPage` previously joined every history entry against
  /// `LibraryRepository`'s scanned library purely by id, which a live,
  /// never-imported track (a radio station fetched from Radio Browser,
  /// a streaming-service track) is never part of — the play genuinely
  /// happened and was genuinely recorded, but there was nothing to
  /// display for it. `null` for a local track — its full metadata is
  /// already in the scanned library, so storing a second copy here would
  /// be pure duplication for the overwhelmingly common case.
  final Map<String, dynamic>? trackSnapshot;

  const TrackPlayStats({
    required this.trackId,
    required this.playCount,
    required this.lastPlayedAt,
    this.lastPositionSeconds = 0,
    this.durationSeconds = 0,
    this.trackSnapshot,
  });

  TrackPlayStats copyWith({
    int? playCount,
    DateTime? lastPlayedAt,
    int? lastPositionSeconds,
    int? durationSeconds,
    Map<String, dynamic>? trackSnapshot,
  }) {
    return TrackPlayStats(
      trackId: trackId,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPositionSeconds: lastPositionSeconds ?? this.lastPositionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'playCount': playCount,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'lastPositionSeconds': lastPositionSeconds,
        'durationSeconds': durationSeconds,
        if (trackSnapshot != null) 'trackSnapshot': trackSnapshot,
      };

  factory TrackPlayStats.fromJson(Map<String, dynamic> json) {
    final snapshot = json['trackSnapshot'];
    return TrackPlayStats(
      trackId: json['trackId'] as String,
      playCount: json['playCount'] as int,
      lastPlayedAt: DateTime.parse(json['lastPlayedAt'] as String),
      lastPositionSeconds: json['lastPositionSeconds'] as int? ?? 0,
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      trackSnapshot:
          snapshot is Map ? Map<String, dynamic>.from(snapshot) : null,
    );
  }
}

/// Decodes the raw JSON object (trackId -> stats) into a map. A top-level
/// function, same reason `LibraryStore`'s `_decodeTracks` is one:
/// [compute] spawns an isolate, which needs a function with no captured
/// state.
///
/// Each entry is decoded independently and a failure skips just that one
/// track's stats — `TrackPlayStats.fromJson` uses `DateTime.parse` (not
/// `tryParse`) and hard-casts `playCount`, so it throws on anything
/// malformed. A single corrupted record among thousands used to throw
/// out of a bulk `Map.map(...)`, wiping the *entire* play history (every
/// play count, every "last played," Continue Listening's whole dataset)
/// over one bad entry. Same rationale as `LibraryStore`'s identical
/// per-entry guard.
Map<String, TrackPlayStats> _decodeStats(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final stats = <String, TrackPlayStats>{};
  for (final entry in decoded.entries) {
    if (entry.value is! Map) continue;
    try {
      stats[entry.key] =
          TrackPlayStats.fromJson(Map<String, dynamic>.from(entry.value));
    } catch (_) {
      continue;
    }
  }
  return stats;
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

  /// Serializes every read-modify-write operation onto one chain.
  ///
  /// `recordPlay`/`recordPosition` each do their own full `_load()` ->
  /// mutate -> `_save()` cycle, and `MainCore` fires both from several
  /// independent, unawaited stream listeners (a track change fires
  /// `recordPosition` for the *previous* track in the same moment
  /// `onTrackStarted` fires `recordPlay` for the *new* one). Without
  /// this, two concurrent calls each `_load()` the same base state,
  /// mutate their own in-memory copy, and whichever `_save()` finishes
  /// last silently overwrites the other's update — a lost play count or
  /// a lost position update, not just a file-write race (the atomic
  /// `.tmp`-rename in `_save` only protects against a torn *file*, not
  /// against two logically-independent mutations racing on the same
  /// read). Wrapping the whole operation, not just the final write,
  /// guarantees each call sees the previous call's result.
  Future<void> _pending = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    // The chain itself must never fail (a failed operation would leave
    // every future caller permanently stuck waiting on a broken Future) —
    // each real operation already catches its own errors internally, so
    // this is just insulating the chain, not swallowing anything new.
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Writes to a sibling `.tmp` file and renames it over the real path —
  /// atomic on the filesystems this app targets, so a crash/power-loss
  /// mid-write (this fires on every pause and every track change, not a
  /// rare event) leaves the previous complete file intact rather than a
  /// truncated one that silently wipes Recently/Most Played/Continue
  /// Listening. Same fix as `LibraryStore.save`; no debounce added here
  /// unlike that one — this store isn't called in the kind of tight
  /// per-mutation loop LibraryStore's bulk tag-edit path is.
  Future<void> _save(Map<String, TrackPlayStats> stats) async {
    try {
      final file = await _getFile();
      final json = await compute(_encodeStats, stats);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Called once per genuinely-started track (see `MainCore`'s
  /// `onTrackStarted` wiring) — increments the play count, stamps "now,"
  /// and resets the position (a fresh listen starts over).
  Future<void> recordPlay(BaseTrack track) => _serialized(() async {
        final stats = await _load();
        final existing = stats[track.id];
        stats[track.id] = TrackPlayStats(
          trackId: track.id,
          playCount: (existing?.playCount ?? 0) + 1,
          lastPlayedAt: DateTime.now(),
          trackSnapshot:
              track.type == TrackType.local ? null : track.toJson(),
        );
        await _save(stats);
      });

  /// Updates how far into [trackId] playback got, for Continue Listening.
  /// A no-op if [recordPlay] was never called for this track (nothing to
  /// update) — position tracking only makes sense for a track that's
  /// actually been played at least once.
  Future<void> recordPosition(
    String trackId,
    Duration position,
    Duration duration,
  ) =>
      _serialized(() async {
        final stats = await _load();
        final existing = stats[trackId];
        if (existing == null) return;
        stats[trackId] = existing.copyWith(
          lastPositionSeconds: position.inSeconds,
          durationSeconds: duration.inSeconds,
        );
        await _save(stats);
      });

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
  Future<void> clear() => _serialized(() async {
        try {
          final file = await _getFile();
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      });
}
