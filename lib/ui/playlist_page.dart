import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/plugin_api/play_record.dart';
import 'package:omnis/core/playlist_folder_store.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// The four always-present "smart" entries shown above the user's real
/// playlists — computed live from other plugins/the engine rather than
/// stored playlist data, the same idea as Spotify's Liked Songs or
/// Musicolet's "top rated"/most-played lists.
enum _SmartList { queue, favorites, recent, mostPlayed }

/// Playlists screen.
///
/// Previously this tab only ever showed the live playback queue — there
/// was no way to save a named collection of tracks at all, unlike every
/// named competitor (Spotify, Poweramp, Musicolet, Namida all separate
/// "a playlist" from "what's queued right now"). Real playlists are
/// persisted via [PlaylistStore]; the live queue is still reachable here
/// too, as one of the "smart" entries above the user's own playlists,
/// alongside Favorites (from [FavoritesPlugin]) and Recently/Most Played
/// (from whatever's registered as [IPlayHistoryProvider]).
class PlaylistPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;

  const PlaylistPage({
    super.key,
    required this.engine,
    required this.pluginManager,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Playlist> _playlists = [];
  PlaylistFolderData _folderData = PlaylistFolderData.empty;
  List<BaseTrack> _libraryTracks = [];
  bool _loading = true;

  /// Which detail view is open, if any. Mutually exclusive with
  /// [_openPlaylist] — only one can be non-null at a time.
  _SmartList? _openSmart;
  Playlist? _openPlaylist;

  StreamSubscription<List<BaseTrack>>? _queueSub;
  StreamSubscription<BaseTrack?>? _trackSub;
  StreamSubscription<FavoriteChangedEvent>? _favoriteSub;

  FavoritesPlugin? get _favorites =>
      widget.pluginManager.bundled<FavoritesPlugin>(onlyEnabled: true);

  /// Looked up by interface, not by concrete plugin type — whatever is
  /// currently registered as `IPlayHistoryProvider` (today, always
  /// `ScrobblePlugin`) answers "recently played"/"most played" without
  /// this page needing to know that.
  IPlayHistoryProvider? get _playHistory =>
      widget.pluginManager.services.get<IPlayHistoryProvider>();

  @override
  void initState() {
    super.initState();
    _load();
    _queueSub = widget.engine.queueStream.listen((_) {
      if (mounted) setState(() {});
    });
    _trackSub = widget.engine.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
    // Toggling a favorite happens on the Library page — kept alive
    // alongside this one in HomePage's IndexedStack, not disposed and
    // rebuilt — so without this, the "Favorites" smart list here only
    // ever caught up the next time something unrelated triggered a
    // rebuild. Proof that the event bus (`PluginManager.events`) actually
    // decouples two pages that don't otherwise know about each other.
    _favoriteSub = widget.pluginManager.events.on<FavoriteChangedEvent>().listen((_) {
      if (mounted) setState(() {});
    });
    // A tag edit, scan, or delete on the Library page previously left
    // _libraryTracks stale here indefinitely — nothing reloaded it after
    // the first initState call, since this page (like Home) stays alive
    // in HomePage's IndexedStack rather than being rebuilt. _load() is
    // cheap now that LibraryRepository caches in memory, so reloading on
    // every save elsewhere is fine.
    LibraryRepository.instance.addListener(_load);
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _trackSub?.cancel();
    _favoriteSub?.cancel();
    LibraryRepository.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final playlists = await PlaylistStore.instance.load();
    final folderData = await PlaylistFolderStore.instance.load();
    final tracks = await LibraryRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _folderData = folderData;
      _libraryTracks = tracks;
      _loading = false;
    });
  }

  Future<void> _savePlaylists() => PlaylistStore.instance.save(_playlists);

  Future<void> _saveFolders() => PlaylistFolderStore.instance.save(_folderData);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Exports [playlist] as an M3U8 file via the platform's save dialog.
  /// `file_picker`'s `saveFile` writes the bytes itself on Android/iOS
  /// (required there); on desktop it only returns the chosen path, so
  /// this writes the file itself in that case.
  Future<void> _exportPlaylist(Playlist playlist) async {
    final result = PlaylistStore.instance.exportM3U(playlist, _libraryTracks);
    final bytes = Uint8List.fromList(utf8.encode(result.content));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlist',
      fileName: '$safeName.m3u8',
      type: FileType.custom,
      allowedExtensions: ['m3u8', 'm3u'],
      bytes: bytes,
    );
    if (path == null) return;
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes);
    }
    _snack(result.skippedCount == 0
        ? 'Exported ${result.writtenCount} tracks.'
        : 'Exported ${result.writtenCount} tracks '
            '(${result.skippedCount} skipped — not in your local library).');
  }

  /// Imports an M3U/M3U8 file, matching its entries against the current
  /// library, and adds the result as a new playlist.
  Future<void> _importM3U() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;

    String? content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null || !mounted) return;

    final defaultName =
        file.name.replaceAll(RegExp(r'\.m3u8?$', caseSensitive: false), '');
    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import playlist'),
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
            child: const Text('Import'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;

    final result = PlaylistStore.instance
        .importM3U(content, _libraryTracks, name: trimmed);
    setState(() {
      _playlists = [..._playlists, result.playlist];
    });
    await _savePlaylists();
    _snack(result.skippedCount == 0
        ? 'Imported ${result.matchedCount} tracks.'
        : 'Imported ${result.matchedCount} tracks '
            '(${result.skippedCount} not found in your library).');
  }

  BaseTrack? _trackById(String id) {
    for (final t in _libraryTracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Resolves a playlist's track ids against the current library, in
  /// order, silently skipping ids that no longer resolve (deleted file) —
  /// see [Playlist.trackIds]' doc for why ids aren't dropped from storage
  /// just because they don't resolve *right now*.
  List<BaseTrack> _resolve(List<String> ids) {
    final result = <BaseTrack>[];
    for (final id in ids) {
      final track = _trackById(id);
      if (track != null) result.add(track);
    }
    return result;
  }

  Future<void> _createPlaylist() async {
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
    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      trackIds: const [],
      createdAt: DateTime.now(),
    );
    setState(() {
      _playlists = [..._playlists, playlist];
      _openPlaylist = playlist;
    });
    await _savePlaylists();
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename playlist'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    final updated = playlist.copyWith(name: trimmed);
    setState(() {
      _playlists =
          _playlists.map((p) => p.id == playlist.id ? updated : p).toList();
      if (_openPlaylist?.id == playlist.id) _openPlaylist = updated;
    });
    await _savePlaylists();
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"${playlist.name}" will be deleted. Tracks stay in '
            'your library — only the playlist itself is removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final hadFolderAssignment = _folderData.assignments.containsKey(playlist.id);
    setState(() {
      _playlists = _playlists.where((p) => p.id != playlist.id).toList();
      if (_openPlaylist?.id == playlist.id) _openPlaylist = null;
      if (hadFolderAssignment) {
        final assignments = Map<String, String>.from(_folderData.assignments)
          ..remove(playlist.id);
        _folderData =
            PlaylistFolderData(folders: _folderData.folders, assignments: assignments);
      }
    });
    await _savePlaylists();
    if (hadFolderAssignment) await _saveFolders();
  }

  Future<PlaylistFolder?> _promptNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
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
    if (trimmed == null || trimmed.isEmpty) return null;
    return PlaylistFolder(
        id: 'folder_${DateTime.now().microsecondsSinceEpoch}', name: trimmed);
  }

  Future<void> _createFolder() async {
    final folder = await _promptNewFolder();
    if (folder == null || !mounted) return;
    setState(() {
      _folderData = PlaylistFolderData(
        folders: [..._folderData.folders, folder],
        assignments: _folderData.assignments,
      );
    });
    await _saveFolders();
  }

  Future<void> _renameFolder(PlaylistFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    setState(() {
      _folderData = PlaylistFolderData(
        folders: _folderData.folders
            .map((f) => f.id == folder.id ? f.copyWith(name: trimmed) : f)
            .toList(),
        assignments: _folderData.assignments,
      );
    });
    await _saveFolders();
  }

  Future<void> _deleteFolder(PlaylistFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text('"${folder.name}" will be deleted. Playlists inside '
            'it are not deleted — they move back to the unsorted list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      final assignments = Map<String, String>.from(_folderData.assignments)
        ..removeWhere((_, folderId) => folderId == folder.id);
      _folderData = PlaylistFolderData(
        folders: _folderData.folders.where((f) => f.id != folder.id).toList(),
        assignments: assignments,
      );
    });
    await _saveFolders();
  }

  /// Lets the user assign [playlist] to an existing folder, "No folder",
  /// or a brand new one created on the spot — a `SimpleDialog` list
  /// rather than a full picker page, matching this app's existing
  /// lightweight-dialog convention for playlist create/rename.
  Future<void> _moveToFolder(Playlist playlist) async {
    final currentFolderId = _folderData.assignments[playlist.id];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: Row(
              children: [
                Icon(
                  currentFolderId == null ? Icons.check : null,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text('No folder'),
              ],
            ),
          ),
          for (final folder in _folderData.folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder.id),
              child: Row(
                children: [
                  Icon(
                    currentFolderId == folder.id ? Icons.check : null,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(folder.name, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          const Divider(height: 1),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__new__'),
            child: const Row(
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: 8),
                Text('New folder…'),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;

    PlaylistFolder? newFolder;
    if (selected == '__new__') {
      newFolder = await _promptNewFolder();
      if (newFolder == null || !mounted) return;
    }

    setState(() {
      final assignments = Map<String, String>.from(_folderData.assignments);
      final folders = newFolder == null
          ? _folderData.folders
          : [..._folderData.folders, newFolder];
      if (newFolder != null) {
        assignments[playlist.id] = newFolder.id;
      } else if (selected.isEmpty) {
        assignments.remove(playlist.id);
      } else {
        assignments[playlist.id] = selected;
      }
      _folderData = PlaylistFolderData(folders: folders, assignments: assignments);
    });
    await _saveFolders();
  }

  Future<void> _removeFromPlaylist(Playlist playlist, String trackId) async {
    final updated = playlist.copyWith(
        trackIds: playlist.trackIds.where((id) => id != trackId).toList());
    setState(() {
      _playlists =
          _playlists.map((p) => p.id == playlist.id ? updated : p).toList();
      _openPlaylist = updated;
    });
    await _savePlaylists();
  }

  Future<void> _reorderPlaylist(
      Playlist playlist, int oldIndex, int newIndex) async {
    OmnisHaptics.selectionClick();
    final ids = List<String>.from(playlist.trackIds);
    if (newIndex > oldIndex) newIndex -= 1;
    final id = ids.removeAt(oldIndex);
    ids.insert(newIndex, id);
    final updated = playlist.copyWith(trackIds: ids);
    setState(() {
      _playlists =
          _playlists.map((p) => p.id == playlist.id ? updated : p).toList();
      _openPlaylist = updated;
    });
    await _savePlaylists();
  }

  Future<void> _playAll(List<BaseTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    await widget.engine.setQueue(tracks, startIndex: startIndex);
    await widget.engine.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final openPlaylist = _openPlaylist;
    if (openPlaylist != null) {
      // Always render the freshest copy in case it was edited underneath.
      final current = _playlists.firstWhere((p) => p.id == openPlaylist.id,
          orElse: () => openPlaylist);
      return _buildPlaylistDetail(current);
    }
    if (_openSmart != null) {
      return _buildSmartDetail(_openSmart!);
    }
    return _buildIndex();
  }

  Widget _buildIndex() {
    final theme = Theme.of(context);
    final queue = widget.engine.queue;
    final favorites = _favorites?.favoritesFrom(_libraryTracks) ?? const [];
    final scrobble = _playHistory;
    final recentCount = scrobble?.recentlyPlayed().length ?? 0;
    final mostPlayedCount = scrobble?.mostPlayedIds().length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import M3U playlist',
            onPressed: _importM3U,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: _createFolder,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New playlist',
            onPressed: _createPlaylist,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: const Text('Current queue'),
              subtitle: Text('${queue.length} tracks'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _openSmart = _SmartList.queue),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.favorite)),
              title: const Text('Favorites'),
              subtitle: Text('${favorites.length} tracks'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _openSmart = _SmartList.favorites),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.history)),
              title: const Text('Recently played'),
              subtitle: Text('$recentCount tracks'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _openSmart = _SmartList.recent),
            ),
          ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.trending_up)),
              title: const Text('Most played'),
              subtitle: Text('$mostPlayedCount tracks'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _openSmart = _SmartList.mostPlayed),
            ),
          ),
          const SizedBox(height: 16),
          Text('Your playlists', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_playlists.isEmpty && _folderData.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.playlist_add,
                        size: 56, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text('No playlists yet.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _createPlaylist,
                      icon: const Icon(Icons.add),
                      label: const Text('New playlist'),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._buildGroupedPlaylists(theme),
        ],
      ),
    );
  }

  /// Playlists grouped under whichever folder each is assigned to
  /// (`_folderData.assignments`), in [_folderData.folders]' own order,
  /// followed by an "Unsorted" section for the rest — only shown when at
  /// least one real folder exists, so a user who's never created one
  /// sees the exact same flat list this page always rendered, zero
  /// visual change from before folders existed at all.
  List<Widget> _buildGroupedPlaylists(ThemeData theme) {
    if (_folderData.folders.isEmpty) {
      return _playlists.map(_playlistTile).toList();
    }
    final widgets = <Widget>[];
    for (final folder in _folderData.folders) {
      final inFolder = _playlists
          .where((p) => _folderData.assignments[p.id] == folder.id)
          .toList();
      widgets.add(_folderHeader(theme, folder, inFolder.length));
      widgets.addAll(inFolder.map(_playlistTile));
    }
    final unsorted = _playlists
        .where((p) => !_folderData.assignments.containsKey(p.id))
        .toList();
    if (unsorted.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('Unsorted', style: theme.textTheme.titleSmall),
      ));
      widgets.addAll(unsorted.map(_playlistTile));
    }
    return widgets;
  }

  Widget _folderHeader(ThemeData theme, PlaylistFolder folder, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.folder_outlined,
              size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${folder.name} ($count)',
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          ),
          PopupMenuButton<String>(
            tooltip: 'Folder options',
            onSelected: (value) {
              if (value == 'rename') _renameFolder(folder);
              if (value == 'delete') _deleteFolder(folder);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename folder')),
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playlistTile(Playlist playlist) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.queue_music)),
        title: Text(playlist.name),
        subtitle: Text('${playlist.trackIds.length} tracks'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'rename') _renamePlaylist(playlist);
            if (value == 'move') _moveToFolder(playlist);
            if (value == 'export') _exportPlaylist(playlist);
            if (value == 'delete') _deletePlaylist(playlist);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            PopupMenuItem(value: 'export', child: Text('Export as M3U')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => setState(() => _openPlaylist = playlist),
      ),
    );
  }

  Widget _buildPlaylistDetail(Playlist playlist) {
    final theme = Theme.of(context);
    final tracks = _resolve(playlist.trackIds);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _openPlaylist = null),
        ),
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play all',
            onPressed: tracks.isEmpty ? null : () => _playAll(tracks),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _renamePlaylist(playlist);
              if (value == 'move') _moveToFolder(playlist);
              if (value == 'export') _exportPlaylist(playlist);
              if (value == 'delete') _deletePlaylist(playlist);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder…')),
              PopupMenuItem(
                  value: 'export', child: Text('Export as M3U')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child: Text('No tracks in this playlist yet.',
                  style: theme.textTheme.bodyMedium),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: tracks.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderPlaylist(playlist, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return ListTile(
                  key: ValueKey(track.id),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TrackArtwork(
                        track: track, width: 44, height: 44, iconSize: 20),
                  ),
                  title: Text(track.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(track.artists.join(', '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove from playlist',
                    onPressed: () => _removeFromPlaylist(playlist, track.id),
                  ),
                  onTap: () => _playAll(tracks, startIndex: index),
                );
              },
            ),
    );
  }

  Widget _buildSmartDetail(_SmartList kind) {
    final theme = Theme.of(context);
    final scrobble = _playHistory;

    final (title, tracks, subtitles) = switch (kind) {
      _SmartList.queue => (
          'Current queue',
          widget.engine.queue,
          <String, String>{}
        ),
      _SmartList.favorites => (
          'Favorites',
          _favorites?.favoritesFrom(_libraryTracks) ?? const <BaseTrack>[],
          <String, String>{},
        ),
      _SmartList.recent => (
          'Recently played',
          (scrobble?.recentlyPlayed() ?? const <PlayRecord>[])
              .map((r) => _trackById(r.trackId))
              .whereType<BaseTrack>()
              .toList(),
          <String, String>{},
        ),
      _SmartList.mostPlayed => (
          'Most played',
          (scrobble?.mostPlayedIds() ?? const <MapEntry<String, int>>[])
              .map((e) => _trackById(e.key))
              .whereType<BaseTrack>()
              .toList(),
          {
            for (final e
                in scrobble?.mostPlayedIds() ?? const <MapEntry<String, int>>[])
              if (_trackById(e.key) != null)
                e.key: '${e.value} play${e.value == 1 ? '' : 's'}',
          },
        ),
    };

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _openSmart = null),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play all',
            onPressed: tracks.isEmpty ? null : () => _playAll(tracks),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(
              child:
                  Text('Nothing here yet.', style: theme.textTheme.bodyMedium))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isCurrent = widget.engine.currentTrack?.id == track.id;
                return Dismissible(
                  key: ValueKey('${kind.name}:${track.id}:$index'),
                  direction: kind == _SmartList.queue
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: const ColoredBox(
                    color: Colors.transparent,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Icon(Icons.delete),
                      ),
                    ),
                  ),
                  onDismissed: kind == _SmartList.queue
                      ? (_) => widget.engine.removeTrack(index)
                      : null,
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: TrackArtwork(
                          track: track, width: 44, height: 44, iconSize: 20),
                    ),
                    title: Text(track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        subtitles[track.id] ?? track.artists.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    selected: isCurrent,
                    trailing: isCurrent
                        ? Icon(Icons.graphic_eq, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => kind == _SmartList.queue
                        ? widget.engine.playAt(index)
                        : _playAll(tracks, startIndex: index),
                  ),
                );
              },
            ),
    );
  }
}
