import 'package:omnis/core/base_track.dart';
import 'package:path/path.dart' as p;

/// A real, writable [BaseTrack] tag field a [CalculatedTagRule] can
/// build a new value for — the same scope `TagFindReplaceField` already
/// uses, and for the same reason: these are the only fields present on
/// [BaseTrack] itself, so a preview never needs a file read.
enum CalculatedTagTargetField { title, artist, album, genre }

/// spec §12's "virtual/calculated tags" gap (item 17) — read-only,
/// computed pseudo-tag tokens (things like the release year, bitrate,
/// or track duration) usable inside a `{token}` template string to
/// build a brand-new value for one writable field. Distinct from
/// `tag_find_replace.dart`'s [previewFindReplace]: that finds-and-
/// replaces *within* an existing value; this constructs a whole new one
/// from a template, e.g. `{artist} - {title} [{year}]`.
///
/// Every token a template can reference:
///
/// ```text
/// {title}/{artist}/{album}/{genre}  -> the real writable fields
///                                       themselves (their *current*
///                                       value), so a template can
///                                       reference one while building
///                                       another
/// {year}                            -> release year, or "" if unknown
/// {track}                           -> track number, or "" if unknown
/// {disc}                            -> disc number, or "" if unknown
/// {bitrate}                         -> bitrate in kbps, or "" if unknown
/// {duration}                        -> "mm:ss"
/// {codec}                           -> e.g. "FLAC", or "" if unknown
/// {dateAdded}                       -> "YYYY-MM-DD", or "" if unknown
/// {folderName}                      -> the file's immediate parent
///                                       folder name, or "" for a
///                                       non-local track/no path
/// {fileExtension}                   -> e.g. "flac" (no leading dot),
///                                       or "" for a non-local track/no
///                                       path
/// ```
///
/// An unrecognized `{token}` resolves to an empty string rather than
/// being left literally in place or throwing — the same "malformed
/// input degrades quietly, never crashes" contract
/// `tag_find_replace.dart`/`library_search.dart` already establish for
/// their own pattern parsing. Plain text outside `{...}` passes through
/// unchanged, so a template with no recognized tokens at all is just a
/// literal replacement value.
class CalculatedTagRule {
  final CalculatedTagTargetField target;
  final String template;

  const CalculatedTagRule({required this.target, required this.template});
}

/// One track whose [CalculatedTagRule.target] field would actually
/// change under a [CalculatedTagRule] — a track whose resolved template
/// happens to equal its current value is never included, the same
/// "a preview list is exactly what would change" contract
/// `TagFindReplaceMatch` already has.
class CalculatedTagMatch {
  final BaseTrack track;
  final String before;
  final String after;

  const CalculatedTagMatch({
    required this.track,
    required this.before,
    required this.after,
  });
}

final _tokenPattern = RegExp(r'\{(\w+)\}');

String _writableFieldValue(BaseTrack track, CalculatedTagTargetField field) =>
    switch (field) {
      CalculatedTagTargetField.title => track.title,
      CalculatedTagTargetField.artist => track.artists.join(', '),
      CalculatedTagTargetField.album => track.album,
      CalculatedTagTargetField.genre => track.genres.join(', '),
    };

String _durationToken(BaseTrack track) {
  final minutes = track.duration ~/ 60;
  final seconds = track.duration % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _dateAddedToken(BaseTrack track) {
  final date = track.dateAdded;
  if (date == null) return '';
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _folderNameToken(BaseTrack track) {
  final path = track.localPath;
  if (path == null) return '';
  final segments = p.split(p.dirname(path));
  return segments.isEmpty ? '' : segments.last;
}

String _fileExtensionToken(BaseTrack track) {
  final path = track.localPath;
  if (path == null) return '';
  final ext = p.extension(path);
  return ext.startsWith('.') ? ext.substring(1) : ext;
}

String? _resolveToken(BaseTrack track, String token) => switch (token) {
      'title' => track.title,
      'artist' => track.artists.join(', '),
      'album' => track.album,
      'genre' => track.genres.join(', '),
      'year' => track.year?.toString() ?? '',
      'track' => track.trackNumber?.toString() ?? '',
      'disc' => track.discNumber?.toString() ?? '',
      'bitrate' => track.bitrateKbps?.toString() ?? '',
      'duration' => _durationToken(track),
      'codec' => track.codec ?? '',
      'dateAdded' => _dateAddedToken(track),
      'folderName' => _folderNameToken(track),
      'fileExtension' => _fileExtensionToken(track),
      _ => null,
    };

/// Substitutes every `{token}` in [template] for [track] — pure, no file
/// I/O, works entirely from already-loaded [BaseTrack] data. An
/// unrecognized token resolves to an empty string; text outside
/// `{...}` (including a template with no tokens at all) passes through
/// unchanged.
String resolveCalculatedTagTemplate(BaseTrack track, String template) {
  return template.replaceAllMapped(_tokenPattern, (match) {
    final token = match.group(1)!;
    return _resolveToken(track, token) ?? '';
  });
}

/// Pure — no file I/O, the same "work from what's already loaded"
/// contract `previewFindReplace`/`LibraryCleanupAnalyzer.analyze`
/// already establish. An empty [CalculatedTagRule.template] returns no
/// matches rather than (mis)treating a blank template as "clear every
/// track's field."
List<CalculatedTagMatch> previewCalculatedTags(
  List<BaseTrack> tracks,
  CalculatedTagRule rule,
) {
  if (rule.template.isEmpty) return const [];

  final matches = <CalculatedTagMatch>[];
  for (final track in tracks) {
    final before = _writableFieldValue(track, rule.target);
    final after = resolveCalculatedTagTemplate(track, rule.template);
    if (after != before) {
      matches.add(CalculatedTagMatch(track: track, before: before, after: after));
    }
  }
  return matches;
}
