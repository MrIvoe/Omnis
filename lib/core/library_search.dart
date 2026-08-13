import 'package:omnis/core/base_track.dart';

/// Filters [tracks] against a free-text/field-qualified [query] — §6 of
/// the Omnis 2.0 product spec ("Search should be one of Omnis' killer
/// features").
///
/// Supports the spec's basic syntax:
///
/// ```text
/// queen                    -> matches title/artist/album/genre
/// artist:queen             -> matches only the artist field
/// album:greatest hits      -> matches only the album field
/// genre:rock
/// year:1990                -> exact year
/// year:1990..1999          -> inclusive range
/// ```
///
/// A query is a whitespace-separated list of terms; every term must
/// match (AND, not OR) for a track to be included — `artist:queen rock`
/// finds Queen tracks that also mention "rock" somewhere in
/// title/artist/album/genre. An empty or whitespace-only query returns
/// [tracks] unchanged, matching "no search" rather than "match nothing."
///
/// A field value can only be one word this way: `album:greatest hits`
/// splits into two independent terms (`album:greatest` AND the free-text
/// `hits`), not one `"greatest hits"` phrase — in practice this still
/// finds "Greatest Hits" albums (both conditions hold), just not by
/// matching the exact phrase. Quoted-phrase parsing (`album:"greatest
/// hits"`) is a reasonable follow-up, not part of this cut.
///
/// Deliberately not yet supported (documented gaps, not oversights):
/// `bpm:`/`format:`/`bitrate:`/`lyrics:`/`missing:`/`duplicate:` — each
/// depends on a feature or data source that doesn't exist yet (audio
/// analysis results being searchable, format/bitrate metadata, lyrics
/// text, duplicate detection). `rating:` is a related but distinct gap:
/// `RatingsPlugin` exists (added alongside this file), but this function
/// only ever sees a plain `List<BaseTrack>` with no plugin access —
/// wiring `rating:>=4` in means either the caller pre-joining ratings
/// onto the query before calling this, or this function growing a
/// plugin dependency it deliberately doesn't have today. Natural
/// follow-ups, not part of this cut.
List<BaseTrack> filterTracks(List<BaseTrack> tracks, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return tracks;

  final terms = trimmed.split(RegExp(r'\s+')).map(_SearchTerm.parse).toList();
  return tracks.where((track) => terms.every((term) => term.matches(track))).toList();
}

/// One parsed term from a search query — either `field:value` or a bare
/// free-text word/phrase-fragment.
class _SearchTerm {
  final String? field;
  final String value;

  const _SearchTerm._(this.field, this.value);

  static final _fieldPattern = RegExp(r'^([a-zA-Z]+):(.+)$');

  factory _SearchTerm.parse(String raw) {
    final match = _fieldPattern.firstMatch(raw);
    if (match == null) return _SearchTerm._(null, raw);
    final field = match.group(1)!.toLowerCase();
    final value = match.group(2)!;
    const known = {'artist', 'album', 'genre', 'title', 'mood', 'year'};
    // An unrecognized "field:" prefix (or a bare word that happens to
    // contain a colon, e.g. a time-formatted title) is treated as plain
    // free text rather than silently matching nothing.
    if (!known.contains(field)) return _SearchTerm._(null, raw);
    return _SearchTerm._(field, value);
  }

  bool matches(BaseTrack track) {
    final f = field;
    if (f == null) return _matchesFreeText(track, value);
    switch (f) {
      case 'artist':
        return _containsCi(track.artists, value);
      case 'album':
        return _contains(track.album, value);
      case 'genre':
        return _containsCi(track.genres, value);
      case 'title':
        return _contains(track.title, value);
      case 'mood':
        return _contains(track.mood ?? '', value);
      case 'year':
        return _matchesYear(track.year, value);
      default:
        return false;
    }
  }

  static bool _matchesFreeText(BaseTrack track, String needle) {
    return _contains(track.title, needle) ||
        _containsCi(track.artists, needle) ||
        _contains(track.album, needle) ||
        _containsCi(track.genres, needle);
  }

  static bool _contains(String haystack, String needle) =>
      haystack.toLowerCase().contains(needle.toLowerCase());

  static bool _containsCi(List<String> haystack, String needle) =>
      haystack.any((h) => _contains(h, needle));

  static bool _matchesYear(int? trackYear, String value) {
    if (trackYear == null) return false;
    final range = value.split('..');
    if (range.length == 2) {
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return false;
      return trackYear >= start && trackYear <= end;
    }
    final exact = int.tryParse(value);
    return exact != null && trackYear == exact;
  }
}
