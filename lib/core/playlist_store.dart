import 'dart:convert';
import 'dart:io';

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/schema_versioning.dart';
import 'package:omnis_plugin_api/playlist.dart';
import 'package:path_provider/path_provider.dart';

// `Playlist` moved to `omnis_plugin_api` (see that package's
// `playlist.dart`) so `PluginContext.loadPlaylists()` can return it
// without depending on this file. Re-exported so every existing
// `import 'package:omnis/core/playlist_store.dart'` in this app keeps
// getting both `PlaylistStore` and `Playlist` unchanged.
export 'package:omnis_plugin_api/playlist.dart' show Playlist;

/// This store's current on-disk shape version — see
/// `schema_versioning.dart`. [_migrations] is empty because no real
/// migration has ever been needed yet (this is the payload's first
/// versioned release, item 4's "no schema migration system" gap); a
/// future format change adds an entry keyed by the version it upgrades
/// *from*.
const _currentSchemaVersion = 1;
const _migrations = <int, SchemaMigration>{};

/// Result of [PlaylistStore.exportM3U].
class M3UExportResult {
  /// The M3U8 file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — a streaming-only track
  /// (Spotify/YouTube) has no local file an M3U player could open, or a
  /// track id no longer exists in the library at all.
  final int skippedCount;

  const M3UExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.importM3U].
class M3UImportResult {
  /// The new playlist, built from whichever entries matched the current
  /// library. Not yet saved — the caller decides when to persist it
  /// (typically by adding it to their in-memory list and calling
  /// [PlaylistStore.save]), matching how every other playlist mutation
  /// in this app works.
  final Playlist playlist;

  /// How many entries matched a track in the current library.
  final int matchedCount;

  /// How many entries didn't match — a moved/renamed/missing file, or a
  /// track that was never scanned into this library.
  final int skippedCount;

  const M3UImportResult({
    required this.playlist,
    required this.matchedCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.exportPLS].
class PLSExportResult {
  /// The PLS file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — same reasons as
  /// [M3UExportResult.skippedCount].
  final int skippedCount;

  const PLSExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.importPLS].
class PLSImportResult {
  /// The new playlist, built from whichever entries matched the current
  /// library. Not yet saved — same contract as [M3UImportResult.playlist].
  final Playlist playlist;

  /// How many entries matched a track in the current library.
  final int matchedCount;

  /// How many entries didn't match.
  final int skippedCount;

  const PLSImportResult({
    required this.playlist,
    required this.matchedCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.exportXSPF].
class XSPFExportResult {
  /// The XSPF (XML) file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — same reasons as
  /// [M3UExportResult.skippedCount].
  final int skippedCount;

  const XSPFExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.importXSPF].
class XSPFImportResult {
  /// The new playlist, built from whichever entries matched the current
  /// library. Not yet saved — same contract as [M3UImportResult.playlist].
  final Playlist playlist;

  /// How many entries matched a track in the current library.
  final int matchedCount;

  /// How many entries didn't match.
  final int skippedCount;

  const XSPFImportResult({
    required this.playlist,
    required this.matchedCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.exportCSV].
class CSVExportResult {
  /// The CSV file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — a track id no longer in the
  /// library. Unlike [M3UExportResult.skippedCount] and its PLS/XSPF
  /// siblings, a streaming-only track is never skipped here — see
  /// [PlaylistStore.exportCSV]'s own doc for why.
  final int skippedCount;

  const CSVExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Result of [PlaylistStore.exportJSON].
class JSONExportResult {
  /// The JSON file content, ready to write to disk.
  final String content;

  /// How many playlist entries were written.
  final int writtenCount;

  /// How many entries were skipped — same reason as
  /// [CSVExportResult.skippedCount].
  final int skippedCount;

  const JSONExportResult({
    required this.content,
    required this.writtenCount,
    required this.skippedCount,
  });
}

/// Persists named playlists to disk, the same load/save shape as
/// `LibraryStore` — one JSON file in the app's documents directory, the
/// caller owns the in-memory list and decides when to save.
class PlaylistStore {
  PlaylistStore._();

  static final PlaylistStore instance = PlaylistStore._();

  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/omnis_playlists.json');
    return _file!;
  }

  /// Load persisted playlists. Returns an empty list if none exist.
  ///
  /// Each entry is decoded independently and a failure skips just that
  /// one playlist — `Playlist.fromJson` hard-casts `id`/`name` and
  /// throws on anything malformed. A single corrupted record among many
  /// used to throw out of a bulk `.map(...)`, wiping *every* playlist —
  /// the user's own hand-curated content, with nothing to regenerate it
  /// from — over one bad entry. Same rationale as `LibraryStore`'s
  /// identical per-entry guard.
  Future<List<Playlist>> load() async {
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
      final playlists = <Playlist>[];
      for (final entry in migrated) {
        if (entry is! Map) continue;
        try {
          playlists.add(Playlist.fromJson(Map<String, dynamic>.from(entry)));
        } catch (_) {
          continue;
        }
      }
      return playlists;
    } catch (e) {
      // Corrupt or unreadable file: treat as empty, don't crash.
      return [];
    }
  }

  /// Persist the given playlists to disk.
  ///
  /// Writes to a sibling `.tmp` file and renames it over the real path —
  /// atomic on the filesystems this app targets, so a crash/power-loss
  /// mid-write leaves the previous complete file intact rather than a
  /// truncated one (the same corruption `LibraryStore.save` guards
  /// against, and just as costly here: this is the user's own
  /// hand-built playlists, not something a rescan can regenerate).
  Future<void> save(List<Playlist> playlists) async {
    try {
      final file = await _getFile();
      final json = jsonEncode(wrapVersioned(
          playlists.map((p) => p.toJson()).toList(), _currentSchemaVersion));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    } catch (e) {
      // Best-effort persistence; a failure here must never crash the app.
    }
  }

  /// Renders [playlist] as M3U8 content, resolving each track id against
  /// [tracks]. Only local tracks with a real file path can be
  /// represented — a streaming-only entry (Spotify/YouTube) or a track
  /// id no longer in the library is skipped, not written as a broken
  /// reference.
  M3UExportResult exportM3U(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final buffer = StringBuffer('#EXTM3U\n');
    var written = 0;
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null || track.type != TrackType.local || track.localPath == null) {
        skipped++;
        continue;
      }
      final artist = track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown Artist';
      buffer.writeln('#EXTINF:${track.duration},$artist - ${track.title}');
      buffer.writeln(track.localPath);
      written++;
    }
    return M3UExportResult(
      content: buffer.toString(),
      writtenCount: written,
      skippedCount: skipped,
    );
  }

  /// Parses M3U/M3U8 [content] into a new playlist named [name], matching
  /// each file path against [tracks]' own [BaseTrack.localPath]. Falls
  /// back to matching on filename alone when the full path doesn't match
  /// — a playlist exported on a different machine (or a different
  /// library folder) commonly has paths that don't line up exactly, but
  /// the filenames usually still do. Comment lines (`#...`, including
  /// `#EXTINF` metadata) and blank lines are ignored; this only reads the
  /// path lines. Never throws — an unreadable line is just skipped.
  ///
  /// Not persisted — see [M3UImportResult.playlist]'s doc.
  M3UImportResult importM3U(
    String content,
    List<BaseTrack> tracks, {
    required String name,
  }) {
    final byPath = {
      for (final t in tracks)
        if (t.localPath != null) t.localPath!: t,
    };
    final byFilename = {
      for (final t in tracks)
        if (t.localPath != null) _basename(t.localPath!): t,
    };

    final trackIds = <String>[];
    var skipped = 0;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final track = byPath[line] ?? byFilename[_basename(line)];
      if (track != null) {
        trackIds.add(track.id);
      } else {
        skipped++;
      }
    }

    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: trackIds,
      createdAt: DateTime.now(),
    );
    return M3UImportResult(
      playlist: playlist,
      matchedCount: trackIds.length,
      skippedCount: skipped,
    );
  }

  /// Matches a PLS `FileN=` entry line — the only PLS field this store
  /// reads on import (`TitleN=`/`LengthN=` are display-only metadata a
  /// player can regenerate from the resolved track itself, the same
  /// reason [importM3U] only reads path lines and ignores `#EXTINF`).
  /// Case-insensitive: real-world PLS files aren't perfectly consistent
  /// about `File1=` vs. `file1=`. The `N` itself is never read — entries
  /// are taken in file-line order, the same convention [importM3U]
  /// already uses, rather than trusting `NumberOfEntries`/each line's own
  /// index (a hand-edited or non-conforming file could have either wrong
  /// without the entries themselves being any less readable).
  static final _plsFileLine = RegExp(r'^File\d+\s*=\s*(.+)$', caseSensitive: false);

  /// Renders [playlist] as PLS content, the same track-resolution rules
  /// [exportM3U] uses (local tracks with a real file path only). PLS's
  /// own format: a `[playlist]` header, `File`/`Title`/`Length` triples
  /// numbered from 1, then `NumberOfEntries` and `Version=2` — see
  /// http://forums.winamp.com/showthread.php?threadid=65772 (the format's
  /// original, still-canonical spec).
  PLSExportResult exportPLS(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final entries = <BaseTrack>[];
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null || track.type != TrackType.local || track.localPath == null) {
        skipped++;
        continue;
      }
      entries.add(track);
    }
    final buffer = StringBuffer('[playlist]\n');
    for (var i = 0; i < entries.length; i++) {
      final track = entries[i];
      final n = i + 1;
      final artist = track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown Artist';
      buffer.writeln('File$n=${track.localPath}');
      buffer.writeln('Title$n=$artist - ${track.title}');
      buffer.writeln('Length$n=${track.duration}');
    }
    buffer.writeln('NumberOfEntries=${entries.length}');
    buffer.writeln('Version=2');
    return PLSExportResult(
      content: buffer.toString(),
      writtenCount: entries.length,
      skippedCount: skipped,
    );
  }

  /// Parses PLS [content] into a new playlist named [name] — the same
  /// path-then-filename matching [importM3U] uses, since a PLS file
  /// exported elsewhere commonly has paths that don't line up exactly on
  /// this machine either. Never throws — a line that isn't a `FileN=`
  /// entry (a `Title`/`Length`/`NumberOfEntries`/`Version` line, the
  /// `[playlist]` header, a blank line) is simply not matched, not an
  /// error.
  ///
  /// Not persisted — see [PLSImportResult.playlist]'s doc.
  PLSImportResult importPLS(
    String content,
    List<BaseTrack> tracks, {
    required String name,
  }) {
    final byPath = {
      for (final t in tracks)
        if (t.localPath != null) t.localPath!: t,
    };
    final byFilename = {
      for (final t in tracks)
        if (t.localPath != null) _basename(t.localPath!): t,
    };

    final trackIds = <String>[];
    var skipped = 0;
    for (final rawLine in const LineSplitter().convert(content)) {
      final match = _plsFileLine.firstMatch(rawLine.trim());
      if (match == null) continue;
      final path = match.group(1)!.trim();
      if (path.isEmpty) continue;
      final track = byPath[path] ?? byFilename[_basename(path)];
      if (track != null) {
        trackIds.add(track.id);
      } else {
        skipped++;
      }
    }

    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: trackIds,
      createdAt: DateTime.now(),
    );
    return PLSImportResult(
      playlist: playlist,
      matchedCount: trackIds.length,
      skippedCount: skipped,
    );
  }

  /// Matches an XSPF `<location>` element's text content — the only XSPF
  /// field this store reads on import, same "only read what we need to
  /// resolve a track" stance [importPLS] takes for `TitleN`/`LengthN`.
  /// `dotAll` since a hand-formatted file could plausibly wrap long
  /// content across a line (unlikely for a URI, but cheap to tolerate);
  /// case-insensitive for the same real-world-files-aren't-perfectly-
  /// consistent reason [_plsFileLine] already is, even though XSPF's own
  /// spec mandates lowercase element names.
  static final _xspfLocationLine =
      RegExp(r'<location>(.*?)</location>', caseSensitive: false, dotAll: true);

  static String _xmlEscape(String input) => input
      .replaceAll('&', '&amp;') // must run first — every other escape below introduces a literal '&'
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _xmlUnescape(String input) => input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&'); // must run last, mirroring _xmlEscape's "first" ordering

  /// A `<location>` element's content is a URI, not a bare path — export
  /// writes a real `file://` URI via [Uri.file], so this reverses that
  /// for a well-formed one. Falls back to treating [location] as a plain
  /// path when it isn't a `file:` URI at all (a hand-edited or
  /// non-conforming XSPF file, or one produced by a tool that — despite
  /// the spec — wrote a bare path) rather than discarding the entry.
  static String _locationToPath(String location) {
    if (location.startsWith('file:')) {
      try {
        return Uri.parse(location).toFilePath();
      } catch (_) {
        // Not a well-formed file:// URI after all — fall through.
      }
    }
    return location;
  }

  /// Renders [playlist] as XSPF content, the same track-resolution rules
  /// [exportM3U]/[exportPLS] use. XSPF is XML (unlike M3U/PLS's plain
  /// key=value text), built directly here rather than via a dependency —
  /// the shape needed (one `<playlist><trackList>` with a flat list of
  /// `<track>` elements) is simple and fixed enough that hand-writing it
  /// avoids a new package dependency for a handful of `StringBuffer`
  /// lines, the same reasoning every other format reader/writer in this
  /// codebase (`audio_format_reader.dart`'s binary parsers, M3U/PLS
  /// above) already follows.
  XSPFExportResult exportXSPF(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final entries = <BaseTrack>[];
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null || track.type != TrackType.local || track.localPath == null) {
        skipped++;
        continue;
      }
      entries.add(track);
    }
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<playlist version="1" xmlns="http://xspf.org/ns/0/">');
    buffer.writeln('  <trackList>');
    for (final track in entries) {
      final artist = track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown Artist';
      final location = Uri.file(track.localPath!).toString();
      buffer.writeln('    <track>');
      buffer.writeln('      <location>${_xmlEscape(location)}</location>');
      buffer.writeln('      <title>${_xmlEscape(track.title)}</title>');
      buffer.writeln('      <creator>${_xmlEscape(artist)}</creator>');
      // XSPF durations are milliseconds; BaseTrack.duration is seconds.
      buffer.writeln('      <duration>${track.duration * 1000}</duration>');
      buffer.writeln('    </track>');
    }
    buffer.writeln('  </trackList>');
    buffer.writeln('</playlist>');
    return XSPFExportResult(
      content: buffer.toString(),
      writtenCount: entries.length,
      skippedCount: skipped,
    );
  }

  /// Parses XSPF [content] into a new playlist named [name] — the same
  /// path-then-filename matching [importM3U]/[importPLS] use. Never
  /// throws — this is a regex extraction of `<location>` text, not a
  /// real XML parse, so malformed XML around a `<location>` element (an
  /// unclosed unrelated tag elsewhere, wrong attribute quoting) doesn't
  /// prevent still finding and resolving every `<location>` that *is*
  /// well-formed.
  ///
  /// Not persisted — see [XSPFImportResult.playlist]'s doc.
  XSPFImportResult importXSPF(
    String content,
    List<BaseTrack> tracks, {
    required String name,
  }) {
    final byPath = {
      for (final t in tracks)
        if (t.localPath != null) t.localPath!: t,
    };
    final byFilename = {
      for (final t in tracks)
        if (t.localPath != null) _basename(t.localPath!): t,
    };

    final trackIds = <String>[];
    var skipped = 0;
    for (final match in _xspfLocationLine.allMatches(content)) {
      final raw = _xmlUnescape(match.group(1)!.trim());
      if (raw.isEmpty) continue;
      final path = _locationToPath(raw);
      final track = byPath[path] ?? byFilename[_basename(path)];
      if (track != null) {
        trackIds.add(track.id);
      } else {
        skipped++;
      }
    }

    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: trackIds,
      createdAt: DateTime.now(),
    );
    return XSPFImportResult(
      playlist: playlist,
      matchedCount: trackIds.length,
      skippedCount: skipped,
    );
  }

  String _basename(String path) => File(path).uri.pathSegments.isNotEmpty
      ? File(path).uri.pathSegments.last
      : path;

  static const _csvHeader = [
    'Title',
    'Artist',
    'Album',
    'Album Artist',
    'Genre',
    'Year',
    'Track Number',
    'Disc Number',
    'Duration (s)',
    'Type',
    'Local Path',
  ];

  /// Escapes one CSV field per RFC 4180: quoted, with any embedded quote
  /// doubled, whenever the field contains a comma, quote, or newline —
  /// the characters that would otherwise be ambiguous with the format's
  /// own delimiters. A field with none of those is left bare.
  static String _csvEscape(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// Renders [playlist] as CSV, resolving each track id against [tracks].
  /// Unlike [exportM3U]/[exportPLS]/[exportXSPF] — playback formats a
  /// media player has to actually open, so only a local track with a
  /// real file path is representable — CSV/JSON export (§46's
  /// spreadsheet/interchange gap, distinct from "export a file a player
  /// can open") includes **every** resolved track regardless of type: a
  /// Spotify/YouTube/radio entry is real playlist data worth exporting
  /// to a spreadsheet even though nothing here can play it back from the
  /// exported file. A track id no longer in the library is still
  /// skipped — there's genuinely no data left to export for it.
  CSVExportResult exportCSV(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final buffer = StringBuffer();
    buffer.writeln(_csvHeader.join(','));
    var written = 0;
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null) {
        skipped++;
        continue;
      }
      final row = [
        track.title,
        track.artists.join('; '),
        track.album,
        track.albumArtist ?? '',
        track.genres.join('; '),
        track.year?.toString() ?? '',
        track.trackNumber?.toString() ?? '',
        track.discNumber?.toString() ?? '',
        track.duration.toString(),
        track.type.name,
        track.localPath ?? '',
      ];
      buffer.writeln(row.map(_csvEscape).join(','));
      written++;
    }
    return CSVExportResult(
      content: buffer.toString(),
      writtenCount: written,
      skippedCount: skipped,
    );
  }

  /// Renders [playlist] as JSON — a top-level object with the playlist's
  /// own name/creation date and a `tracks` array, one object per
  /// resolved entry. Same every-track-type inclusion rule as
  /// [exportCSV], for the same reason.
  JSONExportResult exportJSON(Playlist playlist, List<BaseTrack> tracks) {
    final byId = {for (final t in tracks) t.id: t};
    final entries = <Map<String, dynamic>>[];
    var skipped = 0;
    for (final id in playlist.trackIds) {
      final track = byId[id];
      if (track == null) {
        skipped++;
        continue;
      }
      entries.add({
        'title': track.title,
        'artists': track.artists,
        'album': track.album,
        'albumArtist': track.albumArtist,
        'genres': track.genres,
        'year': track.year,
        'trackNumber': track.trackNumber,
        'discNumber': track.discNumber,
        'durationSeconds': track.duration,
        'type': track.type.name,
        'localPath': track.localPath,
      });
    }
    final content = const JsonEncoder.withIndent('  ').convert({
      'playlist': playlist.name,
      'createdAt': playlist.createdAt.toIso8601String(),
      'tracks': entries,
    });
    return JSONExportResult(
      content: content,
      writtenCount: entries.length,
      skippedCount: skipped,
    );
  }
}
