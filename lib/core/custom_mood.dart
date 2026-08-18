import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/schema_versioning.dart';
import 'package:path_provider/path_provider.dart';

/// `Color.value` is deprecated and its replacement `Color.toARGB32()`
/// only exists from Flutter 3.29 — this project builds on 3.27.4, the
/// same constraint `AppSettings._packArgb` already documents; this is
/// that same helper, duplicated rather than imported since
/// `app_settings.dart`'s copy is private.
int _packArgb(Color color) =>
    ((color.a * 255).round() & 0xff) << 24 |
    ((color.r * 255).round() & 0xff) << 16 |
    ((color.g * 255).round() & 0xff) << 8 |
    ((color.b * 255).round() & 0xff);

/// UI_SPEC §13's "user-created moods" — a closed set of icons a custom
/// mood's tile can pick from, the same "closed vocabulary, IconData baked
/// in directly (never built from a string, so the tree-shaker keeps
/// exactly these glyphs)" discipline `OmnisIconCatalog` already uses one
/// file over. A separate, smaller vocabulary rather than reusing
/// `OmnisIconCatalog` itself — that catalog restyles a fixed set of icons
/// already wired to specific existing UI elements (the bottom nav, the
/// transport row); this is the opposite shape, an arbitrary user choice
/// of *which* glyph identifies *their own* mood.
enum CustomMoodIcon {
  moon(Icons.nightlight_round, 'Moon'),
  sunny(Icons.wb_sunny, 'Sunny'),
  bedtime(Icons.bedtime, 'Bedtime'),
  directionsCar(Icons.directions_car, 'Driving'),
  fitnessCenter(Icons.fitness_center, 'Workout'),
  localCafe(Icons.local_cafe, 'Café'),
  nightlife(Icons.nightlife, 'Nightlife'),
  spa(Icons.spa, 'Spa'),
  whatshot(Icons.whatshot, 'Energetic'),
  favorite(Icons.favorite, 'Love'),
  celebration(Icons.celebration, 'Party'),
  umbrella(Icons.beach_access, 'Rainy day'),
  book(Icons.menu_book, 'Reading'),
  work(Icons.work, 'Focus/Work'),
  forest(Icons.forest, 'Nature'),
  mood(Icons.mood, 'Generic');

  final IconData icon;
  final String label;

  const CustomMoodIcon(this.icon, this.label);
}

/// A user-created mood — UI_SPEC §13's "define genres/energy/tempo/mood/
/// time/rating/exclusions, then 'Play Late Night Drive' becomes an
/// intelligent queue." No "energy" field exists anywhere on [BaseTrack]
/// (checked: only `bpm`, not a separate 0-100 energy value), so this
/// deliberately folds the spec's "Energy" and "Tempo" fields into the one
/// real numeric signal this codebase actually tracks per track —
/// [minBpm]/[maxBpm] — rather than inventing a second axis with nothing
/// behind it.
class CustomMood {
  final String id;
  final String name;

  /// OR-matched against [BaseTrack.genres] — empty means "no genre
  /// filter," not "matches nothing" (see [matches]'s own doc for why an
  /// entirely-empty mood is the one case that *does* match nothing).
  final List<String> genres;

  /// OR-matched against [BaseTrack.mood].
  final List<String> moodTags;

  final double? minBpm;
  final double? maxBpm;

  /// `>=` against a caller-supplied rating lookup. `null`/`0` means no
  /// floor.
  final int? ratingFloor;

  /// When set, tracks played within this many days are excluded — UI_SPEC
  /// §13's "Exclude: Played in last 7 days." `null` means no exclusion.
  final int? excludeRecentlyPlayedDays;

  /// Minutes since midnight, UI_SPEC §13's "Time: 9 PM – 3 AM." Cosmetic
  /// only — see [isInTimeWindow]'s doc for why this never filters tracks.
  /// Both null or both non-null; a lone bound is treated as "no window."
  final int? windowStartMinutes;
  final int? windowEndMinutes;

  final Color? color;
  final CustomMoodIcon icon;

  const CustomMood({
    required this.id,
    required this.name,
    this.genres = const [],
    this.moodTags = const [],
    this.minBpm,
    this.maxBpm,
    this.ratingFloor,
    this.excludeRecentlyPlayedDays,
    this.windowStartMinutes,
    this.windowEndMinutes,
    this.color,
    this.icon = CustomMoodIcon.mood,
  });

  CustomMood copyWith({
    String? name,
    List<String>? genres,
    List<String>? moodTags,
    double? minBpm,
    bool clearMinBpm = false,
    double? maxBpm,
    bool clearMaxBpm = false,
    int? ratingFloor,
    bool clearRatingFloor = false,
    int? excludeRecentlyPlayedDays,
    bool clearExcludeRecentlyPlayedDays = false,
    int? windowStartMinutes,
    int? windowEndMinutes,
    bool clearWindow = false,
    Color? color,
    bool clearColor = false,
    CustomMoodIcon? icon,
  }) {
    return CustomMood(
      id: id,
      name: name ?? this.name,
      genres: genres ?? this.genres,
      moodTags: moodTags ?? this.moodTags,
      minBpm: clearMinBpm ? null : (minBpm ?? this.minBpm),
      maxBpm: clearMaxBpm ? null : (maxBpm ?? this.maxBpm),
      ratingFloor: clearRatingFloor ? null : (ratingFloor ?? this.ratingFloor),
      excludeRecentlyPlayedDays: clearExcludeRecentlyPlayedDays
          ? null
          : (excludeRecentlyPlayedDays ?? this.excludeRecentlyPlayedDays),
      windowStartMinutes:
          clearWindow ? null : (windowStartMinutes ?? this.windowStartMinutes),
      windowEndMinutes:
          clearWindow ? null : (windowEndMinutes ?? this.windowEndMinutes),
      color: clearColor ? null : (color ?? this.color),
      icon: icon ?? this.icon,
    );
  }

  /// Whether [track] belongs in this mood's queue. ALL configured criteria
  /// must hold (there is no ANY/NONE choice here, unlike
  /// `smart_playlist_rule.dart`'s `SmartPlaylistRule.matchType` — a mood
  /// is a single cohesive vibe, not a general-purpose rule builder).
  /// [ratingOf]/[recentlyPlayedIds] are caller-supplied lookups, the same
  /// "pure function, caller joins the data" shape
  /// `smart_playlist_rule.dart`'s `RuleCondition.matches` already
  /// established. Never throws.
  ///
  /// A mood with none of genres/moodTags/minBpm/maxBpm/ratingFloor set
  /// matches nothing — same "not yet configured, not 'everything'"
  /// contract `SmartPlaylistRule.apply` uses for an empty condition list.
  bool matches(
    BaseTrack track, {
    required int Function(String trackId) ratingOf,
    required Set<String> recentlyPlayedIds,
  }) {
    if (genres.isEmpty &&
        moodTags.isEmpty &&
        minBpm == null &&
        maxBpm == null &&
        ratingFloor == null) {
      return false;
    }
    if (genres.isNotEmpty) {
      final lowerGenres = genres.map((g) => g.toLowerCase()).toSet();
      if (!track.genres.any((g) => lowerGenres.contains(g.toLowerCase()))) {
        return false;
      }
    }
    if (moodTags.isNotEmpty) {
      final trackMood = track.mood?.toLowerCase();
      final lowerTags = moodTags.map((m) => m.toLowerCase()).toSet();
      if (trackMood == null || !lowerTags.contains(trackMood)) return false;
    }
    if (minBpm != null || maxBpm != null) {
      final bpm = track.bpm;
      if (bpm == null) return false;
      if (minBpm != null && bpm < minBpm!) return false;
      if (maxBpm != null && bpm > maxBpm!) return false;
    }
    if (ratingFloor != null && ratingOf(track.id) < ratingFloor!) {
      return false;
    }
    if (excludeRecentlyPlayedDays != null &&
        recentlyPlayedIds.contains(track.id)) {
      return false;
    }
    return true;
  }

  /// Whether [now] falls inside this mood's optional suggested time
  /// window, wrapping past midnight when [windowStartMinutes] >
  /// [windowEndMinutes] (e.g. 9 PM – 3 AM). Always `true` when no window
  /// is set. Deliberately never used to filter which *tracks* match —
  /// UI_SPEC §13 frames "Time: 9 PM – 3 AM" as when this mood makes sense
  /// to suggest (surfaced as a "Suggested now" badge on the Moods grid),
  /// not a property of the tracks themselves the way genre/BPM/rating are.
  bool isInTimeWindow(DateTime now) {
    final start = windowStartMinutes;
    final end = windowEndMinutes;
    if (start == null || end == null) return true;
    final minutesNow = now.hour * 60 + now.minute;
    if (start <= end) {
      return minutesNow >= start && minutesNow <= end;
    }
    // Wraps past midnight, e.g. 21:00–03:00.
    return minutesNow >= start || minutesNow <= end;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'genres': genres,
        'moodTags': moodTags,
        'minBpm': minBpm,
        'maxBpm': maxBpm,
        'ratingFloor': ratingFloor,
        'excludeRecentlyPlayedDays': excludeRecentlyPlayedDays,
        'windowStartMinutes': windowStartMinutes,
        'windowEndMinutes': windowEndMinutes,
        'color': color != null ? _packArgb(color!) : null,
        'icon': icon.name,
      };

  /// Returns `null` for a malformed entry rather than throwing — the same
  /// per-entry-defensive contract every JSON-backed store in this app
  /// already follows (see `PlaylistStore.load`/`LibraryStore`'s
  /// `_decodeTracks`), so one corrupted saved mood can't wipe every other
  /// saved mood.
  static CustomMood? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final rawColor = json['color'];
    final iconName = json['icon'];
    return CustomMood(
      id: id,
      name: name,
      genres: (json['genres'] is List)
          ? List<String>.from(json['genres'] as List)
          : const [],
      moodTags: (json['moodTags'] is List)
          ? List<String>.from(json['moodTags'] as List)
          : const [],
      minBpm: (json['minBpm'] as num?)?.toDouble(),
      maxBpm: (json['maxBpm'] as num?)?.toDouble(),
      ratingFloor: json['ratingFloor'] as int?,
      excludeRecentlyPlayedDays: json['excludeRecentlyPlayedDays'] as int?,
      windowStartMinutes: json['windowStartMinutes'] as int?,
      windowEndMinutes: json['windowEndMinutes'] as int?,
      color: rawColor is int ? Color(rawColor) : null,
      icon: iconName is String
          ? CustomMoodIcon.values.firstWhere(
              (v) => v.name == iconName,
              orElse: () => CustomMoodIcon.mood,
            )
          : CustomMoodIcon.mood,
    );
  }
}

/// This store's current on-disk shape version — see
/// `schema_versioning.dart`.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// Persists user-created [CustomMood]s — the same load/save shape as
/// `PlaylistStore`: one JSON file in the app's documents directory, the
/// caller (the Moods page) owns the in-memory list and decides when to
/// save, rather than this store caching state itself. Custom moods are
/// only ever read by the Moods page, unlike the library (read by four
/// pages at once), so there's no need for a `LibraryRepository`-style
/// shared-cache wrapper here.
class CustomMoodStore {
  CustomMoodStore._();

  static final CustomMoodStore instance = CustomMoodStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_custom_moods.json');
    return _file!;
  }

  /// Load persisted custom moods. Returns an empty list if none exist or
  /// the file is corrupt — never throws.
  Future<List<CustomMood>> load() async {
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
      final moods = <CustomMood>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        final mood = CustomMood.fromJson(Map<String, dynamic>.from(entry));
        if (mood != null) moods.add(mood);
      }
      return moods;
    } catch (e) {
      return [];
    }
  }

  /// Persist [moods] to disk. Atomic write (sibling `.tmp` + rename), the
  /// same crash/power-loss-safe pattern `PlaylistStore.save`/
  /// `LibraryStore._flushPending` already use — this is user-authored
  /// content a rescan can't regenerate.
  Future<void> save(List<CustomMood> moods) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          moods.map((m) => m.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Test-only: drops the cached file handle so each test starts clean
  /// regardless of what an earlier test in the same file resolved to —
  /// mirrors `LibraryRepository.resetForTesting`.
  void resetForTesting() {
    _file = null;
  }
}
