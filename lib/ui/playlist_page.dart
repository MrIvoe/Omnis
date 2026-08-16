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
import 'package:omnis/core/queue_history_store.dart';
import 'package:omnis/core/queue_operations.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:omnis_plugins/smart_playlist_plugin.dart';
import 'package:omnis_plugins/smart_playlist_rule.dart';
import 'package:omnis/ui/plugin_settings_page.dart';
import 'package:omnis/ui/queue_history_page.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// The four always-present "smart" entries shown above the user's real
/// playlists — computed live from other plugins/the engine rather than
/// stored playlist data, the same idea as Spotify's Liked Songs or
/// Musicolet's "top rated"/most-played lists.
enum _SmartList { queue, favorites, recent, mostPlayed }

/// A distinct type (not `PopupMenuButton<String>`, same as every
/// rename/move/export/delete menu on this page) deliberately — existing
/// widget tests locate a playlist row's own menu via
/// `find.byType(PopupMenuButton<String>).last`, which would silently
/// start resolving to this AppBar menu instead once it existed, since
/// both share the same generic type otherwise.
enum _ImportFormat { m3u, pls, xspf }

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

  SmartPlaylistPlugin? get _smartPlaylists =>
      widget.pluginManager.bundled<SmartPlaylistPlugin>(onlyEnabled: true);

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

  /// Same shape as [_exportPlaylist], PLS instead of M3U8 — item 13's
  /// "XSPF/PLS import/export" gap, PLS half.
  Future<void> _exportPlaylistPls(Playlist playlist) async {
    final result = PlaylistStore.instance.exportPLS(playlist, _libraryTracks);
    final bytes = Uint8List.fromList(utf8.encode(result.content));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlist',
      fileName: '$safeName.pls',
      type: FileType.custom,
      allowedExtensions: ['pls'],
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

  /// Same shape as [_exportPlaylist]/[_exportPlaylistPls], XSPF instead
  /// — item 13's "XSPF/PLS import/export" gap, XSPF half.
  Future<void> _exportPlaylistXspf(Playlist playlist) async {
    final result = PlaylistStore.instance.exportXSPF(playlist, _libraryTracks);
    final bytes = Uint8List.fromList(utf8.encode(result.content));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlist',
      fileName: '$safeName.xspf',
      type: FileType.custom,
      allowedExtensions: ['xspf'],
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

  /// Same shape as [_exportPlaylist]/[_exportPlaylistPls]/
  /// [_exportPlaylistXspf], CSV instead — §46's "CSV/JSON export" gap.
  /// No import counterpart: unlike M3U/PLS/XSPF (playback formats a
  /// player opens), CSV/JSON are spreadsheet/interchange exports the
  /// comparison doc only ever asks for one direction of.
  Future<void> _exportPlaylistCsv(Playlist playlist) async {
    final result = PlaylistStore.instance.exportCSV(playlist, _libraryTracks);
    final bytes = Uint8List.fromList(utf8.encode(result.content));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlist',
      fileName: '$safeName.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
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

  /// Same shape as [_exportPlaylistCsv], JSON instead — §46's "CSV/JSON
  /// export" gap, JSON half.
  Future<void> _exportPlaylistJson(Playlist playlist) async {
    final result = PlaylistStore.instance.exportJSON(playlist, _libraryTracks);
    final bytes = Uint8List.fromList(utf8.encode(result.content));
    final safeName = playlist.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export playlist',
      fileName: '$safeName.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
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

  /// Same shape as [_importM3U], PLS instead of M3U/M3U8 — item 13's
  /// "XSPF/PLS import/export" gap, PLS half.
  Future<void> _importPLS() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pls'],
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
        file.name.replaceAll(RegExp(r'\.pls$', caseSensitive: false), '');
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
        .importPLS(content, _libraryTracks, name: trimmed);
    setState(() {
      _playlists = [..._playlists, result.playlist];
    });
    await _savePlaylists();
    _snack(result.skippedCount == 0
        ? 'Imported ${result.matchedCount} tracks.'
        : 'Imported ${result.matchedCount} tracks '
            '(${result.skippedCount} not found in your library).');
  }

  /// Same shape as [_importM3U]/[_importPLS], XSPF instead — item 13's
  /// "XSPF/PLS import/export" gap, XSPF half.
  Future<void> _importXSPF() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xspf'],
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
        file.name.replaceAll(RegExp(r'\.xspf$', caseSensitive: false), '');
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
        .importXSPF(content, _libraryTracks, name: trimmed);
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

  /// Saves the current queue as a user-named, permanently-kept
  /// [QueueHistoryEntry] (spec §7's "Queue snapshots") — distinct from
  /// the automatic rolling history `MainCore` already records on every
  /// real queue change.
  Future<void> _saveQueueSnapshot(List<BaseTrack> tracks) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save queue as snapshot'),
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
    await QueueHistoryStore.instance.saveSnapshot(trimmed, tracks);
    if (!mounted) return;
    _snack('Saved "$trimmed".');
  }

  /// Turns the live queue into a real persistent [Playlist] via the same
  /// [PlaylistStore] every other playlist already uses — distinct from
  /// [_saveQueueSnapshot], which saves to the ephemeral, history-scoped
  /// [QueueHistoryStore] instead.
  Future<void> _saveQueueAsPlaylist(List<BaseTrack> tracks) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save queue as playlist'),
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
    final playlist = Playlist(
      id: 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      trackIds: tracks.map((t) => t.id).toList(),
      createdAt: DateTime.now(),
    );
    setState(() => _playlists = [..._playlists, playlist]);
    await _savePlaylists();
    if (!mounted) return;
    _snack('Saved "$trimmed".');
  }

  /// Removes duplicate tracks from the live queue (by id), keeping the
  /// first occurrence of each and never disturbing whatever's currently
  /// playing. Removes highest-index-first so earlier indices don't shift
  /// out from under later removals.
  Future<void> _removeDuplicatesFromQueue() async {
    final indices = QueueOperations.duplicateIndicesToRemove(
      widget.engine.queue,
      currentIndex: widget.engine.currentIndex,
    );
    if (indices.isEmpty) {
      _snack('No duplicates in the queue.');
      return;
    }
    for (final index in indices) {
      await widget.engine.removeTrack(index);
    }
    if (!mounted) return;
    setState(() {});
    _snack('Removed ${indices.length} duplicate'
        '${indices.length == 1 ? '' : 's'}.');
  }

  /// Removes every track before the currently-playing one from the live
  /// queue.
  Future<void> _clearPlayedFromQueue() async {
    final indices = QueueOperations.playedIndicesToRemove(
      widget.engine.queue,
      widget.engine.currentIndex,
    );
    if (indices.isEmpty) {
      _snack('Nothing played to clear.');
      return;
    }
    for (final index in indices) {
      await widget.engine.removeTrack(index);
    }
    if (!mounted) return;
    setState(() {});
    _snack('Cleared ${indices.length} played track'
        '${indices.length == 1 ? '' : 's'}.');
  }

  /// Drag-reorders the live queue — same `(oldIndex, newIndex)` handoff
  /// [_reorderPlaylist] already uses for a saved playlist, except
  /// [AudioEngine.moveTrack] does its own Flutter-convention index
  /// adjustment internally (via `QueueOperations.reorder`), so unlike
  /// [_reorderPlaylist] the raw values are passed straight through here.
  Future<void> _reorderQueue(int oldIndex, int newIndex) async {
    OmnisHaptics.selectionClick();
    await widget.engine.moveTrack(oldIndex, newIndex);
    if (!mounted) return;
    setState(() {});
  }

  /// Shuffles everything after the currently-playing track, leaving
  /// what's already played and what's playing now untouched.
  Future<void> _shuffleRemainingQueue() async {
    await widget.engine.shuffleRemaining();
    if (!mounted) return;
    setState(() {});
  }

  /// Moves a queue track to the very front, ahead of everything else.
  /// Whatever's currently playing keeps playing uninterrupted — only its
  /// index may change, never its identity — since `AudioEngine.moveTrack`
  /// reorders in place rather than restarting playback.
  Future<void> _moveQueueTrackToTop(int index) async {
    if (index <= 0) return;
    await widget.engine.moveTrack(index, 0);
    if (!mounted) return;
    setState(() {});
  }

  /// Builds [rule]'s membership fresh against the current library and
  /// plays it — the same `buildQueueForRule` + `setQueue` + `play`
  /// sequence `SmartPlaylistPlugin`'s own settings page already uses for
  /// its "play" action, just reached from here too now.
  Future<void> _playSmartPlaylist(
      SmartPlaylistPlugin plugin, SmartPlaylistRule rule) async {
    final queue = plugin.buildQueueForRule(_libraryTracks, rule.id);
    if (queue.isEmpty) {
      _snack('"${rule.name}" has no matching tracks right now.');
      return;
    }
    await widget.engine.setQueue(queue);
    await widget.engine.play();
  }

  Future<void> _deleteSmartPlaylist(
      SmartPlaylistPlugin plugin, String ruleId) async {
    await plugin.deleteRule(ruleId);
    if (mounted) setState(() {});
  }

  /// Deep-links to the plugin's own settings page for create/edit —
  /// deliberately not a second rule builder duplicated on this page.
  /// Refreshes on return since a rule may have been added/edited/
  /// deleted there.
  Future<void> _manageSmartPlaylists() async {
    final managed = widget.pluginManager.byId('smart_playlist');
    if (managed == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => PluginSettingsPage(
        pluginManager: widget.pluginManager,
        plugin: managed,
      ),
    ));
    if (mounted) setState(() {});
  }

  String _smartPlaylistSubtitle(SmartPlaylistRule rule) {
    final count = rule.conditions.length;
    return '${rule.matchType.name.toUpperCase()} of $count condition${count == 1 ? '' : 's'}';
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
    final favorites = _favorites?.favoritesWithSnapshots(_libraryTracks) ?? const [];
    final scrobble = _playHistory;
    final recentCount = scrobble?.recentlyPlayed().length ?? 0;
    final mostPlayedCount = scrobble?.mostPlayedIds().length ?? 0;
    final smartPlaylistPlugin = _smartPlaylists;
    final smartRules = smartPlaylistPlugin?.savedRules ?? const <SmartPlaylistRule>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          PopupMenuButton<_ImportFormat>(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import playlist',
            onSelected: (value) {
              if (value == _ImportFormat.m3u) _importM3U();
              if (value == _ImportFormat.pls) _importPLS();
              if (value == _ImportFormat.xspf) _importXSPF();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: _ImportFormat.m3u, child: Text('Import M3U…')),
              PopupMenuItem(
                  value: _ImportFormat.pls, child: Text('Import PLS…')),
              PopupMenuItem(
                  value: _ImportFormat.xspf, child: Text('Import XSPF…')),
            ],
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
              leading: const CircleAvatar(child: Icon(Icons.restore)),
              title: const Text('Queue history'),
              subtitle: const Text('Past queues and saved snapshots'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => QueueHistoryPage(engine: widget.engine),
              )),
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
          if (smartPlaylistPlugin != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Smart playlists', style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: _manageSmartPlaylists,
                  child: const Text('Manage'),
                ),
              ],
            ),
            if (smartRules.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No smart playlists yet — create one in Smart Playlists '
                  'settings.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final rule in smartRules)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.auto_awesome)),
                    title: Text(rule.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_smartPlaylistSubtitle(rule)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () =>
                          _deleteSmartPlaylist(smartPlaylistPlugin, rule.id),
                    ),
                    onTap: () =>
                        _playSmartPlaylist(smartPlaylistPlugin, rule),
                  ),
                ),
          ],
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
            if (value == 'export_pls') _exportPlaylistPls(playlist);
            if (value == 'export_xspf') _exportPlaylistXspf(playlist);
            if (value == 'export_csv') _exportPlaylistCsv(playlist);
            if (value == 'export_json') _exportPlaylistJson(playlist);
            if (value == 'delete') _deletePlaylist(playlist);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            PopupMenuItem(value: 'export', child: Text('Export as M3U')),
            PopupMenuItem(value: 'export_pls', child: Text('Export as PLS')),
            PopupMenuItem(value: 'export_xspf', child: Text('Export as XSPF')),
            PopupMenuItem(value: 'export_csv', child: Text('Export as CSV')),
            PopupMenuItem(value: 'export_json', child: Text('Export as JSON')),
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
              if (value == 'export_pls') _exportPlaylistPls(playlist);
              if (value == 'export_xspf') _exportPlaylistXspf(playlist);
              if (value == 'export_csv') _exportPlaylistCsv(playlist);
              if (value == 'export_json') _exportPlaylistJson(playlist);
              if (value == 'delete') _deletePlaylist(playlist);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder…')),
              PopupMenuItem(
                  value: 'export', child: Text('Export as M3U')),
              PopupMenuItem(
                  value: 'export_pls', child: Text('Export as PLS')),
              PopupMenuItem(
                  value: 'export_xspf', child: Text('Export as XSPF')),
              PopupMenuItem(
                  value: 'export_csv', child: Text('Export as CSV')),
              PopupMenuItem(
                  value: 'export_json', child: Text('Export as JSON')),
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
          _favorites?.favoritesWithSnapshots(_libraryTracks) ?? const <BaseTrack>[],
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

    final isQueue = kind == _SmartList.queue;

    Widget buildTile(BuildContext context, int index) {
      final track = tracks[index];
      final isCurrent = widget.engine.currentTrack?.id == track.id;
      return Dismissible(
        key: ValueKey('${kind.name}:${track.id}:$index'),
        direction: isQueue ? DismissDirection.endToStart : DismissDirection.none,
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
        onDismissed: isQueue ? (_) => widget.engine.removeTrack(index) : null,
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TrackArtwork(
                track: track, width: 44, height: 44, iconSize: 20),
          ),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitles[track.id] ?? track.artists.join(', '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: isCurrent,
          trailing: !isQueue
              ? (isCurrent
                  ? Icon(Icons.graphic_eq, color: theme.colorScheme.primary)
                  : null)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.graphic_eq,
                            color: theme.colorScheme.primary),
                      ),
                    if (index > 0)
                      IconButton(
                        icon: const Icon(Icons.vertical_align_top),
                        tooltip: 'Move to top',
                        onPressed: () => _moveQueueTrackToTop(index),
                      ),
                  ],
                ),
          onTap: () => isQueue
              ? widget.engine.playAt(index)
              : _playAll(tracks, startIndex: index),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _openSmart = null),
        ),
        title: Text(title),
        actions: [
          if (isQueue)
            PopupMenuButton<String>(
              tooltip: 'Queue actions',
              enabled: tracks.isNotEmpty,
              onSelected: (value) {
                switch (value) {
                  case 'snapshot':
                    _saveQueueSnapshot(tracks);
                  case 'save_playlist':
                    _saveQueueAsPlaylist(tracks);
                  case 'remove_duplicates':
                    _removeDuplicatesFromQueue();
                  case 'clear_played':
                    _clearPlayedFromQueue();
                  case 'shuffle_remaining':
                    _shuffleRemainingQueue();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                    value: 'snapshot', child: Text('Save as snapshot')),
                PopupMenuItem(
                    value: 'save_playlist',
                    child: Text('Save as playlist')),
                PopupMenuItem(
                    value: 'remove_duplicates',
                    child: Text('Remove duplicates')),
                PopupMenuItem(
                    value: 'clear_played', child: Text('Clear played')),
                PopupMenuItem(
                    value: 'shuffle_remaining',
                    child: Text('Shuffle remaining')),
              ],
            ),
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
          : isQueue
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tracks.length,
                  onReorder: _reorderQueue,
                  itemBuilder: buildTile,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tracks.length,
                  itemBuilder: buildTile,
                ),
    );
  }
}
