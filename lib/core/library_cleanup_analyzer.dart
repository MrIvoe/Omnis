import 'package:omnis/core/base_track.dart';

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

  const LibraryCleanupReport({
    required this.missingArtwork,
    required this.inconsistentArtists,
    required this.duplicateTrackGroups,
    required this.albumsMissingYear,
    required this.malformedTrackNumbers,
    required this.inconsistentGenres,
    required this.duplicateAlbumGroups,
    required this.corruptFiles,
  });

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
}
