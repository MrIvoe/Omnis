import 'package:omnis/core/base_track.dart';

/// A tag field a find/replace [TagFindReplaceRule] can target — scoped
/// to the fields already present on [BaseTrack] itself (title/artist/
/// album/genre), so a preview never needs a file read the way
/// composer/comment (custom tag-only fields with no `BaseTrack`
/// counterpart) would. `artist`/`genre` operate on the same joined-
/// string representation `library_page.dart`'s own tag editor already
/// uses for those multi-value fields (`artists.join(', ')`,
/// `genres.join(', ')`) — this is a rename, not a new convention.
enum TagFindReplaceField { title, artist, album, genre }

/// spec §12's "regex search/replace" gap (item 17) — a bulk pattern-
/// based rewrite across selected tracks' tags, distinct from the
/// single-track manual editor (`TagEditorDialog`) and from the
/// automatic featured-artist cleanup (`_autoTagLibrary`).
///
/// [replace] is inserted literally, even in regex mode — this
/// deliberately does not support `$1`-style capture-group back-
/// references (a real, separate feature this increment doesn't
/// attempt); [find] can still *match* using full regex syntax, the
/// replacement text itself just isn't templated.
class TagFindReplaceRule {
  final Set<TagFindReplaceField> fields;
  final String find;
  final String replace;
  final bool useRegex;
  final bool caseSensitive;

  const TagFindReplaceRule({
    required this.fields,
    required this.find,
    required this.replace,
    this.useRegex = false,
    this.caseSensitive = false,
  });
}

/// One field on one track whose value would actually change under a
/// [TagFindReplaceRule] — a no-op field (the pattern doesn't match) is
/// never included, so a preview list is exactly "what would change,"
/// not "every field that was checked."
class TagFindReplaceMatch {
  final BaseTrack track;
  final TagFindReplaceField field;
  final String before;
  final String after;

  const TagFindReplaceMatch({
    required this.track,
    required this.field,
    required this.before,
    required this.after,
  });
}

String _fieldValue(BaseTrack track, TagFindReplaceField field) =>
    switch (field) {
      TagFindReplaceField.title => track.title,
      TagFindReplaceField.artist => track.artists.join(', '),
      TagFindReplaceField.album => track.album,
      TagFindReplaceField.genre => track.genres.join(', '),
    };

/// Pure — no file I/O, works entirely from already-loaded [BaseTrack]
/// data, the same "work from what's already loaded" contract
/// `LibraryCleanupAnalyzer.analyze`/`library_search.dart`'s
/// `filterTracks` already establish. An empty [TagFindReplaceRule.find]
/// or empty [TagFindReplaceRule.fields] returns no matches rather than
/// (mis)treating a blank pattern as "match everything." An invalid
/// regex pattern (when [TagFindReplaceRule.useRegex] is set) also
/// returns no matches rather than throwing — the same "a malformed
/// query finds nothing, not a crash" contract `library_search.dart`
/// already uses for its own free-text parsing.
List<TagFindReplaceMatch> previewFindReplace(
  List<BaseTrack> tracks,
  TagFindReplaceRule rule,
) {
  if (rule.find.isEmpty || rule.fields.isEmpty) return const [];

  RegExp? pattern;
  if (rule.useRegex) {
    try {
      pattern = RegExp(rule.find, caseSensitive: rule.caseSensitive);
    } catch (_) {
      return const [];
    }
  }

  final matches = <TagFindReplaceMatch>[];
  for (final track in tracks) {
    for (final field in rule.fields) {
      final before = _fieldValue(track, field);
      if (before.isEmpty) continue;
      final after = rule.useRegex
          ? before.replaceAll(pattern!, rule.replace)
          : before.replaceAll(
              RegExp(RegExp.escape(rule.find), caseSensitive: rule.caseSensitive),
              rule.replace,
            );
      if (after != before) {
        matches.add(TagFindReplaceMatch(
          track: track,
          field: field,
          before: before,
          after: after,
        ));
      }
    }
  }
  return matches;
}
