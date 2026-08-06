import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/plugin_api/audio_analysis_result.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugin_api/enrichment_result.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/media_scanner.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/plugins/favorites_plugin.dart';
import 'package:omnis/plugins/metadata_enrichment_plugin.dart';
import 'package:omnis/plugins/tag_editor_plugin.dart';
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:omnis/ui/tag_editor_dialog.dart';
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
}

List<LibrarySection> buildLibrarySections(
  List<BaseTrack> tracks, {
  required LibraryViewMode viewMode,
  required bool showAlbums,
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
      final artist =
          track.artists.isNotEmpty ? track.artists.first : 'Unknown Artist';
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
    _trackSub?.cancel();
    super.dispose();
  }

  /// Load the previously-scanned library from disk so the user doesn't
  /// have to rescan (and re-grant permission) on every app launch.
  Future<void> _loadPersistedLibrary() async {
    final saved = await LibraryStore.instance.load();
    if (!mounted) return;
    setState(() => _tracks = saved);
    if (saved.isNotEmpty) {
      await widget.engine.setQueue(saved);
    }
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
      final scanned = await MediaScanner.instance.scanLibrary();
      if (scanned.isEmpty) {
        setState(() =>
            _error = 'No audio files found. Try picking a folder in Settings.');
        return;
      }
      // Dedupe by id: scanLibrary() always rescans everything from
      // scratch (it's not incremental), so without this, pressing "Add
      // audio files" a second time duplicated every track already in
      // _tracks.
      final existingIds = _tracks.map((t) => t.id).toSet();
      final newTracks =
          scanned.where((t) => !existingIds.contains(t.id)).toList();
      setState(() => _tracks = [..._tracks, ...newTracks]);
      // Persist so the library survives app restarts.
      await LibraryStore.instance.save(_tracks);
      await widget.engine.setQueue(_tracks);
      await widget.engine.play();
    } catch (e) {
      setState(() => _error = 'Could not load audio files: $e');
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
      await LibraryStore.instance.save(_tracks);
      _toast('Updated "${track.title}" from ${result.sourcesUsed.join(', ')}.');
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

    await LibraryStore.instance.save(_tracks);
    doneNotifier.dispose();
    changedNotifier.dispose();
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      _toast('Enrichment finished: $changed of $done tracks updated.');
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
      await LibraryStore.instance.save(_tracks);
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
    for (final track in local) {
      if (_bulkAnalyzeCancelled || !mounted) break;
      final result = await provider.analyze(track);
      if (!result.isEmpty) {
        _applyAnalysis(track, result);
        changed++;
        changedNotifier.value = changed;
      }
      done++;
      doneNotifier.value = done;
    }

    await LibraryStore.instance.save(_tracks);
    doneNotifier.dispose();
    changedNotifier.dispose();
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      _toast('Analysis finished: $changed of $done tracks updated.');
    }
  }

  // --- Duration measurement (unblocks short-track cleanup) ---
  //
  // Desktop scans never had a way to know a track's real length — ID3
  // tags don't reliably carry one — so every desktop-scanned track sat at
  // duration 0 forever. That silently defeated "short tracks" cleanup on
  // desktop: 0 is treated as "unknown," not "confirmed short" (see
  // findShortTracks), so nothing was ever found. This measures the real
  // duration for whatever's still unknown, once, by actually opening each
  // file — that's too slow to do during a bulk scan (see MediaScanner's
  // own doc on why it doesn't), so it's a separate, explicit, cancellable
  // pass instead.
  bool _bulkMeasureCancelled = false;

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

  Future<void> _measureDurations() async {
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

    var done = 0;
    for (final track in unmeasured) {
      if (_bulkMeasureCancelled || !mounted) break;
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
      doneNotifier.value = done;
    }

    await LibraryStore.instance.save(_tracks);
    doneNotifier.dispose();
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      _toast('Measured $done of $total tracks.');
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
    setState(() {
      _tracks.removeWhere((t) => ids.contains(t.id));
      _selectedIds.removeAll(ids);
    });
    await LibraryStore.instance.save(_tracks);
    await widget.engine.setQueue(_tracks);
    _toast('Deleted ${toDelete.length} track${toDelete.length == 1 ? '' : 's'}.');
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

  // --- Favorites + playlists ---

  FavoritesPlugin? get _favoritesPlugin =>
      widget.pluginManager.bundled<FavoritesPlugin>(onlyEnabled: true);

  TagEditorPlugin? get _tagEditorPlugin =>
      widget.pluginManager.bundled<TagEditorPlugin>(onlyEnabled: true);

  bool _isFavorite(String trackId) =>
      _favoritesPlugin?.isFavorite(trackId) ?? false;

  Future<void> _toggleFavorite(String trackId) async {
    final plugin = _favoritesPlugin;
    if (plugin == null) {
      _toast('The Favorites plugin is disabled in Settings.');
      return;
    }
    await plugin.toggleFavorite(trackId);
    if (mounted) setState(() {});
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
    await LibraryStore.instance.save(_tracks);
    _toast('Tags updated for "${updated.title}".');
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

    await LibraryStore.instance.save(_tracks);
    doneNotifier.dispose();
    changedNotifier.dispose();
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      _toast('Auto-tagging finished: $changed of $done tracks fixed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = buildLibrarySections(_tracks,
        viewMode: _viewMode, showAlbums: _showAlbums);
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
                    if (value == 'analyze_all') _analyzeAll();
                    if (value == 'measure_durations') _measureDurations();
                    if (value == 'cleanup') _openCleanupTool();
                    if (value == 'auto_tag') _autoTagLibrary();
                    if (value == 'retag_all') _autoTagLibrary(force: true);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'enrich_all',
                      child: Text('Look up metadata for the whole library'),
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
          ? const Center(child: CircularProgressIndicator())
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
                          child: (_gridCapable &&
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
      return _tracks
          .map((t) => LibrarySection(title: t.title, tracks: [t]))
          .toList();
    }
    return buildLibrarySections(_tracks, viewMode: _viewMode, showAlbums: false);
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

  Widget _buildSection(LibrarySection section, {required int depth}) {
    final theme = Theme.of(context);

    if (section.children.isNotEmpty) {
      return ExpansionTile(
        tilePadding: EdgeInsets.only(left: 16 + depth * 12, right: 16),
        title: Text(section.title, style: theme.textTheme.titleMedium),
        children: section.children
            .map((child) => _buildSection(child, depth: depth + 1))
            .toList(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 16 + depth * 12, top: 8, bottom: 4),
            child: Text(section.title, style: theme.textTheme.titleSmall),
          ),
        ...section.tracks.map((track) {
          final selected = _selectedIds.contains(track.id);
          return ListTile(
            leading: _selectionMode
                ? CircleAvatar(
                    radius: 22,
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
                      width: 44,
                      height: 44,
                      iconSize: 20,
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
                            if (value == 'edit_tags') _editTags(track);
                            if (value == 'add_to_playlist') {
                              _addToPlaylist({track.id});
                            }
                            if (value == 'enrich') _enrichSingle(track);
                            if (value == 'analyze') _analyzeSingle(track);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit_tags',
                              child: Text('Edit tags'),
                            ),
                            PopupMenuItem(
                              value: 'add_to_playlist',
                              child: Text('Add to playlist'),
                            ),
                            PopupMenuItem(
                              value: 'enrich',
                              child: Text('Look up metadata'),
                            ),
                            PopupMenuItem(
                              value: 'analyze',
                              child: Text('Analyze audio (BPM/key/mood)'),
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
