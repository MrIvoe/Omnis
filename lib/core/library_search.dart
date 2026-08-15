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
/// A bare, unquoted field value can only be one word: `album:greatest
/// hits` splits into two independent terms (`album:greatest` AND the
/// free-text `hits`), not one `"greatest hits"` phrase — in practice
/// this still finds "Greatest Hits" albums (both conditions hold), just
/// not by matching the exact phrase. Wrap a multi-word value in double
/// quotes to search it as one phrase instead:
///
/// ```text
/// album:"greatest hits"    -> one phrase, not two AND'd terms
/// artist:"guns n' roses"
/// "exact free text phrase" -> quoting works unqualified too
/// ```
///
/// An unterminated quote (`artist:"queen`) extends to the end of the
/// query rather than being treated as an error — the same forgiving
/// convention most search boxes use. An empty quoted value
/// (`artist:""`) leaves nothing after the `:`, so it falls back to
/// matching as the plain free-text word `artist:` rather than a field
/// term at all, the same as any other field-looking prefix with no
/// value.
///
/// `rating:` matches against a track's star rating (0-5, 0 meaning
/// unrated — the same convention `RatingsPlugin.ratingOf` already uses):
///
/// ```text
/// rating:4                 -> exactly 4 stars
/// rating:>=4                -> 4 stars or more
/// rating:<=2                -> 2 stars or fewer
/// rating:>3                 -> more than 3 stars
/// rating:<1                 -> unrated only (equivalent to rating:0)
/// ```
///
/// `bpm:`/`format:` read straight off `BaseTrack`'s own fields (`bpm`,
/// `codec` — populated by `AudioAnalysisPlugin`/`AudioFormatReader`
/// respectively), no caller-supplied lookup needed:
///
/// ```text
/// format:flac              -> exact codec match, case-insensitive
/// bpm:120                  -> exact BPM
/// bpm:120..140              -> inclusive range
/// bpm:>=120                 -> comparison, same operators as rating:
/// ```
///
/// `favorite:` needs a caller-supplied lookup, the same shape [ratingOf]
/// already establishes — `library_page.dart` passes `_isFavorite`
/// (backed by `FavoritesPlugin.isFavorite`):
///
/// ```text
/// favorite:true
/// favorite:false
/// ```
///
/// `bitrate:` reads straight off `BaseTrack.bitrateKbps` (populated by
/// `AudioFormatReader`, same as `format:`) — exact/range/comparison,
/// identical shape to `bpm:`:
///
/// ```text
/// bitrate:320
/// bitrate:>=1000            -> lossless-range territory
/// bitrate:128..320
/// ```
///
/// `lyrics:` needs a caller-supplied lookup — unlike [ratingOf]/
/// [favoriteOf] (keyed by track id, since `RatingsPlugin`/
/// `FavoritesPlugin` only ever need an id), [hasLyrics] takes the whole
/// [BaseTrack], matching `LyricsPlugin.hasLyrics(BaseTrack)`'s own real
/// signature exactly — `library_page.dart` passes it straight through:
///
/// ```text
/// lyrics:true
/// lyrics:false
/// ```
///
/// This function stays deliberately plugin-free — [ratingOf]/
/// [favoriteOf]/[hasLyrics] are optional lookups the *caller* supplies,
/// not a dependency this function reaches out for itself. Every
/// `rating:`/`favorite:`/`lyrics:` term matches nothing when its lookup
/// is omitted, the same "don't silently ignore a field the caller
/// didn't wire up" stance [_SearchTerm.parse] already takes for an
/// unknown field name.
///
/// Deliberately not yet supported (documented gaps, not oversights):
/// `missing:`/`duplicate:` — both need a multi-value sub-field
/// (`missing:artwork`/`missing:year`/...), a genuinely different shape
/// from every boolean/numeric/string qualifier above, and duplicate
/// detection specifically is a library-wide computation
/// (`findDuplicateTracks`-style), not a per-track lookup any of the
/// existing qualifier shapes can express.
List<BaseTrack> filterTracks(
  List<BaseTrack> tracks,
  String query, {
  int Function(String trackId)? ratingOf,
  bool Function(String trackId)? favoriteOf,
  bool Function(BaseTrack track)? hasLyrics,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return tracks;

  final terms = _tokenize(trimmed).map(_SearchTerm.parse).toList();
  return tracks
      .where((track) => terms
          .every((term) => term.matches(track, ratingOf, favoriteOf, hasLyrics)))
      .toList();
}

/// Splits [query] into terms on whitespace, the same as a plain
/// `split(RegExp(r'\s+'))` would — except a `"..."` span is kept intact
/// as one term (its quotes stripped, any whitespace inside preserved)
/// rather than being split apart, which is what lets `album:"greatest
/// hits"` reach [_SearchTerm.parse] as a single `album:greatest hits`
/// token instead of two independent terms. An unterminated quote simply
/// never closes, so everything from it to the end of the string
/// collapses into one final term — never throws, matching every other
/// "a malformed query degrades, it doesn't crash" contract in this file.
List<String> _tokenize(String query) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (final char in query.split('')) {
    if (char == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && _whitespace.hasMatch(char)) {
      if (buffer.isNotEmpty) {
        tokens.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) tokens.add(buffer.toString());
  return tokens;
}

final _whitespace = RegExp(r'\s');

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
    const known = {
      'artist',
      'album',
      'genre',
      'title',
      'mood',
      'year',
      'rating',
      'bpm',
      'format',
      'favorite',
      'bitrate',
      'lyrics',
    };
    // An unrecognized "field:" prefix (or a bare word that happens to
    // contain a colon, e.g. a time-formatted title) is treated as plain
    // free text rather than silently matching nothing.
    if (!known.contains(field)) return _SearchTerm._(null, raw);
    return _SearchTerm._(field, value);
  }

  bool matches(
    BaseTrack track,
    int Function(String trackId)? ratingOf,
    bool Function(String trackId)? favoriteOf,
    bool Function(BaseTrack track)? hasLyrics,
  ) {
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
      case 'rating':
        if (ratingOf == null) return false;
        return _matchesRating(ratingOf(track.id), value);
      case 'bpm':
        return _matchesBpm(track.bpm, value);
      case 'format':
        return _matchesFormat(track.codec, value);
      case 'favorite':
        if (favoriteOf == null) return false;
        return _matchesBoolean(favoriteOf(track.id), value);
      case 'bitrate':
        return _matchesBitrate(track.bitrateKbps, value);
      case 'lyrics':
        if (hasLyrics == null) return false;
        return _matchesBoolean(hasLyrics(track), value);
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

  static final _comparisonPattern = RegExp(r'^(>=|<=|>|<)(-?\d+)$');

  /// `rating:4` (exact), `rating:>=4`/`rating:<=2`/`rating:>3`/`rating:<1`
  /// (comparisons). An unparseable value matches nothing rather than
  /// throwing — same "a bad query finds nothing, not a crash" contract
  /// [_matchesYear] already has for a non-numeric year.
  static bool _matchesRating(int trackRating, String value) {
    final comparison = _comparisonPattern.firstMatch(value);
    if (comparison != null) {
      final op = comparison.group(1)!;
      final threshold = int.parse(comparison.group(2)!);
      return switch (op) {
        '>=' => trackRating >= threshold,
        '<=' => trackRating <= threshold,
        '>' => trackRating > threshold,
        '<' => trackRating < threshold,
        _ => false,
      };
    }
    final exact = int.tryParse(value);
    return exact != null && trackRating == exact;
  }

  static final _bpmComparisonPattern =
      RegExp(r'^(>=|<=|>|<)(-?\d+(?:\.\d+)?)$');

  /// `bpm:120` (exact), `bpm:120..140` (inclusive range, same convention
  /// [_matchesYear] uses), `bpm:>=120`/`bpm:<=140`/etc. (comparisons,
  /// same operator set [_matchesRating] uses) — a separate comparison
  /// regex from rating's since BPM is a `double`, not an `int`.
  static bool _matchesBpm(double? trackBpm, String value) {
    if (trackBpm == null) return false;
    final range = value.split('..');
    if (range.length == 2) {
      final start = double.tryParse(range[0]);
      final end = double.tryParse(range[1]);
      if (start == null || end == null) return false;
      return trackBpm >= start && trackBpm <= end;
    }
    final comparison = _bpmComparisonPattern.firstMatch(value);
    if (comparison != null) {
      final op = comparison.group(1)!;
      final threshold = double.parse(comparison.group(2)!);
      return switch (op) {
        '>=' => trackBpm >= threshold,
        '<=' => trackBpm <= threshold,
        '>' => trackBpm > threshold,
        '<' => trackBpm < threshold,
        _ => false,
      };
    }
    final exact = double.tryParse(value);
    return exact != null && trackBpm == exact;
  }

  /// `format:flac` — an exact, case-insensitive match against
  /// `BaseTrack.codec` (a short, discrete label like `"FLAC"`/`"MP3"`,
  /// not free text), unlike the substring matching every string field
  /// above uses — "format:mp3" shouldn't also match an "AAC" track just
  /// because some unrelated field happened to contain "mp3" as a
  /// substring, and codec labels are categorical, not prose.
  static bool _matchesFormat(String? codec, String value) =>
      codec != null && codec.toLowerCase() == value.toLowerCase();

  /// Shared by `favorite:`/`lyrics:` — `true`/`false` (also accepts
  /// `yes`/`no`/`1`/`0`, the same forgiving spirit [_tokenize]'s
  /// unterminated-quote handling already has). An unrecognized value
  /// matches nothing rather than throwing — same "a bad query finds
  /// nothing, not a crash" contract every other value parser in this
  /// file already has.
  static bool _matchesBoolean(bool actual, String value) {
    final v = value.toLowerCase();
    if (v == 'true' || v == 'yes' || v == '1') return actual;
    if (v == 'false' || v == 'no' || v == '0') return !actual;
    return false;
  }

  static final _bitrateComparisonPattern = RegExp(r'^(>=|<=|>|<)(-?\d+)$');

  /// `bitrate:320` (exact), `bitrate:128..320` (inclusive range),
  /// `bitrate:>=1000`/etc. (comparisons) — same shape as [_matchesRating]
  /// (both are `int`-valued), a separate pattern purely so this qualifier
  /// isn't coupled to rating's regex if the two ever need to diverge.
  static bool _matchesBitrate(int? trackBitrate, String value) {
    if (trackBitrate == null) return false;
    final range = value.split('..');
    if (range.length == 2) {
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return false;
      return trackBitrate >= start && trackBitrate <= end;
    }
    final comparison = _bitrateComparisonPattern.firstMatch(value);
    if (comparison != null) {
      final op = comparison.group(1)!;
      final threshold = int.parse(comparison.group(2)!);
      return switch (op) {
        '>=' => trackBitrate >= threshold,
        '<=' => trackBitrate <= threshold,
        '>' => trackBitrate > threshold,
        '<' => trackBitrate < threshold,
        _ => false,
      };
    }
    final exact = int.tryParse(value);
    return exact != null && trackBitrate == exact;
  }
}
