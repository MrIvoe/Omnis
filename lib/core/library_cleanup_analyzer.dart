import 'dart:io';

import 'package:omnis/core/base_track.dart';
import 'package:path/path.dart' as p;

/// One category from spec §20's "Music Library Cleanup" report — a
/// count plus the actual tracks (or track groups) it counted, so a
/// guided-cleanup UI can act on the same data the count came from
/// rather than re-deriving it.
class LibraryCleanupCategory {
  final String label;
  final int count;

  const LibraryCleanupCategory({required this.label, required this.count});
}

/// The full report — one field per category, in the same order spec
/// §20's sample output lists them. Each category also exposes the
/// tracks/groups it flagged, for guided cleanup to act on.
class LibraryCleanupReport {
  final List<BaseTrack> missingArtwork;
  final List<BaseTrack> inconsistentArtists;
  final List<List<BaseTrack>> duplicateTrackGroups;
  final List<String> albumsMissingYear;
  final List<BaseTrack> malformedTrackNumbers;
  final List<BaseTrack> inconsistentGenres;
  final List<List<BaseTrack>> duplicateAlbumGroups;
  final List<BaseTrack> corruptFiles;

  /// Local tracks whose codec is a known-lossy format at a bitrate below
  /// [LibraryCleanupAnalyzer.lowQualityBitrateThresholdKbps] — spec §9's
  /// "Low-quality files" category. Lossless tracks and any track with an
  /// unknown bitrate are never flagged, the same "don't manufacture a
  /// claim the data can't support" stance [corruptFiles]'s own doc
  /// comment already states.
  final List<BaseTrack> lowQualityFiles;

  /// Local tracks whose file no longer exists on disk. Always `const []`
  /// on the report [LibraryCleanupAnalyzer.analyze] itself returns —
  /// filled in afterward by a caller that awaits
  /// [LibraryCleanupAnalyzer.findMissingFiles] separately and applies it
  /// via [copyWithMissingFiles], since checking real files is genuine
  /// I/O that [analyze]'s own "no new I/O, work from what's already
  /// loaded" contract deliberately excludes.
  final List<BaseTrack> missingFiles;

  /// Local tracks whose file doesn't live in a `<primary artist>/<album>/`
  /// folder structure — spec §9's third and last named Library Health
  /// Center category. Reads only the file's own path (already loaded, no
  /// new I/O — same contract every category above [missingFiles]
  /// already has), comparing the immediate parent folder against
  /// [BaseTrack.album] and the grandparent against the primary artist,
  /// both normalized the same way [_duplicateAlbums] already does. A
  /// track with a blank artist/album, or too few path segments to have a
  /// real two-level folder at all, is never flagged — nothing to
  /// meaningfully compare against, the same "don't manufacture a claim
  /// the data can't support" stance every other category here takes.
  final List<BaseTrack> unorganizedFiles;

  const LibraryCleanupReport({
    required this.missingArtwork,
    required this.inconsistentArtists,
    required this.duplicateTrackGroups,
    required this.albumsMissingYear,
    required this.malformedTrackNumbers,
    required this.inconsistentGenres,
    required this.duplicateAlbumGroups,
    required this.corruptFiles,
    this.lowQualityFiles = const [],
    this.missingFiles = const [],
    this.unorganizedFiles = const [],
  });

  /// A copy with [missingFiles] filled in — see that field's own doc for
  /// why this is applied after the fact rather than being part of the
  /// synchronous [LibraryCleanupAnalyzer.analyze] pass.
  LibraryCleanupReport copyWithMissingFiles(List<BaseTrack> missingFiles) =>
      LibraryCleanupReport(
        missingArtwork: missingArtwork,
        inconsistentArtists: inconsistentArtists,
        duplicateTrackGroups: duplicateTrackGroups,
        albumsMissingYear: albumsMissingYear,
        malformedTrackNumbers: malformedTrackNumbers,
        inconsistentGenres: inconsistentGenres,
        duplicateAlbumGroups: duplicateAlbumGroups,
        corruptFiles: corruptFiles,
        lowQualityFiles: lowQualityFiles,
        missingFiles: missingFiles,
        unorganizedFiles: unorganizedFiles,
      );

  int get duplicateTracksCount =>
      duplicateTrackGroups.fold(0, (sum, g) => sum + g.length);

  int get duplicateAlbumsCount => duplicateAlbumGroups.length;

  List<LibraryCleanupCategory> get categories => [
        LibraryCleanupCategory(
            label: 'missing artwork', count: missingArtwork.length),
        LibraryCleanupCategory(
            label: 'inconsistent artists', count: inconsistentArtists.length),
        LibraryCleanupCategory(
            label: 'duplicate tracks', count: duplicateTracksCount),
        LibraryCleanupCategory(
            label: 'albums missing year', count: albumsMissingYear.length),
        LibraryCleanupCategory(
            label: 'malformed track numbers',
            count: malformedTrackNumbers.length),
        LibraryCleanupCategory(
            label: 'inconsistent genres', count: inconsistentGenres.length),
        LibraryCleanupCategory(
            label: 'duplicate albums', count: duplicateAlbumsCount),
        LibraryCleanupCategory(label: 'corrupt files', count: corruptFiles.length),
        LibraryCleanupCategory(
            label: 'low-quality files', count: lowQualityFiles.length),
        LibraryCleanupCategory(
            label: 'missing files', count: missingFiles.length),
        LibraryCleanupCategory(
            label: 'unorganized files', count: unorganizedFiles.length),
      ];

  /// Whether every category came back clean — the report UI's "nothing
  /// to clean up" state.
  bool get isClean => categories.every((c) => c.count == 0);
}

/// Extensions [AudioFormatReader] parses a real header for today — used
/// by [LibraryCleanupAnalyzer.analyze]'s "corrupt files" heuristic.
/// Duplicated here rather than imported from `audio_format_reader.dart`
/// (which isn't otherwise a dependency of this pure-data analyzer) —
/// small, stable list, not worth a cross-file coupling for.
const _fullyParsedExtensions = {
  'flac', 'wav', 'mp3', //
  'aiff', 'aif', 'aifc',
  'ogg', 'oga', 'opus',
  'm4a',
  'wma',
};

String _normalize(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
}

/// Computes spec §20's "Music Library Cleanup" analysis — a set of
/// counts (missing artwork, inconsistent artists, duplicate tracks,
/// albums missing year, malformed track numbers, inconsistent genres,
/// duplicate albums, corrupt files) purely from already-scanned
/// [BaseTrack] data, the same "no new I/O, work from what's already
/// loaded" shape `findDuplicateTracks`/`findShortTracks` in
/// `library_page.dart` already use — this deliberately doesn't trigger
/// a fresh scan or re-read any file.
class LibraryCleanupAnalyzer {
  const LibraryCleanupAnalyzer._();

  /// The conventional "low bitrate" floor for a lossy encode — below
  /// this, quality loss is broadly audible regardless of the specific
  /// lossy codec. Matches [_lossyCodecs]' own scope: only meaningful for
  /// a lossy format, never applied to a lossless one.
  static const lowQualityBitrateThresholdKbps = 128;

  static LibraryCleanupReport analyze(List<BaseTrack> tracks) {
    return LibraryCleanupReport(
      missingArtwork: _missingArtwork(tracks),
      inconsistentArtists: _inconsistentByAlbum(
          tracks, (t) => t.artists.isNotEmpty ? t.artists.first : ''),
      duplicateTrackGroups: _duplicateTracks(tracks),
      albumsMissingYear: _albumsMissingYear(tracks),
      malformedTrackNumbers: _malformedTrackNumbers(tracks),
      inconsistentGenres: _inconsistentByAlbum(
          tracks, (t) => t.genres.isNotEmpty ? t.genres.first : ''),
      duplicateAlbumGroups: _duplicateAlbums(tracks),
      corruptFiles: _corruptFiles(tracks),
      lowQualityFiles: _lowQualityFiles(tracks),
      unorganizedFiles: _unorganizedFiles(tracks),
    );
  }

  static List<BaseTrack> _missingArtwork(List<BaseTrack> tracks) => tracks
      .where((t) => t.coverArt == null || t.coverArt!.trim().isEmpty)
      .toList();

  /// Groups [tracks] by normalized album (blank albums excluded — an
  /// untitled "album" isn't a real grouping to compare within), then
  /// flags every track whose [valueOf] result disagrees with at least
  /// one other track in the same album — the same shape for both
  /// "inconsistent artists" (primary artist) and "inconsistent genres"
  /// (primary genre), just a different field selector.
  static List<BaseTrack> _inconsistentByAlbum(
    List<BaseTrack> tracks,
    String Function(BaseTrack) valueOf,
  ) {
    final byAlbum = <String, List<BaseTrack>>{};
    for (final t in tracks) {
      final album = t.album.trim();
      if (album.isEmpty) continue;
      byAlbum.putIfAbsent(_normalize(album), () => []).add(t);
    }

    final flagged = <BaseTrack>[];
    for (final group in byAlbum.values) {
      final distinctValues = <String>{};
      for (final t in group) {
        final value = valueOf(t).trim();
        if (value.isNotEmpty) distinctValues.add(value);
      }
      if (distinctValues.length < 2) continue;
      for (final t in group) {
        if (valueOf(t).trim().isNotEmpty) flagged.add(t);
      }
    }
    return flagged;
  }

  static List<List<BaseTrack>> _duplicateTracks(List<BaseTrack> tracks) {
    final groups = <String, List<BaseTrack>>{};
    for (final t in tracks) {
      final artist = t.artists.isNotEmpty ? t.artists.first : '';
      final key = '${_normalize(t.title)}|${_normalize(artist)}';
      groups.putIfAbsent(key, () => []).add(t);
    }
    return groups.values.where((g) => g.length > 1).toList();
  }

  /// Distinct album names (raw, as first seen) where *every* track in
  /// that album has no [BaseTrack.year] — an album with even one dated
  /// track isn't "missing year" as a whole, since the value is probably
  /// just recoverable from a sibling track.
  static List<String> _albumsMissingYear(List<BaseTrack> tracks) {
    final byAlbum = <String, List<BaseTrack>>{};
    final rawNameOf = <String, String>{};
    for (final t in tracks) {
      final album = t.album.trim();
      if (album.isEmpty) continue;
      final key = _normalize(album);
      byAlbum.putIfAbsent(key, () => []).add(t);
      rawNameOf.putIfAbsent(key, () => album);
    }
    final result = <String>[];
    byAlbum.forEach((key, group) {
      if (group.every((t) => t.year == null)) {
        result.add(rawNameOf[key]!);
      }
    });
    return result;
  }

  /// A track number only makes sense in the context of a real album —
  /// an album-less track (a single loose file, or a station) isn't
  /// "malformed" for lacking one.
  static List<BaseTrack> _malformedTrackNumbers(List<BaseTrack> tracks) =>
      tracks
          .where((t) =>
              t.album.trim().isNotEmpty &&
              (t.trackNumber == null || t.trackNumber! <= 0))
          .toList();

  /// The same logical album appearing under two or more differently-
  /// spelled/cased/whitespaced exact strings — e.g. "Abbey Road" and
  /// "Abbey  Road " — which would otherwise show as two separate albums
  /// in any album-grouped view despite being the same release. Grouped
  /// first by the *raw* (album, primary-artist) pair (so genuinely
  /// distinct artists' same-named albums, e.g. two different "Greatest
  /// Hits", are never conflated), then those raw variants are grouped
  /// again by their normalized form; a normalized key with 2+ distinct
  /// raw variants is the duplicate.
  static List<List<BaseTrack>> _duplicateAlbums(List<BaseTrack> tracks) {
    final byRawVariant = <String, List<BaseTrack>>{};
    for (final t in tracks) {
      final album = t.album.trim();
      if (album.isEmpty) continue;
      final artist = t.artists.isNotEmpty ? t.artists.first.trim() : '';
      byRawVariant.putIfAbsent('$album|$artist', () => []).add(t);
    }

    final byNormalizedKey = <String, Set<String>>{};
    for (final rawKey in byRawVariant.keys) {
      final parts = rawKey.split('|');
      final normalizedKey = '${_normalize(parts[0])}|${_normalize(parts.length > 1 ? parts[1] : '')}';
      byNormalizedKey.putIfAbsent(normalizedKey, () => {}).add(rawKey);
    }

    final result = <List<BaseTrack>>[];
    byNormalizedKey.forEach((normalizedKey, rawVariants) {
      if (rawVariants.length < 2) return;
      final combined = <BaseTrack>[];
      for (final rawKey in rawVariants) {
        combined.addAll(byRawVariant[rawKey]!);
      }
      result.add(combined);
    });
    return result;
  }

  /// A local track whose extension is one this app's `AudioFormatReader`
  /// fully parses today, but whose [BaseTrack.codec] is still `null` —
  /// a real (if imperfect) proxy for "the header wouldn't parse," since
  /// every fully-supported extension always yields a non-null codec
  /// label on a successful parse. Not a certainty: a `null` codec here
  /// can also mean the track was scanned before the `codec` field
  /// existed at all, which this analyzer — deliberately working only
  /// from already-scanned data, never triggering a fresh read — has no
  /// way to distinguish from a genuine parse failure.
  static List<BaseTrack> _corruptFiles(List<BaseTrack> tracks) => tracks
      .where((t) =>
          t.type == TrackType.local &&
          t.localPath != null &&
          t.codec == null &&
          _fullyParsedExtensions.contains(_extensionOf(t.localPath!)))
      .toList();

  /// Known-lossy codec labels — the exact strings `AudioFormatReader`
  /// actually produces (confirmed by reading it directly). Duplicated
  /// from `library_statistics.dart`'s identical set rather than
  /// cross-imported — small, stable list, the same "not worth a
  /// cross-file coupling" reasoning [_fullyParsedExtensions] above
  /// already applies. `AAC/ALAC (M4A)` is deliberately excluded: it's a
  /// container, not a codec, and can hold either lossy AAC or lossless
  /// ALAC — flagging it either way would be a guess, not a finding.
  static const _lossyCodecs = {'MP3', 'Ogg', 'Ogg Vorbis', 'Opus', 'WMA', 'AAC'};

  /// A local track encoded in a known-lossy format below
  /// [lowQualityBitrateThresholdKbps] — spec §9's "Low-quality files"
  /// category. A lossless track, an unrecognized/ambiguous codec, or a
  /// track with no known bitrate is never flagged.
  static List<BaseTrack> _lowQualityFiles(List<BaseTrack> tracks) => tracks
      .where((t) =>
          t.type == TrackType.local &&
          t.codec != null &&
          _lossyCodecs.contains(t.codec) &&
          t.bitrateKbps != null &&
          t.bitrateKbps! < lowQualityBitrateThresholdKbps)
      .toList();

  /// A local track whose file doesn't sit in the conventional
  /// `<primary artist>/<album>/<file>` folder layout — spec §9's
  /// "Unorganized files" category. Uses `path.split` on
  /// [BaseTrack.localPath] rather than raw string slicing, since
  /// separator conventions differ (`\` on Windows, `/` elsewhere) and
  /// this analyzer runs against paths a real scan produced on whatever
  /// platform did the scanning. Flags a track with fewer than 2 real
  /// path segments before the filename (no folder structure at all —
  /// e.g. a file dropped directly in the library root), or whose
  /// immediate parent folder doesn't normalize-match [BaseTrack.album]
  /// or whose grandparent doesn't normalize-match the primary artist. A
  /// track with a blank artist or album is never flagged — there's
  /// nothing real to compare the folder name against.
  static List<BaseTrack> _unorganizedFiles(List<BaseTrack> tracks) {
    final flagged = <BaseTrack>[];
    for (final t in tracks) {
      if (t.type != TrackType.local || t.localPath == null) continue;
      final album = t.album.trim();
      final artist = t.artists.isNotEmpty ? t.artists.first.trim() : '';
      if (album.isEmpty || artist.isEmpty) continue;

      // Segments before the filename itself, e.g. for
      // "/music/Queen/A Night at the Opera/track.flac" this is
      // ["", "music", "Queen", "A Night at the Opera"].
      final segments = p.split(p.dirname(t.localPath!));
      if (segments.length < 2) {
        flagged.add(t);
        continue;
      }
      final albumFolder = segments[segments.length - 1];
      final artistFolder = segments[segments.length - 2];
      if (_normalize(albumFolder) != _normalize(album) ||
          _normalize(artistFolder) != _normalize(artist)) {
        flagged.add(t);
      }
    }
    return flagged;
  }

  /// Local tracks whose file no longer exists on disk — moved, renamed
  /// outside the app, or deleted since the last scan. Deliberately a
  /// separate method from [analyze], not folded into it: this is the one
  /// category spec §20's "Music Library Cleanup" names that genuinely
  /// needs real I/O (`File.exists()`), so it stays opt-in rather than
  /// silently making every call to [analyze] touch the filesystem. Never
  /// throws for an individual track — a permission error or transient
  /// filesystem hiccup checking one file degrades to "treat as present"
  /// (skip it) rather than failing the whole scan or wrongly flagging a
  /// file that's actually fine.
  static Future<List<BaseTrack>> findMissingFiles(
    List<BaseTrack> tracks,
  ) async {
    final candidates =
        tracks.where((t) => t.type == TrackType.local && t.localPath != null);
    final checked = await Future.wait(candidates.map((t) async {
      try {
        final exists = await File(t.localPath!).exists();
        return exists ? null : t;
      } catch (_) {
        return null;
      }
    }));
    return checked.whereType<BaseTrack>().toList();
  }
}
