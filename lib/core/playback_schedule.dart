import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// This store's current on-disk shape version — see `schema_versioning.dart`.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// A recurring "start playback at this time, on these days" trigger —
/// MusicBee comparison §43's scheduling gap ("start/stop playback at a
/// time, wake playback, scheduled playlist... recurring/day-of-week
/// rules"), distinct from `SleepTimerPlugin` (countdown-only, no
/// future-time/day-of-week concept at all) and from a general
/// automation-rules engine (item 50's larger, still-deferred ask) — this
/// is one concrete, narrowly-scoped trigger type, not a rules engine.
class PlaybackSchedule {
  final String id;
  final String name;

  /// Minutes since midnight (0-1439) — e.g. 7:30 AM is `450`. Stored this
  /// way rather than as a `TimeOfDay` (a Flutter type with no `toJson`)
  /// or a full `DateTime` (which would wrongly encode a specific date).
  final int minuteOfDay;

  /// [DateTime.weekday] values (1 = Monday ... 7 = Sunday) this schedule
  /// fires on. Empty means "never" rather than "every day" — an
  /// explicit, unambiguous opt-in for each day, matching how the
  /// schedule-editor UI presents day toggles.
  final Set<int> weekdays;

  final bool enabled;

  /// A specific playlist to play, or `null` to just resume/replay
  /// whatever's already queued.
  final String? playlistId;

  final DateTime createdAt;

  const PlaybackSchedule({
    required this.id,
    required this.name,
    required this.minuteOfDay,
    required this.weekdays,
    required this.enabled,
    this.playlistId,
    required this.createdAt,
  });

  PlaybackSchedule copyWith({
    String? name,
    int? minuteOfDay,
    Set<int>? weekdays,
    bool? enabled,
    String? playlistId,
    bool clearPlaylistId = false,
  }) =>
      PlaybackSchedule(
        id: id,
        name: name ?? this.name,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
        playlistId:
            clearPlaylistId ? null : (playlistId ?? this.playlistId),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minuteOfDay': minuteOfDay,
        'weekdays': weekdays.toList(),
        'enabled': enabled,
        if (playlistId != null) 'playlistId': playlistId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PlaybackSchedule.fromJson(Map<String, dynamic> json) =>
      PlaybackSchedule(
        id: json['id'] as String,
        name: json['name'] as String,
        minuteOfDay: json['minuteOfDay'] as int,
        weekdays: (json['weekdays'] as List? ?? const [])
            .whereType<int>()
            .toSet(),
        enabled: json['enabled'] as bool? ?? true,
        playlistId: json['playlistId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Persists playback schedules. Same atomic-write + schema-versioned-
/// envelope shape every other store in this app already uses (see
/// `AbLoopStore`/`CustomRadioStationStore` for the identical template).
class PlaybackScheduleStore {
  PlaybackScheduleStore._();

  static final PlaybackScheduleStore instance = PlaybackScheduleStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_playback_schedules.json');
    return _file!;
  }

  /// Load every persisted schedule, in the order they were created.
  /// Returns an empty list if none exist or the file is corrupt — each
  /// entry is decoded independently, so one malformed record can't wipe
  /// the rest.
  Future<List<PlaybackSchedule>> load() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      final unwrapped = unwrapVersioned(decoded);
      final migrated = runMigrations(unwrapped.data, unwrapped.version,
          _currentSchemaVersion, _migrations);
      if (migrated is! List) return [];
      final schedules = <PlaybackSchedule>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        try {
          schedules
              .add(PlaybackSchedule.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return schedules;
    } catch (e) {
      return [];
    }
  }

  /// Persist [schedules] to disk. Writes to a sibling `.tmp` file and
  /// renames it over the real path — atomic on the filesystems this app
  /// targets, the same crash-safety every other store's `save` already
  /// has.
  Future<void> save(List<PlaybackSchedule> schedules) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          schedules.map((s) => s.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Adds a new schedule and returns the updated list.
  Future<List<PlaybackSchedule>> add(PlaybackSchedule schedule) async {
    final existing = await load();
    final updated = [...existing, schedule];
    await save(updated);
    return updated;
  }

  /// Replaces the schedule with [updated]'s id, if one exists. A
  /// harmless no-op otherwise.
  Future<List<PlaybackSchedule>> update(PlaybackSchedule updated) async {
    final existing = await load();
    final result = [
      for (final s in existing) s.id == updated.id ? updated : s
    ];
    await save(result);
    return result;
  }

  /// Deletes the schedule with [id], if one exists. A harmless no-op
  /// otherwise.
  Future<List<PlaybackSchedule>> delete(String id) async {
    final existing = await load();
    final updated = existing.where((s) => s.id != id).toList();
    await save(updated);
    return updated;
  }
}
