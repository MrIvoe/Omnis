import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/plugin_api/audio_analysis_result.dart';
import 'package:omnis/core/artist_similarity.dart';
import 'package:omnis/core/artwork_candidates.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/calculated_tags.dart';
import 'package:omnis/plugin_api/enrichment_result.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_search.dart';
import 'package:omnis/core/media_scanner.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/rating_aggregation.dart';
import 'package:omnis/core/star_rating.dart';
import 'package:omnis/core/tag_find_replace.dart';
import 'package:omnis/core/track_similarity.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:omnis_plugins/lyrics_plugin.dart';
import 'package:omnis_plugins/metadata_enrichment_plugin.dart';
import 'package:omnis_plugins/ratings_plugin.dart';
import 'package:omnis_plugins/ringtone_plugin.dart';
import 'package:omnis_plugins/tag_editor_plugin.dart';
import 'package:omnis/ui/calculated_tag_dialog.dart';
import 'package:omnis/ui/library_cleanup_report_page.dart';
import 'package:omnis/ui/library_statistics_page.dart';
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:omnis/ui/tag_editor_dialog.dart';
import 'package:omnis/ui/tag_find_replace_dialog.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/artist_avatar.dart';
import 'package:omnis/ui/widgets/library_shimmer.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';
import 'package:path/path.dart' as p;

enum LibraryViewMode { songs, albums, artists, genres, folders }

class LibrarySection {
  final String title;
  final List<LibrarySection> children;
  final List<BaseTrack> tracks;

  const LibrarySection({
    required this.title,
    this.children = const [],
    this.tracks = const [],
  });

  /// Every track this section covers, including nested children's —
  /// [tracks] alone is empty for a section that only holds sub-sections
  /// (e.g. an Artists-view artist row when albums are grouped beneath
  /// it), so a caller wanting "every track under this row" (like a
  /// calculated rating average) needs the full recursive set.
  List<BaseTrack> get allTracks =>
      children.isEmpty ? tracks : children.expand((c) => c.allTracks).toList();
}

List<LibrarySection> buildLibrarySections(
  List<BaseTrack> tracks, {
  required LibraryViewMode viewMode,
  required bool showAlbums,
  bool groupArtistsByAlbumArtist = false,
}) {
  if (tracks.isEmpty) {
    return const [];
  }

  if (viewMode == LibraryViewMode.songs) {
    return [
      LibrarySection(
        title: 'All songs',
        tracks: tracks,
      ),
    ];
  }

  if (viewMode == LibraryViewMode.albums) {
    final byAlbum = <String, List<BaseTrack>>{};
    for (final track in tracks) {
      final album = track.album.isNotEmpty ? track.album : 'Unknown Album';
      byAlbum.putIfAbsent(album, () => []).add(track);
    }
    final sections = <LibrarySection>[];
    final sortedAlbums = byAlbum.keys.toList()..sort();
    for (final album in sortedAlbums) {
      sections.add(LibrarySection(title: album, tracks: byAlbum[album] ?? []));
    }
    return sections;
  }

  if (viewMode == LibraryViewMode.folders) {
    // A flat ("linear," in Musicolet's terms) folder list — one section
    // per unique parent directory, not a nested filesystem tree. Grouped
    // by the *full* directory path (so two differently-located folders
    // that happen to share a name, e.g. two albums' "Disc 1", stay
    // separate groups) but displayed by just its last segment, since a
    // full absolute path as a section title is mostly noise.
    final byFolder = <String, List<BaseTrack>>{};
    for (final track in tracks) {
      final path = track.localPath;
      final folder =
          (path != null && path.isNotEmpty) ? p.dirname(path) : '';
      byFolder.putIfAbsent(folder, () => []).add(track);
    }
    final sections = <LibrarySection>[];
    final sortedFolders = byFolder.keys.toList()..sort();
    for (final folder in sortedFolders) {
      final title = folder.isEmpty ? 'Unknown location' : p.basename(folder);
      sections.add(LibrarySection(title: title, tracks: byFolder[folder] ?? []));
    }
    return sections;
  }

  if (viewMode == LibraryViewMode.artists) {
    final byArtist = <String, List<BaseTrack>>{};
    for (final track in tracks) {
      // Off (default): each track's own listed performer, same as
      // before this setting existed. On: the album's credited artist
      // when known — the difference that actually matters is a
      // various-artists compilation, whose tracks would otherwise
      // scatter across many different per-track artist sections instead
      // of grouping under the one album artist ("Various Artists" or
      // similar).
      final artist = groupArtistsByAlbumArtist
          ? (track.albumArtist ??
              (track.artists.isNotEmpty ? track.artists.first : null) ??
              'Unknown Artist')
          : (track.artists.isNotEmpty ? track.artists.first : 'Unknown Artist');
      byArtist.putIfAbsent(artist, () => []).add(track);
    }

    final sections = <LibrarySection>[];
    final sortedArtists = byArtist.keys.toList()..sort();

    for (final artist in sortedArtists) {
      final artistTracks = byArtist[artist] ?? [];
      if (!showAlbums) {
        sections.add(LibrarySection(title: artist, tracks: artistTracks));
        continue;
      }

      final byAlbum = <String, List<BaseTrack>>{};
      for (final track in artistTracks) {
        final album = track.album.isNotEmpty ? track.album : 'Unknown Album';
        byAlbum.putIfAbsent(album, () => []).add(track);
      }

      final albumSections = <LibrarySection>[];
      final sortedAlbums = byAlbum.keys.toList()..sort();
      for (final album in sortedAlbums) {
        final albumTracks = byAlbum[album] ?? [];
        final trackSections = albumTracks
            .map((track) => LibrarySection(title: track.title, tracks: [track]))
            .toList();
        albumSections
            .add(LibrarySection(title: album, children: trackSections));
      }

      sections.add(LibrarySection(title: artist, children: albumSections));
    }

    return sections;
  }

  final byGenre = <String, List<BaseTrack>>{};
  for (final track in tracks) {
    final genres = track.genres.isNotEmpty ? track.genres : ['Unknown Genre'];
    for (final genre in genres) {
      byGenre.putIfAbsent(genre, () => []).add(track);
    }
  }

  final sections = <LibrarySection>[];
  final sortedGenres = byGenre.keys.toList()..sort();
  for (final genre in sortedGenres) {
    final genreTracks = byGenre[genre] ?? [];
    if (!showAlbums) {
      sections.add(LibrarySection(title: genre, tracks: genreTracks));
      continue;
    }

    final byAlbum = <String, List<BaseTrack>>{};
    for (final track in genreTracks) {
      final album = track.album.isNotEmpty ? track.album : 'Unknown Album';
      byAlbum.putIfAbsent(album, () => []).add(track);
    }

    final albumSections = <LibrarySection>[];
    final sortedAlbums = byAlbum.keys.toList()..sort();
    for (final album in sortedAlbums) {
      final albumTracks = byAlbum[album] ?? [];
      final trackSections = albumTracks
          .map((track) => LibrarySection(title: track.title, tracks: [track]))
          .toList();
      albumSections.add(LibrarySection(title: album, children: trackSections));
    }

    sections.add(LibrarySection(title: genre, children: albumSections));
  }

  return sections;
}

/// Groups tracks that look like duplicates — same title and same primary
/// artist, ignoring case/extra whitespace — regardless of file format or
/// path. Only groups with 2+ tracks are returned (a "group" of one isn't
/// a duplicate). Group order and within-group order both follow [tracks]'
/// own order, so results are stable given the same input.
List<List<BaseTrack>> findDuplicateTracks(List<BaseTrack> tracks) {
  String normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  final groups = <String, List<BaseTrack>>{};
  for (final track in tracks) {
    final artist = track.artists.isNotEmpty ? track.artists.first : '';
    final key = '${normalize(track.title)}|${normalize(artist)}';
    groups.putIfAbsent(key, () => []).add(track);
  }
  return groups.values.where((group) => group.length > 1).toList();
}

/// Tracks at or under [thresholdSeconds] — likely ad stingers, bumpers, or
/// other non-song audio rather than real tracks. A track with `duration
/// == 0` is deliberately excluded: on this app 0 means "duration unknown"
/// (an untagged/unmeasured local file), not "confirmed to be short" — see
/// `LibraryPage._measureDurations`, the tool that turns "unknown" into a
/// real value so this can actually find anything on a desktop-scanned
/// library.
List<BaseTrack> findShortTracks(List<BaseTrack> tracks,
    {required int thresholdSeconds}) {
  return tracks
      .where((t) => t.duration > 0 && t.duration <= thresholdSeconds)
      .toList();
}

/// Library screen — pick local audio files and play them.
class LibraryPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;

  const LibraryPage({
    super.key,
    required this.engine,
    required this.pluginManager,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<BaseTrack> _tracks = [];
  bool _loading = false;
  String? _error;
  LibraryViewMode _viewMode = LibraryViewMode.songs;
  bool _showAlbums = false;

  /// §6 of the Omnis 2.0 product spec ("Search should be one of Omnis'
  /// killer features") — see `filterTracks` for the query syntax.
  /// Deliberately filters `_tracks` at read time rather than replacing
  /// `_tracks` itself: every other piece of state here (selection,
  /// bulk-action progress, the "currently playing" stream) is keyed off
  /// track ids independent of the search box, and none of it should
  /// reset just because the user typed into it.
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<BaseTrack> get _visibleTracks => filterTracks(
        _tracks,
        _searchQuery,
        ratingOf: _ratingOf,
        favoriteOf: _isFavorite,
        hasLyrics: _lyricsPlugin?.hasLyrics,
      );

  LyricsPlugin? get _lyricsPlugin =>
      widget.pluginManager.bundled<LyricsPlugin>(onlyEnabled: true);

  /// Track ids currently selected for a bulk action (delete duplicates,
  /// delete short files, ...). Selection mode is active whenever this is
  /// non-empty.
  final Set<String> _selectedIds = {};

  // Without this the "currently playing" marker on a row was painted once
  // and never refreshed, so it kept pointing at whichever track was playing
  // when the list happened to be built.
  StreamSubscription<BaseTrack?>? _trackSub;

  /// Track ids currently being looked up via MetadataEnrichmentPlugin.
  final Set<String> _enrichingIds = {};
  bool _bulkEnrichCancelled = false;
  bool _bulkArtworkCancelled = false;

  /// Track ids currently being analyzed via AudioAnalysisPlugin.
  final Set<String> _analyzingIds = {};
  bool _bulkAnalyzeCancelled = false;

  @override
  void initState() {
    super.initState();
    _trackSub = widget.engine.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
    _loadPersistedLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _trackSub?.cancel();
    // Stops the next iteration of whichever measurement loop is running —
    // _runDurationMeasurement also checks `mounted` itself, so this is
    // belt-and-suspenders for the automatic pass specifically, which (being
    // unawaited) can otherwise keep running well after this State is gone.
    _bulkMeasureCancelled = true;
    _autoMeasureCancelled = true;
    super.dispose();
  }

  /// Load the previously-scanned library from disk so the user doesn't
  /// have to rescan (and re-grant permission) on every app launch.
  ///
  /// Deliberately does not also call `engine.setQueue(saved)` here —
  /// confirmed by live, on-device measurement that it used to (see
  /// docs/MANUAL_QA.md's performance section): every real "play" action
  /// already sets its own queue explicitly at the moment of the action
  /// (tapping a track, a mood, a section — see `_playTrack`,
  /// `_MoodsPage._playMood`, etc.), so nothing depends on the queue being
  /// pre-populated at boot. Eagerly loading the *entire* library — every
  /// track, however large — into `just_audio`'s native
  /// `ConcatenatingAudioSource` before the user has asked to play
  /// anything was measured taking upwards of 40 seconds for a
  /// few-thousand-track library, and left the native player working
  /// through it in the background for many seconds afterward, degrading
  /// UI responsiveness (including plain bottom-nav tab switches) well
  /// past that. Matches the same "a data operation must not touch
  /// playback" principle `_pickAndAdd`'s own doc comment already
  /// established for library scans.
  Future<void> _loadPersistedLibrary() async {
    final saved = await LibraryRepository.instance.load();
    if (!mounted) return;
    setState(() => _tracks = saved);
  }

  Future<void> _pickAndAdd() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = AppSettings.instance;
      if (settings.librarySource == LibrarySource.none) {
        setState(() => _error = 'Library scanning is disabled in Settings.');
        return;
      }

      // Scan fast using the platform-optimized scanner.
      // On Android this queries the OS MediaStore (pre-indexed, instant).
      // On the filesystem-walk path (desktop/iOS), passing the
      // already-known tracks lets the scanner skip re-reading tags for
      // files that haven't changed since the last scan — see
      // MediaScanner.scanLibrary's doc comment. A scan can still take a
      // while on a large, mostly-new library — long enough that the user
      // may well have navigated away before it resolves, so every
      // setState below has to check mounted first.
      final scanned =
          await MediaScanner.instance.scanLibrary(knownTracks: _tracks);
      if (!mounted) return;
      if (scanned.isEmpty) {
        setState(() =>
            _error = 'No audio files found. Try picking a folder in Settings.');
        return;
      }
      // Dedupe by id: scanned may re-report tracks already in _tracks
      // (the whole point of the incremental scan is that it still finds
      // them, just without re-parsing their tags) — without this,
      // pressing "Add audio files" a second time duplicated every track
      // already known.
      final existingIds = _tracks.map((t) => t.id).toSet();
      final newTracks = scanned
          .where((t) => !existingIds.contains(t.id))
          // The scanner only ever supplies dateAdded from real MediaStore
          // data (Android) — on the filesystem-walk path it's left null,
          // so a genuinely new track gets "now" as the best available
          // signal of when the user actually added it.
          .map((t) => t.dateAdded == null
              ? t.copyWith(dateAdded: DateTime.now())
              : t)
          .toList();
      // A previously-known local track whose file no longer exists on
      // disk shouldn't stay in the library forever — scoped to this
      // explicit rescan action (not run automatically on every app open)
      // so pruning stays predictable and bounded.
      final stillPresent = _tracks.where((t) {
        if (t.type != TrackType.local || t.localPath == null) return true;
        return File(t.localPath!).existsSync();
      }).toList();
      setState(() => _tracks = [...stillPresent, ...newTracks]);
      // Persist so the library survives app restarts. Deliberately does
      // NOT touch the playback queue or start playback — scanning/adding
      // to the library is a data operation, not a "play something"
      // action, and previously did both: every scan silently replaced
      // whatever queue was playing and started a random track.
      await LibraryRepository.instance.save(_tracks);
      // Silent, low-priority, unawaited — see _autoMeasureDurationsAfterScan's
      // doc comment. Must not block this method (or the "loading" spinner
      // it drives) on opening potentially hundreds of files.
      unawaited(_autoMeasureDurationsAfterScan());
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load audio files: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playTrack(BaseTrack track) async {
    final index = _tracks.indexWhere((candidate) => candidate.id == track.id);
    if (index < 0) return;
    await widget.engine.setQueue(_tracks, startIndex: index);
    await widget.engine.playAt(index);
  }

  /// §7's "play next" — inserts right after whatever's currently
  /// playing, distinct from [_addToQueue]'s "append to the end."
  Future<void> _playNext(BaseTrack track) async {
    await widget.engine.playNext(track);
    _toast('Playing "${track.title}" next');
  }

  Future<void> _addToQueue(BaseTrack track) async {
    await widget.engine.addTrack(track);
    _toast('Added "${track.title}" to queue');
  }

  /// Item 40/§39's "Similar Track" recommendation — real BPM/key/mood/
  /// genre distance via [findSimilarTracks], not a placeholder. A track
  /// with no comparable analysis/enrichment data yet yields an empty
  /// result, so this tells the user to run "Analyze audio"/"Look up
  /// metadata" first rather than silently queueing an arbitrary shuffle.
  Future<void> _playSimilar(BaseTrack track) async {
    final similar = findSimilarTracks(track, _tracks);
    if (similar.isEmpty) {
      _toast('Not enough BPM/key/mood/genre data yet for "${track.title}" — '
          'try "Analyze audio" or "Look up metadata" first.');
      return;
    }
    final queue = [track, ...similar];
    await widget.engine.setQueue(queue, startIndex: 0);
    await widget.engine.playAt(0);
  }

  /// Item 39's still-missing "Similar Artist" recommendation, the
  /// artist-level sibling of [_playSimilar] — real genre/mood/BPM
  /// distance via [findSimilarArtists], not a placeholder. Groups
  /// [_tracks] by artist the exact same way `buildLibrarySections`'s
  /// own Artists-view grouping does (respecting
  /// `groupArtistsByAlbumArtist`), so "the artist" this looks up
  /// matches whatever's actually shown as one row in that view. An
  /// artist with no comparable analysis/enrichment data across their
  /// tracks yields an empty result, same "tell the user why, don't
  /// silently queue an arbitrary shuffle" stance [_playSimilar] already
  /// takes.
  Future<void> _showSimilarArtists(String artist) async {
    final groupByAlbumArtist = AppSettings.instance.groupArtistsByAlbumArtist;
    final byArtist = <String, List<BaseTrack>>{};
    for (final track in _tracks) {
      final trackArtist = groupByAlbumArtist
          ? (track.albumArtist ??
              (track.artists.isNotEmpty ? track.artists.first : null) ??
              'Unknown Artist')
          : (track.artists.isNotEmpty ? track.artists.first : 'Unknown Artist');
      byArtist.putIfAbsent(trackArtist, () => []).add(track);
    }

    final similar = findSimilarArtists(artist, byArtist);
    if (similar.isEmpty) {
      _toast('Not enough genre/mood/BPM data yet for "$artist" — try '
          '"Analyze audio" or "Look up metadata" on their tracks first.');
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Similar to $artist'),
        children: [
          for (final name in similar)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final tracks = byArtist[selected];
    if (tracks == null || tracks.isEmpty) return;
    await widget.engine.setQueue(tracks);
    await widget.engine.play();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Merge an [EnrichmentResult] into the stored track: fills in a missing
  /// album/year rather than overwriting a value that's already there, and
  /// merges genres/mood additively since those start empty for every
  /// locally scanned track. Deliberately never touches title/artist — a
  /// single top search match is not reliable enough to silently overwrite
  /// what the file itself (or the user) already says.
  void _applyEnrichment(BaseTrack original, EnrichmentResult result) {
    final index = _tracks.indexWhere((t) => t.id == original.id);
    if (index < 0) return;
    final current = _tracks[index];
    final updated = current.copyWith(
      album: (current.album.isEmpty || current.album == 'Unknown Album')
          ? result.canonicalAlbum
          : null,
      year: current.year ?? result.year,
      genres: {...current.genres, ...result.genres}.toList(),
      mood: current.mood ?? result.mood,
      albumArtist: current.albumArtist ?? result.albumArtist,
      releaseType: current.releaseType ?? result.releaseType,
      releaseDate: current.releaseDate ?? result.releaseDate,
    );
    if (mounted) {
      setState(() => _tracks[index] = updated);
    } else {
      _tracks[index] = updated;
    }
  }

  /// Looked up by interface for the actual "enrich this track" capability
  /// — whatever's currently registered as `IMetadataProvider` (today,
  /// always `MetadataEnrichmentPlugin`).
  IMetadataProvider? get _metadataProvider =>
      widget.pluginManager.services.get<IMetadataProvider>();

  /// Looked up by interface, not concrete plugin type — see
  /// `_metadataProvider`. `null` when the Artist Photos plugin is disabled
  /// or not registered; every artist row just falls back to the generic
  /// person icon in that case (see `ArtistAvatar`).
  IArtistImageProvider? get _artistImageProvider =>
      widget.pluginManager.services.get<IArtistImageProvider>();

  /// `hasAnyCredential` is a detail specific to this particular provider's
  /// credential model (a Last.fm key, a Discogs token) — a hypothetical
  /// future provider wouldn't necessarily have the same concept, so it
  /// isn't part of `IMetadataProvider`. Only the UI hint below needs the
  /// concrete type.
  MetadataEnrichmentPlugin? get _enrichmentPlugin =>
      widget.pluginManager.bundled<MetadataEnrichmentPlugin>(onlyEnabled: true);

  Future<void> _enrichSingle(BaseTrack track) async {
    final provider = _metadataProvider;
    if (provider == null) {
      _toast('The Metadata Enrichment plugin is disabled in Settings.');
      return;
    }
    if (_enrichmentPlugin?.hasAnyCredential == false) {
      _toast('Looking up MusicBrainz only — add a Last.fm key or Discogs '
          'token in Settings for genre/mood tags too.');
    }
    setState(() => _enrichingIds.add(track.id));
    try {
      final result = await provider.enrich(track);
      if (result.isEmpty) {
        _toast('No metadata found for "${track.title}".');
        return;
      }
      _applyEnrichment(track, result);
      await LibraryRepository.instance.save(_tracks);
      _toast('Updated "${track.title}" from ${result.sourcesUsed.join(', ')}.');
    } finally {
      if (mounted) setState(() => _enrichingIds.remove(track.id));
    }
  }

  /// Looks up [track]'s cover art online via `MetadataEnrichmentPlugin
  /// .lookupArtwork` (MusicBrainz → Cover Art Archive, item 12/spec §47)
  /// and embeds it through the same `TagEditorPlugin.writeTags` call the
  /// manual "pick an image" flow (`TagEditorDialog._pickArtwork`) already
  /// uses — this is genuinely the same "write artwork bytes to the file"
  /// operation, just sourced online instead of from a file picker.
  Future<void> _lookupArtworkOnline(BaseTrack track) async {
    final enrichment = _enrichmentPlugin;
    if (enrichment == null) {
      _toast('The Metadata Enrichment plugin is disabled in Settings.');
      return;
    }
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    final path = track.localPath;
    if (path == null) {
      _toast('"${track.title}" has no local file to update.');
      return;
    }
    setState(() => _enrichingIds.add(track.id));
    try {
      final artwork = await enrichment.lookupArtwork(track);
      if (artwork == null) {
        _toast('No artwork found online for "${track.title}".');
        return;
      }
      final ok = await tagEditor.writeTags(path, artworkBytes: artwork);
      if (!ok) {
        _toast('Could not write artwork to "${track.title}".');
        return;
      }
      ArtworkProvider.invalidate(track.id);
      if (mounted) setState(() {});
      _toast('Updated artwork for "${track.title}".');
    } finally {
      if (mounted) setState(() => _enrichingIds.remove(track.id));
    }
  }

  /// Looks up every track sequentially, respecting MusicBrainz's ~1
  /// request/second rate limit between calls. Shows live progress and can
  /// be cancelled mid-run; whatever was already updated is kept.
  Future<void> _enrichAll() async {
    final provider = _metadataProvider;
    if (provider == null) {
      _toast('The Metadata Enrichment plugin is disabled in Settings.');
      return;
    }
    if (_tracks.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enrich entire library?'),
        content: Text(
          'Looks up ${_tracks.length} tracks one at a time — MusicBrainz '
          'rate-limits to about one request per second, so this takes '
          'roughly ${_tracks.length} seconds. You can cancel partway '
          'through; anything already updated is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _bulkEnrichCancelled = false;
    final total = _tracks.length;
    final doneNotifier = ValueNotifier<int>(0);
    final changedNotifier = ValueNotifier<int>(0);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enriching library…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => ValueListenableBuilder<int>(
                valueListenable: changedNotifier,
                builder: (context, changed, __) =>
                    Text('$done / $total tracks checked · $changed updated'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _bulkEnrichCancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    var done = 0;
    var changed = 0;
    // try/catch/finally so a thrown exception anywhere in the loop (a
    // misbehaving IMetadataProvider — a downloaded plugin, not
    // necessarily the bundled one — or a save failure) can't strand this
    // dialog on screen forever: it's barrierDismissible: false, so
    // without this the only way out would be force-closing the app.
    var failed = false;
    try {
      for (final track in List<BaseTrack>.from(_tracks)) {
        if (_bulkEnrichCancelled || !mounted) break;
        final result = await provider.enrich(track);
        if (!result.isEmpty) {
          _applyEnrichment(track, result);
          changed++;
          changedNotifier.value = changed;
        }
        done++;
        doneNotifier.value = done;
        if (done < total && !_bulkEnrichCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
      }
      await LibraryRepository.instance.save(_tracks);
    } catch (e) {
      failed = true;
      debugPrint('Omnis: bulk enrichment stopped early: $e');
    } finally {
      doneNotifier.dispose();
      changedNotifier.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _toast(failed
            ? 'Enrichment stopped after an error — $changed of $done tracks '
                'were updated before it happened.'
            : 'Enrichment finished: $changed of $done tracks updated.');
      }
    }
  }

  /// Item 12/spec §47's "no bulk 'look up artwork for the whole library'
  /// action" gap — deliberately scoped narrower than [_enrichAll]'s
  /// batch flow (which covers title/artist/album/genre): this one only
  /// ever targets [tracksNeedingArtwork], the local tracks that still
  /// have no [BaseTrack.coverArt] at all, and reuses the exact
  /// `MetadataEnrichmentPlugin.lookupArtwork` → `TagEditorPlugin
  /// .writeTags` → `ArtworkProvider.invalidate` sequence
  /// [_lookupArtworkOnline] already established for a single track — a
  /// real but separate follow-on, not a duplicate of [_enrichAll].
  /// Same rate-limit/progress/cancel/try-finally shape as [_enrichAll]
  /// throughout, since it's making the same kind of MusicBrainz-backed
  /// per-track network call.
  Future<void> _lookupArtworkForAll() async {
    final enrichment = _enrichmentPlugin;
    if (enrichment == null) {
      _toast('The Metadata Enrichment plugin is disabled in Settings.');
      return;
    }
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    final candidates = tracksNeedingArtwork(_tracks);
    if (candidates.isEmpty) {
      _toast('Every local track already has artwork.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Look up artwork for the whole library?'),
        content: Text(
          'Looks up ${candidates.length} track${candidates.length == 1 ? '' : 's'} '
          'missing artwork, one at a time — MusicBrainz rate-limits to '
          'about one request per second, so this takes roughly '
          '${candidates.length} seconds. You can cancel partway through; '
          'anything already updated is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _bulkArtworkCancelled = false;
    final total = candidates.length;
    final doneNotifier = ValueNotifier<int>(0);
    final changedNotifier = ValueNotifier<int>(0);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Looking up artwork…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => ValueListenableBuilder<int>(
                valueListenable: changedNotifier,
                builder: (context, changed, __) =>
                    Text('$done / $total tracks checked · $changed updated'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _bulkArtworkCancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    var done = 0;
    var changed = 0;
    // Same try/catch/finally shape as [_enrichAll], and for the same
    // reason: this dialog is barrierDismissible: false, so an
    // uncaught exception anywhere in the loop would otherwise strand it
    // on screen with no way out short of force-closing the app.
    var failed = false;
    try {
      for (final track in candidates) {
        if (_bulkArtworkCancelled || !mounted) break;
        final path = track.localPath;
        if (path != null) {
          final artwork = await enrichment.lookupArtwork(track);
          if (artwork != null) {
            final ok = await tagEditor.writeTags(path, artworkBytes: artwork);
            if (ok) {
              ArtworkProvider.invalidate(track.id);
              changed++;
              changedNotifier.value = changed;
            }
          }
        }
        done++;
        doneNotifier.value = done;
        if (done < total && !_bulkArtworkCancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
      }
    } catch (e) {
      failed = true;
      debugPrint('Omnis: bulk artwork lookup stopped early: $e');
    } finally {
      doneNotifier.dispose();
      changedNotifier.dispose();
      if (mounted) {
        setState(() {});
        Navigator.of(context, rootNavigator: false).pop();
        _toast(failed
            ? 'Artwork lookup stopped after an error — $changed of $done '
                'tracks were updated before it happened.'
            : 'Artwork lookup finished: $changed of $done tracks updated.');
      }
    }
  }

  /// Looked up by interface — whatever's currently registered as
  /// `IAudioAnalysisProvider` (today, always `AudioAnalysisPlugin`).
  IAudioAnalysisProvider? get _analysisProvider =>
      widget.pluginManager.services.get<IAudioAnalysisProvider>();

  /// Merge an [AudioAnalysisResult] into the stored track: fills in
  /// missing bpm/key only, merges mood/genres additively — same
  /// conservative policy as [_applyEnrichment], and for the same reason:
  /// a single automated pass shouldn't overwrite data that's already
  /// there, whether it came from the file's own tags or a user edit.
  void _applyAnalysis(BaseTrack original, AudioAnalysisResult result) {
    final index = _tracks.indexWhere((t) => t.id == original.id);
    if (index < 0) return;
    final current = _tracks[index];
    final updated = current.copyWith(
      bpm: current.bpm ?? result.bpm,
      key: current.key ?? result.formattedKey,
      mood: current.mood ?? result.mood,
      genres: {...current.genres, ...result.genres}.toList(),
    );
    if (mounted) {
      setState(() => _tracks[index] = updated);
    } else {
      _tracks[index] = updated;
    }
  }

  /// Writes [track]'s current (already-merged) bpm/key/mood/genres into
  /// the actual file's ID3 tags via [TagEditorPlugin] — deliberately the
  /// track *after* [_applyAnalysis]'s merge, not the raw
  /// [AudioAnalysisResult], so a value [_applyAnalysis] chose to leave
  /// alone (because the file already had one) never gets clobbered here
  /// either. Without this, "analyze" only ever updated Omnis's own
  /// library JSON — the tags never actually made it into the song file,
  /// so they wouldn't survive a rescan or show up in any other player.
  /// Silent on failure (no tag editor plugin, no local file, or the
  /// write itself fails): the values are already safely in Omnis's own
  /// library regardless, so this is strictly an additional
  /// make-it-portable step, never the thing a user is blocked on.
  Future<void> _writeAnalysisTagsToFile(BaseTrack track) async {
    final tagEditor = _tagEditorPlugin;
    final path = track.localPath;
    if (tagEditor == null || path == null) return;
    await tagEditor.writeTags(
      path,
      bpm: track.bpm?.round().toString(),
      initialKey: track.key,
      mood: track.mood,
      genre: track.genres.isEmpty ? null : track.genres.join(', '),
    );
  }

  Future<void> _analyzeSingle(BaseTrack track) async {
    final provider = _analysisProvider;
    if (provider == null) {
      _toast('The Audio Analysis plugin is disabled in Settings.');
      return;
    }
    if (!provider.isAvailable) {
      _toast('Set an Essentia service URL in Settings first — see '
          'tools/essentia_service/ to deploy one.');
      return;
    }
    if (track.localPath == null) {
      _toast('"${track.title}" has no local file to analyze.');
      return;
    }
    setState(() => _analyzingIds.add(track.id));
    try {
      final result = await provider.analyze(track);
      if (result.isEmpty) {
        _toast('No analysis result for "${track.title}" — check the '
            'service is reachable.');
        return;
      }
      _applyAnalysis(track, result);
      await LibraryRepository.instance.save(_tracks);
      final merged = _tracks.firstWhere((t) => t.id == track.id,
          orElse: () => track);
      await _writeAnalysisTagsToFile(merged);
      _toast('Analyzed "${track.title}".');
    } finally {
      if (mounted) setState(() => _analyzingIds.remove(track.id));
    }
  }

  /// Analyzes every local track sequentially. Unlike enrichment there's no
  /// fixed external rate limit — the pace here is really "how fast is
  /// your own Essentia service," so this waits for each response rather
  /// than adding an artificial delay.
  Future<void> _analyzeAll() async {
    final provider = _analysisProvider;
    if (provider == null) {
      _toast('The Audio Analysis plugin is disabled in Settings.');
      return;
    }
    if (!provider.isAvailable) {
      _toast('Set an Essentia service URL in Settings first — see '
          'tools/essentia_service/ to deploy one.');
      return;
    }
    final local = _tracks.where((t) => t.localPath != null).toList();
    if (local.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analyze entire library?'),
        content: Text(
          'Sends ${local.length} local track${local.length == 1 ? '' : 's'} '
          'to your Essentia service one at a time. This can take a while '
          'depending on that service\'s speed. You can cancel partway '
          'through; anything already updated is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _bulkAnalyzeCancelled = false;
    final total = local.length;
    final doneNotifier = ValueNotifier<int>(0);
    final changedNotifier = ValueNotifier<int>(0);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Analyzing library…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => ValueListenableBuilder<int>(
                valueListenable: changedNotifier,
                builder: (context, changed, __) =>
                    Text('$done / $total tracks checked · $changed updated'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _bulkAnalyzeCancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    var done = 0;
    var changed = 0;
    // Same try/catch/finally rationale as _enrichAll: this dialog is
    // barrierDismissible: false, so an uncaught exception anywhere in
    // here (a misbehaving IAudioAnalysisProvider, a tag-write failure, a
    // save failure) would otherwise strand it on screen forever.
    var failed = false;
    try {
      for (final track in local) {
        if (_bulkAnalyzeCancelled || !mounted) break;
        final result = await provider.analyze(track);
        if (!result.isEmpty) {
          _applyAnalysis(track, result);
          final merged = _tracks.firstWhere((t) => t.id == track.id,
              orElse: () => track);
          await _writeAnalysisTagsToFile(merged);
          changed++;
          changedNotifier.value = changed;
        }
        done++;
        doneNotifier.value = done;
      }
      await LibraryRepository.instance.save(_tracks);
    } catch (e) {
      failed = true;
      debugPrint('Omnis: bulk analysis stopped early: $e');
    } finally {
      doneNotifier.dispose();
      changedNotifier.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _toast(failed
            ? 'Analysis stopped after an error — $changed of $done tracks '
                'were updated before it happened.'
            : 'Analysis finished: $changed of $done tracks updated.');
      }
    }
  }

  // --- Duration measurement (unblocks short-track cleanup) ---
  //
  // Desktop scans never had a way to know a track's real length — ID3
  // tags don't reliably carry one — so every desktop-scanned track sat at
  // duration 0 forever. That silently defeated "short tracks" cleanup on
  // desktop: 0 is treated as "unknown," not "confirmed short" (see
  // findShortTracks), so nothing was ever found. This measures the real
  // duration for whatever's still unknown by actually opening each file —
  // too slow to do inline during a bulk scan (see MediaScanner's own doc
  // on why it doesn't) — so every scan that adds new local tracks kicks
  // off _autoMeasureDurationsAfterScan() as a silent, unawaited background
  // pass afterward (see _pickAndAdd), instead of requiring the user to
  // find this manual action themselves. The manual "Measure durations"
  // menu item still exists for a deliberate re-run (e.g. after cancelling
  // an earlier pass) and shares the same underlying loop.
  bool _bulkMeasureCancelled = false;
  bool _autoMeasureCancelled = false;

  /// Whether a duration-measurement pass (manual or automatic) is already
  /// running — guards against two passes opening `AudioPlayer` on the same
  /// file concurrently and racing on `_tracks`/the persisted library if,
  /// say, the user taps "Measure durations" while the post-scan automatic
  /// pass is still going.
  bool _measurementInProgress = false;

  Future<int> _probeDurationSeconds(String path) async {
    final player = AudioPlayer();
    try {
      final duration =
          await player.setFilePath(path).timeout(const Duration(seconds: 8));
      return duration?.inSeconds ?? 0;
    } catch (_) {
      return 0;
    } finally {
      unawaited(player.dispose());
    }
  }

  /// Measures [candidates] one at a time via [_probeDurationSeconds],
  /// updating `_tracks` and calling [onProgress] after each, then persists
  /// once at the end. Shared by the manual dialog-driven flow and the
  /// silent automatic post-scan pass — [isCancelled] is checked before
  /// every file so either caller can stop it early.
  Future<int> _runDurationMeasurement(
    List<BaseTrack> candidates, {
    required bool Function() isCancelled,
    void Function(int done)? onProgress,
  }) async {
    var done = 0;
    for (final track in candidates) {
      if (isCancelled() || !mounted) break;
      final seconds = await _probeDurationSeconds(track.localPath!);
      if (seconds > 0) {
        final index = _tracks.indexWhere((t) => t.id == track.id);
        if (index >= 0) {
          final updated = _tracks[index].copyWith(duration: seconds);
          if (mounted) {
            setState(() => _tracks[index] = updated);
          } else {
            _tracks[index] = updated;
          }
        }
      }
      done++;
      onProgress?.call(done);
    }
    await LibraryRepository.instance.save(_tracks);
    return done;
  }

  /// Kicked off unawaited right after a scan persists new tracks (see
  /// _pickAndAdd) — turns "duration unknown" into a real value for
  /// whatever the scan couldn't get one for, with no dialog and nothing
  /// for the user to discover or trigger themselves. Silently does
  /// nothing if a measurement pass is already running or there's nothing
  /// left to measure.
  Future<void> _autoMeasureDurationsAfterScan() async {
    if (_measurementInProgress) return;
    final unmeasured =
        _tracks.where((t) => t.duration <= 0 && t.localPath != null).toList();
    if (unmeasured.isEmpty) return;

    _measurementInProgress = true;
    _autoMeasureCancelled = false;
    try {
      await _runDurationMeasurement(unmeasured,
          isCancelled: () => _autoMeasureCancelled || !mounted);
    } finally {
      _measurementInProgress = false;
    }
  }

  Future<void> _measureDurations() async {
    if (_measurementInProgress) {
      _toast('Already measuring durations in the background — hang on.');
      return;
    }
    final unmeasured =
        _tracks.where((t) => t.duration <= 0 && t.localPath != null).toList();
    if (unmeasured.isEmpty) {
      _toast('Every track already has a known duration.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Measure durations?'),
        content: Text(
          'Opens ${unmeasured.length} file${unmeasured.length == 1 ? '' : 's'} '
          'to read its real length — needed for "short tracks" cleanup to '
          'find anything. You can cancel partway through.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _bulkMeasureCancelled = false;
    _measurementInProgress = true;
    final total = unmeasured.length;
    final doneNotifier = ValueNotifier<int>(0);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Measuring durations…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => Text('$done / $total measured'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _bulkMeasureCancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    // try/finally so a thrown exception in here (e.g. a LibraryRepository
    // listener elsewhere in the app throwing during notifyListeners(),
    // which propagates straight through save()) can't leave
    // _measurementInProgress stuck true forever — that would silently
    // disable "Measure durations" (and the post-scan automatic pass) for
    // the rest of the session, on top of stranding this
    // barrierDismissible: false dialog.
    var done = 0;
    try {
      done = await _runDurationMeasurement(unmeasured,
          isCancelled: () => _bulkMeasureCancelled,
          onProgress: (n) => doneNotifier.value = n);
    } finally {
      _measurementInProgress = false;
      doneNotifier.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _toast('Measured $done of $total tracks.');
      }
    }
  }

  // --- Duplicate / short-track cleanup + multi-select ---

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelected(String trackId) {
    setState(() {
      if (!_selectedIds.remove(trackId)) {
        _selectedIds.add(trackId);
      }
    });
  }

  /// Toggles every track in a group together — used by grid tiles, where
  /// one tile already represents a collapsed group of tracks rather than
  /// one file. All-selected toggles off; anything else toggles everything
  /// on, so one tap always has an unambiguous, visible effect.
  void _toggleSelectedGroup(List<BaseTrack> tracks) {
    final allSelected = tracks.every((t) => _selectedIds.contains(t.id));
    setState(() {
      for (final t in tracks) {
        if (allSelected) {
          _selectedIds.remove(t.id);
        } else {
          _selectedIds.add(t.id);
        }
      }
    });
  }

  Future<bool> _confirmPermanentDelete(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete these files?'),
        content: Text(
          'This permanently deletes $count file${count == 1 ? '' : 's'} '
          'from your device and removes them from the library. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Deletes [ids] from disk (where a local file exists) and from the
  /// library, persists, and keeps the playback queue in sync. A failed
  /// disk delete for one file (permissions, already gone, ...) doesn't
  /// stop the rest — it's logged and that track is still dropped from the
  /// library so it doesn't keep cluttering cleanup results.
  Future<void> _deleteTracks(Set<String> ids) async {
    if (ids.isEmpty) return;
    final toDelete = _tracks.where((t) => ids.contains(t.id)).toList();
    // Deleting many files from disk can take a while — long enough that
    // the user may have navigated away before this loop finishes, so
    // every UI touch below has to check mounted first.
    for (final track in toDelete) {
      final path = track.localPath;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Omnis: failed to delete "$path": $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _tracks.removeWhere((t) => ids.contains(t.id));
      _selectedIds.removeAll(ids);
    });
    await LibraryRepository.instance.save(_tracks);
    await widget.engine.setQueue(_tracks);
    if (mounted) {
      _toast('Deleted ${toDelete.length} track${toDelete.length == 1 ? '' : 's'}.');
    }
  }

  Future<void> _deleteSelected() async {
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    if (!await _confirmPermanentDelete(ids.length)) return;
    if (!mounted) return;
    await _deleteTracks(ids);
  }

  Future<void> _openCleanupTool() async {
    final duplicates = findDuplicateTracks(_tracks);
    final shortTracks = findShortTracks(
      _tracks,
      thresholdSeconds: AppSettings.instance.shortTrackThresholdSeconds,
    );
    if (duplicates.isEmpty && shortTracks.isEmpty) {
      _toast('No duplicates or short tracks found.');
      return;
    }
    final toDelete = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CleanupSheet(
        duplicateGroups: duplicates,
        shortTracks: shortTracks,
      ),
    );
    if (toDelete == null || toDelete.isEmpty || !mounted) return;
    if (!await _confirmPermanentDelete(toDelete.length)) return;
    if (!mounted) return;
    await _deleteTracks(toDelete);
  }

  /// Opens spec §20's "Music Library Cleanup" report — a broader,
  /// read-first analysis than [_openCleanupTool]'s duplicates/short-
  /// tracks-only sheet, covering missing artwork, inconsistent artist/
  /// genre spellings, albums missing a year, malformed track numbers,
  /// duplicate albums, and (heuristically) corrupt files too.
  Future<void> _openCleanupReport() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => LibraryCleanupReportPage(
        tracks: _tracks,
        onEditTags: _editTags,
        onRemoveFromLibrary: _removeFromLibrary,
      ),
    ));
  }

  /// Spec §35's "Library Statistics" dashboard — a point-in-time
  /// snapshot over the already-loaded [_tracks], the same "no new I/O"
  /// contract [_openCleanupReport] already establishes.
  Future<void> _openStatistics() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => LibraryStatisticsPage(tracks: _tracks),
    ));
  }

  /// Drops [track] from the library without attempting to delete
  /// anything from disk — unlike [_deleteTracks], which is for a file
  /// that still exists. Used by the cleanup report's "missing files"
  /// category, where the file is already gone; there's nothing left to
  /// delete, just a now-dangling library entry to remove.
  Future<void> _removeFromLibrary(BaseTrack track) async {
    if (!mounted) return;
    setState(() {
      _tracks.removeWhere((t) => t.id == track.id);
      _selectedIds.remove(track.id);
    });
    await LibraryRepository.instance.save(_tracks);
    await widget.engine.setQueue(_tracks);
    _toast('Removed "${track.title}" from your library.');
  }

  // --- Favorites + playlists ---

  FavoritesPlugin? get _favoritesPlugin =>
      widget.pluginManager.bundled<FavoritesPlugin>(onlyEnabled: true);

  TagEditorPlugin? get _tagEditorPlugin =>
      widget.pluginManager.bundled<TagEditorPlugin>(onlyEnabled: true);

  RingtonePlugin? get _ringtonePlugin =>
      widget.pluginManager.bundled<RingtonePlugin>(onlyEnabled: true);

  Future<void> _setAsRingtone(BaseTrack track) async {
    final plugin = _ringtonePlugin;
    if (plugin == null) {
      _toast('The Ringtone plugin is disabled in Settings.');
      return;
    }
    final ok = await plugin.setAsRingtone(track);
    _toast(ok
        ? 'Set "${track.title}" as your ringtone.'
        : plugin.lastError ?? 'Could not set ringtone.');
  }

  bool _isFavorite(String trackId) =>
      _favoritesPlugin?.isFavorite(trackId) ?? false;

  Future<void> _toggleFavorite(String trackId) async {
    final plugin = _favoritesPlugin;
    if (plugin == null) {
      _toast('The Favorites plugin is disabled in Settings.');
      return;
    }
    OmnisHaptics.selectionClick();
    await plugin.toggleFavorite(trackId);
    if (mounted) setState(() {});
  }

  RatingsPlugin? get _ratingsPlugin =>
      widget.pluginManager.bundled<RatingsPlugin>(onlyEnabled: true);

  int _ratingOf(String trackId) => _ratingsPlugin?.ratingOf(trackId) ?? 0;

  /// [RatingsPlugin] also implements [IThumbsProvider] — same plugin
  /// instance, an independent signal from the star rating above (§36:
  /// a coarse "yes/no" preference some listeners prefer over picking a
  /// specific star count).
  ThumbState _thumbOf(String trackId) =>
      _ratingsPlugin?.thumbOf(trackId) ?? ThumbState.none;

  /// Toggles [track]'s thumb state: tapping the currently-active thumb
  /// clears it, tapping the other one switches to it — the same
  /// one-tap-no-confirm UX [_toggleFavorite] already uses.
  Future<void> _setThumb(BaseTrack track, ThumbState state) async {
    final plugin = _ratingsPlugin;
    if (plugin == null) {
      _toast('The Ratings plugin is disabled in Settings.');
      return;
    }
    OmnisHaptics.selectionClick();
    final next = _thumbOf(track.id) == state ? ThumbState.none : state;
    await plugin.setThumb(track.id, next);
    if (mounted) setState(() {});
  }

  /// Opens a 5-star picker for [track] — tapping a star immediately sets
  /// that rating and closes, tapping the already-selected star (or the
  /// explicit clear button, when rated) clears it. One tap, no separate
  /// "confirm" step, matching how the rest of this page's quick actions
  /// (favorite toggle, playlist add) already work.
  Future<void> _rateTrack(BaseTrack track) async {
    final plugin = _ratingsPlugin;
    if (plugin == null) {
      _toast('The Ratings plugin is disabled in Settings.');
      return;
    }
    final selected = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate "${track.title}"'),
        content: _StarPicker(initialRating: plugin.preciseRatingOf(track.id)),
      ),
    );
    if (selected == null || !mounted) return;
    await plugin.setPreciseRating(track.id, selected);
    if (mounted) setState(() {});
  }

  /// Rates every currently selected track — item 9's "no bulk 'rate
  /// selected' action" gap: a specific 1-5 value doesn't fit the
  /// one-tap bulk-toggle pattern [Icons.favorite_border]'s handler
  /// above uses, so this opens the same [_StarPicker] [_rateTrack] uses
  /// for a single track first, then applies whichever star was tapped
  /// to the whole selection. Starts at 0 (no single "current" rating
  /// makes sense across a mixed-rating selection), so the picker's own
  /// "Clear rating" option — which only appears once something is
  /// already rated — never shows here; clearing a whole selection's
  /// ratings is a distinct action this doesn't attempt.
  Future<void> _bulkRate() async {
    final plugin = _ratingsPlugin;
    if (plugin == null) {
      _toast('The Ratings plugin is disabled in Settings.');
      return;
    }
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    final selected = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate ${ids.length} track${ids.length == 1 ? '' : 's'}'),
        content: const _StarPicker(initialRating: 0),
      ),
    );
    if (selected == null || !mounted) return;
    for (final id in ids) {
      await plugin.setPreciseRating(id, selected);
    }
    if (mounted) setState(() {});
    _toast('Rated ${ids.length} track${ids.length == 1 ? '' : 's'} '
        '$selected star${selected == 1 ? '' : 's'}.');
  }

  /// Adds [trackIds] to a playlist the user picks, or a brand-new one —
  /// used by both the per-track "Add to playlist" menu item and the
  /// multi-select bulk action, so a single track and a batch go through
  /// the same path.
  Future<void> _addToPlaylist(Set<String> trackIds) async {
    if (trackIds.isEmpty) return;
    final playlists = await PlaylistStore.instance.load();
    if (!mounted) return;

    const newPlaylistChoice = '__new__';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, newPlaylistChoice),
            child: const Row(
              children: [
                Icon(Icons.add),
                SizedBox(width: 12),
                Text('New playlist'),
              ],
            ),
          ),
          if (playlists.isNotEmpty) const Divider(),
          for (final playlist in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, playlist.id),
              child: Text(playlist.name),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    var updatedPlaylists = playlists;
    Playlist target;
    if (choice == newPlaylistChoice) {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      final trimmed = name?.trim();
      if (trimmed == null || trimmed.isEmpty || !mounted) return;
      target = Playlist(
        id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
        name: trimmed,
        trackIds: const [],
        createdAt: DateTime.now(),
      );
      updatedPlaylists = [...playlists, target];
    } else {
      target = playlists.firstWhere((p) => p.id == choice);
    }

    final merged = <String>{...target.trackIds, ...trackIds}.toList();
    final finalPlaylist = target.copyWith(trackIds: merged);
    updatedPlaylists = updatedPlaylists
        .map((p) => p.id == finalPlaylist.id ? finalPlaylist : p)
        .toList();
    await PlaylistStore.instance.save(updatedPlaylists);
    _toast('Added ${trackIds.length} track${trackIds.length == 1 ? '' : 's'} '
        'to "${finalPlaylist.name}".');
  }

  // --- Manual + automatic tag editing ---

  /// Opens the manual tag editor for one track, then re-reads the file's
  /// tags back into the in-memory track (rather than trusting whatever
  /// the dialog had cached) — the file itself is the source of truth,
  /// same principle MediaScanner scans by.
  Future<void> _editTags(BaseTrack track) async {
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    if (track.localPath == null) {
      _toast('"${track.title}" has no local file to tag.');
      return;
    }
    final changed = await TagEditorDialog.show(context, track, plugin: tagEditor);
    if (!changed || !mounted) return;

    final tags =
        await tagEditor.readTags(track.localPath!, includeArtwork: false);
    if (!mounted) return;
    final index = _tracks.indexWhere((t) => t.id == track.id);
    if (index < 0) return;

    final rawArtist = tags.artist?.trim() ?? '';
    final artists =
        rawArtist.isEmpty ? track.artists : tagEditor.splitArtists(rawArtist);
    final updated = track.copyWith(
      title: (tags.title?.trim().isNotEmpty ?? false)
          ? tags.title!.trim()
          : track.title,
      artists: artists,
      album: (tags.album?.trim().isNotEmpty ?? false)
          ? tags.album!.trim()
          : track.album,
      genres: (tags.genre?.trim().isNotEmpty ?? false)
          ? [tags.genre!.trim()]
          : track.genres,
      year: int.tryParse((tags.year ?? '').trim()) ?? track.year,
      trackNumber:
          int.tryParse((tags.track ?? '').trim()) ?? track.trackNumber,
      discNumber: int.tryParse((tags.disc ?? '').trim()) ?? track.discNumber,
      bpm: double.tryParse((tags.bpm ?? '').trim()) ?? track.bpm,
      key: (tags.initialKey?.trim().isNotEmpty ?? false)
          ? tags.initialKey!.trim()
          : track.key,
      mood:
          (tags.mood?.trim().isNotEmpty ?? false) ? tags.mood!.trim() : track.mood,
    );
    setState(() => _tracks[index] = updated);
    await LibraryRepository.instance.save(_tracks);
    _toast('Tags updated for "${updated.title}".');
  }

  /// Shows what `MediaScanner`/`AudioFormatReader` actually found in this
  /// file's own header — codec, sample rate, bit depth, bitrate, channel
  /// count — the "source" half of Bit-perfect mode's spec'd
  /// source→DSP→output display. A file scanned before these fields
  /// existed, a streaming track, or a format this app can't parse a
  /// header for shows "Not available" per field rather than a fabricated
  /// guess.
  Future<void> _showAudioInfo(BaseTrack track) async {
    String field(String? value) => (value == null || value.isEmpty)
        ? 'Not available'
        : value;
    final rows = <MapEntry<String, String>>[
      MapEntry('Codec', field(track.codec)),
      MapEntry(
        'Sample rate',
        track.sampleRateHz != null
            ? '${(track.sampleRateHz! / 1000).toStringAsFixed(1)} kHz'
            : 'Not available',
      ),
      MapEntry(
        'Bit depth',
        track.bitDepth != null ? '${track.bitDepth}-bit' : 'Not available',
      ),
      MapEntry(
        'Bitrate',
        track.bitrateKbps != null
            ? '${track.bitrateKbps} kbps'
            : 'Not available',
      ),
      MapEntry(
        'Channels',
        track.channels == 1
            ? 'Mono'
            : track.channels == 2
                ? 'Stereo'
                : track.channels != null
                    ? '${track.channels}'
                    : 'Not available',
      ),
      MapEntry('File', field(track.localPath)),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Audio info — ${track.title}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          row.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  bool _bulkAutoTagCancelled = false;

  /// Automatic bulk tagging: cleans up featured-artist splitting
  /// (`TagEditorPlugin.cleanArtistFields`) for every local track, writes
  /// the result back to the actual file (so it survives a rescan, not
  /// just this session's in-memory list), and marks each one auto-tagged.
  ///
  /// "Smart": [force] false (the default, from the menu's "Auto-tag
  /// library") skips anything already marked auto-tagged, so repeat runs
  /// don't keep re-processing (and re-writing files) that never changed.
  /// [force] true is the explicit "redo anyway" escape hatch ("Re-tag
  /// everything" in the menu) — for when separators changed in Settings
  /// and old results need a second pass.
  Future<void> _autoTagLibrary({bool force = false}) async {
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    final candidates = _tracks
        .where((t) =>
            t.localPath != null && (force || !tagEditor.wasAutoTagged(t.id)))
        .toList();
    if (candidates.isEmpty) {
      _toast('Nothing to auto-tag — every local track has already been '
          'processed. Use "Re-tag everything" to force it.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auto-tag library?'),
        content: Text(
          'Checks ${candidates.length} track${candidates.length == 1 ? '' : 's'} '
          'for a featured artist stuck in the title or artist field (using '
          'the separators configured in Settings) and moves it to a '
          'separate artist, writing the fix to the file itself. Tracks '
          'already processed are skipped unless you use "Re-tag '
          'everything."',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _bulkAutoTagCancelled = false;
    final total = candidates.length;
    final doneNotifier = ValueNotifier<int>(0);
    final changedNotifier = ValueNotifier<int>(0);

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Auto-tagging…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: doneNotifier,
              builder: (context, done, _) => ValueListenableBuilder<int>(
                valueListenable: changedNotifier,
                builder: (context, changed, __) =>
                    Text('$done / $total tracks checked · $changed fixed'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _bulkAutoTagCancelled = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    ));

    var done = 0;
    var changed = 0;
    // The *original* track (before this batch's edit) for every track
    // actually changed — item 17's "no undo/backup/restore for tag
    // edits" gap. `TagEditorPlugin.writeTags` already snapshots each
    // file's own pre-write tags for `undoLastEdit`; this list is what
    // lets a single "Undo" action revert the *whole batch*, including
    // this page's in-memory `_tracks` copy, not just one file at a time.
    final changedOriginals = <BaseTrack>[];
    // Same try/catch/finally rationale as _enrichAll/_analyzeAll: this
    // dialog is barrierDismissible: false, so an uncaught exception
    // anywhere in here (a file-write failure, a save failure) would
    // otherwise strand it on screen forever.
    var failed = false;
    try {
      for (final track in candidates) {
        if (_bulkAutoTagCancelled || !mounted) break;
        final cleaned = tagEditor.cleanArtistFields(track);
        if (cleaned != null) {
          final ok = await tagEditor.writeTags(
            track.localPath!,
            title: cleaned.title,
            artist: cleaned.artists.join(', '),
          );
          if (ok) {
            changedOriginals.add(track);
            final index = _tracks.indexWhere((t) => t.id == track.id);
            if (index >= 0) {
              final updated = _tracks[index]
                  .copyWith(title: cleaned.title, artists: cleaned.artists);
              if (mounted) {
                setState(() => _tracks[index] = updated);
              } else {
                _tracks[index] = updated;
              }
            }
            changed++;
            changedNotifier.value = changed;
          }
        }
        await tagEditor.markAutoTagged(track.id);
        done++;
        doneNotifier.value = done;
      }
      await LibraryRepository.instance.save(_tracks);
    } catch (e) {
      failed = true;
      debugPrint('Omnis: bulk auto-tagging stopped early: $e');
    } finally {
      doneNotifier.dispose();
      changedNotifier.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        final message = failed
            ? 'Auto-tagging stopped after an error — $changed of $done '
                'tracks were fixed before it happened.'
            : 'Auto-tagging finished: $changed of $done tracks fixed.';
        if (changedOriginals.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoAutoTagBatch(changedOriginals),
            ),
          ));
        } else {
          _toast(message);
        }
      }
    }
  }

  /// Restores every track in [originalTracks] to its tags as they stood
  /// before the auto-tag batch that just ran — the "Undo" action on
  /// that batch's completion snackbar. Reverts both the file itself
  /// (`TagEditorPlugin.undoLastEdit`, using the snapshot `writeTags`
  /// already saved) and this page's in-memory `_tracks` copy, then
  /// re-persists the library so the reverted titles/artists survive a
  /// restart too — the exact same two-sided update `writeTags`'s own
  /// success path already does, just in reverse.
  Future<void> _undoAutoTagBatch(List<BaseTrack> originalTracks) async {
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) return;
    var restored = 0;
    for (final original in originalTracks) {
      final path = original.localPath;
      if (path == null) continue;
      final ok = await tagEditor.undoLastEdit(path);
      if (!ok) continue;
      restored++;
      final index = _tracks.indexWhere((t) => t.id == original.id);
      if (index < 0) continue;
      if (mounted) {
        setState(() => _tracks[index] = original);
      } else {
        _tracks[index] = original;
      }
    }
    await LibraryRepository.instance.save(_tracks);
    _toast('Restored $restored track${restored == 1 ? '' : 's'} to their '
        'previous tags.');
  }

  /// spec §12's "regex search/replace" gap (item 17) — a bulk pattern-
  /// based tag rewrite across the currently-selected tracks. Builds the
  /// rule via [TagFindReplaceDialog] (preview-first, no write happens
  /// until "Apply"), then applies each affected field through the same
  /// `TagEditorPlugin.writeTags` call every other tag-editing action on
  /// this page already uses, and reuses [_undoAutoTagBatch] for the
  /// "Undo" snackbar action — that method is already generic over "a
  /// list of pre-edit track snapshots to restore," not specific to the
  /// auto-tag batch it was written for.
  Future<void> _findReplaceSelected() async {
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    final candidates =
        _tracks.where((t) => ids.contains(t.id) && t.localPath != null).toList();
    if (candidates.isEmpty) {
      _toast('None of the selected tracks have a local file to edit.');
      return;
    }

    final rule = await TagFindReplaceDialog.show(context, candidates);
    if (rule == null || !mounted) return;

    final matches = previewFindReplace(candidates, rule);
    if (matches.isEmpty) {
      _toast('Nothing to change.');
      return;
    }

    final byTrackId = <String, List<TagFindReplaceMatch>>{};
    for (final match in matches) {
      byTrackId.putIfAbsent(match.track.id, () => []).add(match);
    }

    final changedOriginals = <BaseTrack>[];
    for (final entry in byTrackId.entries) {
      final track = candidates.firstWhere((t) => t.id == entry.key);
      final path = track.localPath;
      if (path == null) continue;

      String? newTitle;
      String? newArtist;
      String? newAlbum;
      String? newGenre;
      for (final match in entry.value) {
        switch (match.field) {
          case TagFindReplaceField.title:
            newTitle = match.after;
          case TagFindReplaceField.artist:
            newArtist = match.after;
          case TagFindReplaceField.album:
            newAlbum = match.after;
          case TagFindReplaceField.genre:
            newGenre = match.after;
        }
      }

      final ok = await tagEditor.writeTags(
        path,
        title: newTitle,
        artist: newArtist,
        album: newAlbum,
        genre: newGenre,
      );
      if (!ok) continue;

      changedOriginals.add(track);
      final index = _tracks.indexWhere((t) => t.id == track.id);
      if (index >= 0) {
        final updated = _tracks[index].copyWith(
          title: newTitle,
          artists: newArtist != null
              ? tagEditor.splitArtists(newArtist)
              : null,
          album: newAlbum,
          genres: newGenre != null ? [newGenre] : null,
        );
        if (mounted) {
          setState(() => _tracks[index] = updated);
        } else {
          _tracks[index] = updated;
        }
      }
    }

    await LibraryRepository.instance.save(_tracks);
    if (!mounted) return;
    setState(_selectedIds.clear);

    if (changedOriginals.isNotEmpty) {
      final changed = changedOriginals.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Updated tags on $changed track${changed == 1 ? '' : 's'}.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoAutoTagBatch(changedOriginals),
        ),
      ));
    } else {
      _toast('Nothing changed.');
    }
  }

  /// spec §12's "virtual/calculated tags" gap (item 17) — builds a new
  /// value for one writable field from a `{token}` template referencing
  /// computed data (year, bitrate, duration, ...) across the currently-
  /// selected tracks. Mirrors [_findReplaceSelected] exactly: builds via
  /// [CalculatedTagDialog] (preview-first), writes through the same
  /// `TagEditorPlugin.writeTags` call, and reuses [_undoAutoTagBatch] for
  /// the "Undo" snackbar action.
  Future<void> _calculatedTagsSelected() async {
    final tagEditor = _tagEditorPlugin;
    if (tagEditor == null) {
      _toast('The Tag Editor plugin is disabled in Settings.');
      return;
    }
    final ids = Set<String>.from(_selectedIds);
    if (ids.isEmpty) return;
    final candidates =
        _tracks.where((t) => ids.contains(t.id) && t.localPath != null).toList();
    if (candidates.isEmpty) {
      _toast('None of the selected tracks have a local file to edit.');
      return;
    }

    final rule = await CalculatedTagDialog.show(context, candidates);
    if (rule == null || !mounted) return;

    final matches = previewCalculatedTags(candidates, rule);
    if (matches.isEmpty) {
      _toast('Nothing to change.');
      return;
    }

    final changedOriginals = <BaseTrack>[];
    for (final match in matches) {
      final track = match.track;
      final path = track.localPath;
      if (path == null) continue;

      final ok = await tagEditor.writeTags(
        path,
        title:
            rule.target == CalculatedTagTargetField.title ? match.after : null,
        artist:
            rule.target == CalculatedTagTargetField.artist ? match.after : null,
        album:
            rule.target == CalculatedTagTargetField.album ? match.after : null,
        genre:
            rule.target == CalculatedTagTargetField.genre ? match.after : null,
      );
      if (!ok) continue;

      changedOriginals.add(track);
      final index = _tracks.indexWhere((t) => t.id == track.id);
      if (index >= 0) {
        final updated = _tracks[index].copyWith(
          title: rule.target == CalculatedTagTargetField.title
              ? match.after
              : null,
          artists: rule.target == CalculatedTagTargetField.artist
              ? tagEditor.splitArtists(match.after)
              : null,
          album: rule.target == CalculatedTagTargetField.album
              ? match.after
              : null,
          genres: rule.target == CalculatedTagTargetField.genre
              ? [match.after]
              : null,
        );
        if (mounted) {
          setState(() => _tracks[index] = updated);
        } else {
          _tracks[index] = updated;
        }
      }
    }

    await LibraryRepository.instance.save(_tracks);
    if (!mounted) return;
    setState(_selectedIds.clear);

    if (changedOriginals.isNotEmpty) {
      final changed = changedOriginals.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Updated tags on $changed track${changed == 1 ? '' : 's'}.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoAutoTagBatch(changedOriginals),
        ),
      ));
    } else {
      _toast('Nothing changed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = buildLibrarySections(_visibleTracks,
        viewMode: _viewMode,
        showAlbums: _showAlbums,
        groupArtistsByAlbumArtist:
            AppSettings.instance.groupArtistsByAlbumArtist);
    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: () => setState(_selectedIds.clear),
              ),
              title: Text('${_selectedIds.length} selected'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  tooltip: 'Add to playlist',
                  onPressed: () => _addToPlaylist(Set<String>.from(_selectedIds)),
                ),
                IconButton(
                  icon: const Icon(Icons.favorite_border),
                  tooltip: 'Add to favorites',
                  onPressed: () async {
                    final plugin = _favoritesPlugin;
                    if (plugin == null) {
                      _toast('The Favorites plugin is disabled in Settings.');
                      return;
                    }
                    for (final id in _selectedIds) {
                      await plugin.setFavorite(id, true);
                    }
                    if (mounted) setState(() {});
                    _toast('Added ${_selectedIds.length} track'
                        '${_selectedIds.length == 1 ? '' : 's'} to favorites.');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.star_border),
                  tooltip: 'Rate selected',
                  onPressed: _bulkRate,
                ),
                IconButton(
                  icon: const Icon(Icons.find_replace),
                  tooltip: 'Find & Replace tags…',
                  onPressed: _findReplaceSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.data_object),
                  tooltip: 'Virtual / calculated tags…',
                  onPressed: _calculatedTagsSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete selected',
                  onPressed: _deleteSelected,
                ),
              ],
            )
          : AppBar(
              title: const Text('Library'),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.auto_fix_high),
                  tooltip: 'Library tools',
                  enabled: !_loading && _tracks.isNotEmpty,
                  onSelected: (value) {
                    if (value == 'enrich_all') _enrichAll();
                    if (value == 'artwork_all') _lookupArtworkForAll();
                    if (value == 'analyze_all') _analyzeAll();
                    if (value == 'measure_durations') _measureDurations();
                    if (value == 'cleanup') _openCleanupTool();
                    if (value == 'cleanup_report') _openCleanupReport();
                    if (value == 'statistics') _openStatistics();
                    if (value == 'auto_tag') _autoTagLibrary();
                    if (value == 'retag_all') _autoTagLibrary(force: true);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'enrich_all',
                      child: Text('Look up metadata for the whole library'),
                    ),
                    PopupMenuItem(
                      value: 'artwork_all',
                      child: Text('Look up artwork for the whole library'),
                    ),
                    PopupMenuItem(
                      value: 'analyze_all',
                      child: Text('Analyze audio for the whole library'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'auto_tag',
                      child: Text('Auto-tag library (skips already-tagged)'),
                    ),
                    PopupMenuItem(
                      value: 'retag_all',
                      child: Text('Re-tag everything'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'measure_durations',
                      child: Text('Measure track durations'),
                    ),
                    PopupMenuItem(
                      value: 'cleanup',
                      child: Text('Find duplicates & short tracks…'),
                    ),
                    PopupMenuItem(
                      value: 'cleanup_report',
                      child: Text('Analyze library (cleanup report)…'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'statistics',
                      child: Text('Library statistics'),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.audio_file),
                  tooltip: 'Add audio files',
                  onPressed: _loading ? null : _pickAndAdd,
                ),
              ],
            ),
      body: Column(
        children: [
          // Content plugins inject via uiSlot('library_header') — the Core
          // hook this location ID documents existed but nothing rendered
          // it here before.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: PluginSlotView(
              pluginManager: widget.pluginManager,
              locationId: 'library_header',
            ),
          ),
          Expanded(child: _buildBody(theme, sections)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<LibrarySection> sections) {
    return _loading
          ? const LibraryShimmerList()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => setState(() => _error = null),
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                )
              : _tracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.library_music,
                              size: 72, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('No tracks yet'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _pickAndAdd,
                            icon: const Icon(Icons.add),
                            label: const Text('Add audio files'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search library',
                                  prefixIcon: const Icon(Icons.search),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: _searchQuery.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.clear),
                                          tooltip: 'Clear search',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        ),
                                ),
                                onChanged: (value) =>
                                    setState(() => _searchQuery = value),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<LibraryViewMode>(
                                  segments: const [
                                    ButtonSegment(
                                        value: LibraryViewMode.songs,
                                        label: Text('Songs'),
                                        icon: Icon(Icons.music_note)),
                                    ButtonSegment(
                                        value: LibraryViewMode.albums,
                                        label: Text('Albums'),
                                        icon: Icon(Icons.album)),
                                    ButtonSegment(
                                        value: LibraryViewMode.artists,
                                        label: Text('Artists'),
                                        icon: Icon(Icons.person)),
                                    ButtonSegment(
                                        value: LibraryViewMode.genres,
                                        label: Text('Genres'),
                                        icon: Icon(Icons.tag)),
                                    ButtonSegment(
                                        value: LibraryViewMode.folders,
                                        label: Text('Folders'),
                                        icon: Icon(Icons.folder)),
                                  ],
                                  selected: {_viewMode},
                                  onSelectionChanged: (value) {
                                    setState(() => _viewMode = value.first);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (_viewMode == LibraryViewMode.artists ||
                                      _viewMode == LibraryViewMode.genres)
                                    FilterChip(
                                      label: const Text('Nest albums'),
                                      selected: _showAlbums,
                                      onSelected: (value) =>
                                          setState(() => _showAlbums = value),
                                    ),
                                  const Spacer(),
                                  if (_gridCapable) ...[
                                    if (_displayMode == LibraryDisplayMode.grid)
                                      PopupMenuButton<int>(
                                        tooltip: 'Grid columns',
                                        onSelected: _setGridColumns,
                                        itemBuilder: (context) => [2, 3, 4, 5]
                                            .map((n) => PopupMenuItem(
                                                  value: n,
                                                  child: Text('$n×$n grid'),
                                                ))
                                            .toList(),
                                        child: Chip(
                                          label:
                                              Text('$_gridColumns×$_gridColumns'),
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: _displayMode == LibraryDisplayMode.grid
                                          ? 'List view'
                                          : 'Grid view',
                                      icon: Icon(
                                          _displayMode == LibraryDisplayMode.grid
                                              ? Icons.view_list
                                              : Icons.grid_view),
                                      onPressed: () => _setDisplayMode(
                                          _displayMode == LibraryDisplayMode.grid
                                              ? LibraryDisplayMode.list
                                              : LibraryDisplayMode.grid),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: sections.isEmpty && _searchQuery.trim().isNotEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_off,
                                            size: 48,
                                            color: theme.colorScheme.outline),
                                        const SizedBox(height: 12),
                                        Text(
                                            'No results for '
                                            '"${_searchController.text}"',
                                            textAlign: TextAlign.center),
                                      ],
                                    ),
                                  ),
                                )
                              : (_gridCapable &&
                                      _displayMode == LibraryDisplayMode.grid)
                                  ? _buildGrid()
                                  : ListView.builder(
                                      itemCount: sections.length,
                                      itemBuilder: (context, index) {
                                        final section = sections[index];
                                        return _buildSection(section, depth: 0);
                                      },
                                    ),
                        ),
                      ],
                    );
  }

  /// Grid view is a flat "one tile per item" layout — it doesn't apply to
  /// Artists (a 3-level artist → album → track hierarchy doesn't reduce to
  /// a flat grid the way Songs/Albums/Genres do) or Folders (a plain
  /// directory listing reads better as a list too).
  bool get _gridCapable =>
      _viewMode != LibraryViewMode.artists &&
      _viewMode != LibraryViewMode.folders;

  LibraryDisplayMode get _displayMode {
    final settings = AppSettings.instance;
    return switch (_viewMode) {
      LibraryViewMode.songs => settings.songsViewMode,
      LibraryViewMode.albums => settings.albumsViewMode,
      LibraryViewMode.genres => settings.genresViewMode,
      LibraryViewMode.artists => LibraryDisplayMode.list,
      LibraryViewMode.folders => LibraryDisplayMode.list,
    };
  }

  int get _gridColumns {
    final settings = AppSettings.instance;
    return switch (_viewMode) {
      LibraryViewMode.songs => settings.songsGridColumns,
      LibraryViewMode.albums => settings.albumsGridColumns,
      LibraryViewMode.genres => settings.genresGridColumns,
      LibraryViewMode.artists => 3,
      LibraryViewMode.folders => 3,
    };
  }

  Future<void> _setDisplayMode(LibraryDisplayMode mode) async {
    final settings = AppSettings.instance;
    switch (_viewMode) {
      case LibraryViewMode.songs:
        await settings.setSongsViewMode(mode);
      case LibraryViewMode.albums:
        await settings.setAlbumsViewMode(mode);
      case LibraryViewMode.genres:
        await settings.setGenresViewMode(mode);
      case LibraryViewMode.artists:
      case LibraryViewMode.folders:
        break;
    }
    if (mounted) setState(() {});
  }

  Future<void> _setGridColumns(int columns) async {
    final settings = AppSettings.instance;
    switch (_viewMode) {
      case LibraryViewMode.songs:
        await settings.setSongsGridColumns(columns);
      case LibraryViewMode.albums:
        await settings.setAlbumsGridColumns(columns);
      case LibraryViewMode.genres:
        await settings.setGenresGridColumns(columns);
      case LibraryViewMode.artists:
      case LibraryViewMode.folders:
        break;
    }
    if (mounted) setState(() {});
  }

  /// Flat, one-tile-per-item sections for grid display: every song is its
  /// own tile (unlike the "All songs" single-section list grouping), and
  /// albums/genres are grouped without the artist-nested nesting list view
  /// uses — a grid tile represents one thing you can tap to play.
  List<LibrarySection> _gridSections() {
    if (_viewMode == LibraryViewMode.songs) {
      return _visibleTracks
          .map((t) => LibrarySection(title: t.title, tracks: [t]))
          .toList();
    }
    return buildLibrarySections(_visibleTracks,
        viewMode: _viewMode,
        showAlbums: false,
        groupArtistsByAlbumArtist:
            AppSettings.instance.groupArtistsByAlbumArtist);
  }

  Widget _buildGrid() {
    final gridSections = _gridSections();
    if (gridSections.isEmpty) {
      return const Center(child: Text('Nothing here yet.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: gridSections.length,
      itemBuilder: (context, index) => _buildGridTile(gridSections[index]),
    );
  }

  Widget _buildGridTile(LibrarySection section) {
    final theme = Theme.of(context);
    final cover = section.tracks.isNotEmpty ? section.tracks.first : null;
    final selected =
        section.tracks.isNotEmpty && section.tracks.every((t) => _selectedIds.contains(t.id));
    final gridRatingBadge =
        (_viewMode == LibraryViewMode.albums || _viewMode == LibraryViewMode.artists)
            ? _groupRatingBadge(section.tracks)
            : null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectionMode
          ? _toggleSelectedGroup(section.tracks)
          : _playSection(section),
      onLongPress: () => _toggleSelectedGroup(section.tracks),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: cover != null
                      ? TrackArtwork(track: cover, fit: BoxFit.cover)
                      : Container(
                          color: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.music_note,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                ),
                if (_selectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: selected
                          ? theme.colorScheme.primary
                          : Colors.black.withValues(alpha: 0.45),
                      child: Icon(
                        selected ? Icons.check : Icons.circle_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(section.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          if (section.tracks.length > 1)
            Text('${section.tracks.length} tracks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          if (gridRatingBadge != null) gridRatingBadge,
        ],
      ),
    );
  }

  /// Plays a grid tile: a single-track section (Songs) plays that track in
  /// the context of the full library queue; a multi-track section
  /// (Albums/Genres) replaces the queue with just that group.
  Future<void> _playSection(LibrarySection section) async {
    if (section.tracks.length == 1) {
      await _playTrack(section.tracks.first);
      return;
    }
    await widget.engine.setQueue(section.tracks);
    await widget.engine.play();
  }

  /// MusicBee-comparison §36's "album/artist-level ratings" gap — a
  /// read-only, calculated average across [tracks]' individual ratings,
  /// distinct from (and never itself persisted alongside) the per-track
  /// rating `RatingsPlugin` stores. `null` when no track in the group
  /// has been rated yet, so callers can skip rendering anything rather
  /// than showing a misleading "0.0".
  Widget? _groupRatingBadge(List<BaseTrack> tracks) {
    final summary = averageRating(tracks, _ratingOf);
    if (summary == null) return null;
    final theme = Theme.of(context);
    return Text(
      '★ ${summary.average.toStringAsFixed(1)} '
      '(${summary.ratedCount} rated)',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.primary),
    );
  }

  Widget _buildSection(LibrarySection section, {required int depth}) {
    final theme = Theme.of(context);
    // Only the top-level row of an Artists-view section is actually an
    // artist name — deeper levels there are albums/tracks, and every
    // other view mode's top level (album/genre/folder) isn't an artist
    // at all, so this only ever fires exactly where a photo makes sense.
    final isArtistRow = depth == 0 && _viewMode == LibraryViewMode.artists;
    final isAlbumRow = depth == 0 && _viewMode == LibraryViewMode.albums;

    if (section.children.isNotEmpty) {
      return ExpansionTile(
        tilePadding: EdgeInsets.only(left: 16 + depth * 12, right: 16),
        leading: isArtistRow
            ? ArtistAvatar(
                artistName: section.title,
                imageProvider: _artistImageProvider,
                radius: 18,
              )
            : null,
        title: isArtistRow
            ? Row(
                children: [
                  Expanded(
                    child: Text(section.title,
                        style: theme.textTheme.titleMedium),
                  ),
                  // A custom `trailing` would replace ExpansionTile's own
                  // expand/collapse chevron entirely, so this sits in the
                  // title row instead, preserving that default indicator.
                  IconButton(
                    icon: const Icon(Icons.people_outline),
                    tooltip: 'Similar artists',
                    onPressed: () => _showSimilarArtists(section.title),
                  ),
                ],
              )
            : Text(section.title, style: theme.textTheme.titleMedium),
        subtitle: isArtistRow ? _groupRatingBadge(section.allTracks) : null,
        children: section.children
            .map((child) => _buildSection(child, depth: depth + 1))
            .toList(),
      );
    }

    final ratingBadge =
        (isArtistRow || isAlbumRow) ? _groupRatingBadge(section.allTracks) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 16 + depth * 12, top: 8, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isArtistRow
                    ? Row(
                        children: [
                          ArtistAvatar(
                            artistName: section.title,
                            imageProvider: _artistImageProvider,
                            radius: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(section.title,
                                style: theme.textTheme.titleSmall),
                          ),
                          IconButton(
                            icon: const Icon(Icons.people_outline, size: 20),
                            tooltip: 'Similar artists',
                            onPressed: () =>
                                _showSimilarArtists(section.title),
                          ),
                        ],
                      )
                    : Text(section.title, style: theme.textTheme.titleSmall),
                if (ratingBadge != null) ratingBadge,
              ],
            ),
          ),
        ...section.tracks.map((track) {
          final selected = _selectedIds.contains(track.id);
          final compact =
              AppSettings.instance.libraryDensity == LibraryDensity.compact;
          final artSize = compact ? 36.0 : 44.0;
          return ListTile(
            dense: compact,
            leading: _selectionMode
                ? CircleAvatar(
                    radius: compact ? 18 : 22,
                    backgroundColor: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      selected ? Icons.check : Icons.circle_outlined,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TrackArtwork(
                      track: track,
                      width: artSize,
                      height: artSize,
                      iconSize: compact ? 16 : 20,
                    ),
                  ),
            title:
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_subtitle(track)),
            selected: selected,
            trailing: _selectionMode
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _currentTrackIcon(track),
                      IconButton(
                        icon: Icon(
                          _isFavorite(track.id) ? Icons.favorite : Icons.favorite_border,
                          size: 20,
                          color: _isFavorite(track.id) ? theme.colorScheme.primary : null,
                        ),
                        tooltip: _isFavorite(track.id)
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                        onPressed: () => _toggleFavorite(track.id),
                      ),
                      // Only shown once a track actually has a rating —
                      // unlike the favorite heart, most tracks stay
                      // unrated, so reserving row space for every track
                      // would mostly just be clutter. The full picker
                      // (any rating, including a first one) is always
                      // reachable via the "Rate track" menu item below.
                      if (_ratingOf(track.id) > 0)
                        IconButton(
                          icon: const Icon(Icons.star, size: 20),
                          color: theme.colorScheme.primary,
                          tooltip: 'Rated ${_ratingOf(track.id)}/5',
                          onPressed: () => _rateTrack(track),
                        ),
                      // Same "only shown once set" reasoning as the star
                      // rating above — an independent signal (§36), so a
                      // track can show a thumb icon, a star icon, both,
                      // or neither.
                      if (_thumbOf(track.id) != ThumbState.none)
                        IconButton(
                          icon: Icon(
                            _thumbOf(track.id) == ThumbState.up
                                ? Icons.thumb_up
                                : Icons.thumb_down,
                            size: 20,
                          ),
                          color: theme.colorScheme.primary,
                          tooltip: _thumbOf(track.id) == ThumbState.up
                              ? 'Thumbed up'
                              : 'Thumbed down',
                          onPressed: () =>
                              _setThumb(track, _thumbOf(track.id)),
                        ),
                      if (_enrichingIds.contains(track.id) ||
                          _analyzingIds.contains(track.id))
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          tooltip: 'Track tools',
                          onSelected: (value) {
                            if (value == 'play_next') _playNext(track);
                            if (value == 'add_to_queue') _addToQueue(track);
                            if (value == 'play_similar') _playSimilar(track);
                            if (value == 'edit_tags') _editTags(track);
                            if (value == 'add_to_playlist') {
                              _addToPlaylist({track.id});
                            }
                            if (value == 'rate') _rateTrack(track);
                            if (value == 'thumb_up') {
                              _setThumb(track, ThumbState.up);
                            }
                            if (value == 'thumb_down') {
                              _setThumb(track, ThumbState.down);
                            }
                            if (value == 'enrich') _enrichSingle(track);
                            if (value == 'lookup_artwork') {
                              _lookupArtworkOnline(track);
                            }
                            if (value == 'analyze') _analyzeSingle(track);
                            if (value == 'set_ringtone') _setAsRingtone(track);
                            if (value == 'audio_info') _showAudioInfo(track);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'play_next',
                              child: Text('Play next'),
                            ),
                            PopupMenuItem(
                              value: 'add_to_queue',
                              child: Text('Add to queue'),
                            ),
                            PopupMenuItem(
                              value: 'play_similar',
                              child: Text('Play similar'),
                            ),
                            PopupMenuItem(
                              value: 'edit_tags',
                              child: Text('Edit tags'),
                            ),
                            PopupMenuItem(
                              value: 'audio_info',
                              child: Text('Audio info'),
                            ),
                            PopupMenuItem(
                              value: 'add_to_playlist',
                              child: Text('Add to playlist'),
                            ),
                            PopupMenuItem(
                              value: 'rate',
                              child: Text('Rate track'),
                            ),
                            PopupMenuItem(
                              value: 'thumb_up',
                              child: Text('Thumbs up'),
                            ),
                            PopupMenuItem(
                              value: 'thumb_down',
                              child: Text('Thumbs down'),
                            ),
                            PopupMenuItem(
                              value: 'enrich',
                              child: Text('Look up metadata'),
                            ),
                            PopupMenuItem(
                              value: 'lookup_artwork',
                              child: Text('Look up artwork online'),
                            ),
                            PopupMenuItem(
                              value: 'analyze',
                              child: Text('Analyze audio (BPM/key/mood)'),
                            ),
                            PopupMenuItem(
                              value: 'set_ringtone',
                              child: Text('Set as ringtone'),
                            ),
                          ],
                        ),
                    ],
                  ),
            onTap: () =>
                _selectionMode ? _toggleSelected(track.id) : _playTrack(track),
            onLongPress: () => _toggleSelected(track.id),
          );
        }),
      ],
    );
  }

  Widget _currentTrackIcon(BaseTrack track) {
    final current = widget.engine.currentTrack;
    if (current != null && current.id == track.id) {
      return const Icon(Icons.graphic_eq, color: Colors.deepPurple);
    }
    return const SizedBox.shrink();
  }

  String _subtitle(BaseTrack track) {
    final parts = <String>[];
    if (track.artists.isNotEmpty) {
      parts.add(track.artists.join(', '));
    }
    if (track.album.isNotEmpty) {
      parts.add(track.album);
    }
    // Surfaces what enrichment/analysis actually found — otherwise a
    // successful lookup would have no visible effect on this screen at all.
    if (track.mood != null && track.mood!.isNotEmpty) {
      parts.add(track.mood!);
    } else if (track.genres.isNotEmpty) {
      parts.add(track.genres.first);
    }
    if (track.bpm != null) {
      parts.add('${track.bpm!.round()} BPM');
    }
    if (track.key != null && track.key!.isNotEmpty) {
      parts.add(track.key!);
    }
    return parts.isEmpty ? 'No metadata' : parts.join(' • ');
  }
}

/// Reviews duplicate groups and short tracks before anything is deleted.
/// Pre-selects a "smart" default — the shortest/most redundant copy in
/// each duplicate group, every short track — so accepting the defaults
/// is a reasonable one-tap cleanup, while every checkbox stays editable
/// for anyone who wants to keep something the default would drop.
class _CleanupSheet extends StatefulWidget {
  final List<List<BaseTrack>> duplicateGroups;
  final List<BaseTrack> shortTracks;

  const _CleanupSheet({
    required this.duplicateGroups,
    required this.shortTracks,
  });

  @override
  State<_CleanupSheet> createState() => _CleanupSheetState();
}

class _CleanupSheetState extends State<_CleanupSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {};
    // Keep the longest copy in each duplicate group (most likely the
    // highest-quality/most complete rip) and pre-select the rest.
    for (final group in widget.duplicateGroups) {
      final sorted = [...group]
        ..sort((a, b) => b.duration.compareTo(a.duration));
      for (final track in sorted.skip(1)) {
        _selected.add(track.id);
      }
    }
    for (final track in widget.shortTracks) {
      _selected.add(track.id);
    }
  }

  void _toggle(String id, bool value) {
    setState(() {
      if (value) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'unknown length';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Clean up library',
                      style: theme.textTheme.titleLarge),
                ),
                Text('${_selected.length} selected'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (widget.duplicateGroups.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Possible duplicates',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final group in widget.duplicateGroups) ...[
                    ...group.map((track) => CheckboxListTile(
                          value: _selected.contains(track.id),
                          onChanged: (v) => _toggle(track.id, v ?? false),
                          title: Text(track.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${track.artists.join(', ')} • '
                            '${_formatDuration(track.duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                    const Divider(height: 1),
                  ],
                ],
                if (widget.shortTracks.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('Short tracks (likely not songs)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ...widget.shortTracks.map((track) => CheckboxListTile(
                        value: _selected.contains(track.id),
                        onChanged: (v) => _toggle(track.id, v ?? false),
                        title: Text(track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_formatDuration(track.duration)),
                      )),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Delete ${_selected.length}'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Five tappable stars for [_LibraryPageState._rateTrack] — MusicBee
/// comparison §36's "half stars" gap: tapping the left half of a star
/// picks `i - 0.5`, the right half picks the whole `i`, both popping the
/// dialog immediately with no separate confirm step (the same one-tap
/// shape this always had, just with twice the resolution). A "Clear
/// rating" action only appears once something is actually rated,
/// popping with `0`.
class _StarPicker extends StatelessWidget {
  final double initialRating;

  const _StarPicker({required this.initialRating});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    const iconSize = 32.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTapUp: (details) {
              final tappedLeftHalf = details.localPosition.dx < iconSize / 2;
              final rating = snapToHalfStep(tappedLeftHalf ? i - 0.5 : i.toDouble());
              Navigator.of(context).pop(rating);
            },
            child: Tooltip(
              message: '$i star${i == 1 ? '' : 's'}',
              child: Icon(
                switch (iconStateFor(i, initialRating)) {
                  StarIconState.full => Icons.star,
                  StarIconState.half => Icons.star_half,
                  StarIconState.empty => Icons.star_border,
                },
                size: iconSize,
                color: iconStateFor(i, initialRating) == StarIconState.empty
                    ? null
                    : color,
              ),
            ),
          ),
        if (initialRating > 0)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Clear rating',
            onPressed: () => Navigator.of(context).pop(0.0),
          ),
      ],
    );
  }
}
