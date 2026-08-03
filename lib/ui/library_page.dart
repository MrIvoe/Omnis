import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/media_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

enum LibraryViewMode { songs, artists, genres }

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

/// Library screen — pick local audio files and play them.
class LibraryPage extends StatefulWidget {
  final AudioEngine engine;

  const LibraryPage({super.key, required this.engine});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<BaseTrack> _tracks = [];
  bool _loading = false;
  bool _loadedFromDisk = false;
  String? _error;
  LibraryViewMode _viewMode = LibraryViewMode.songs;
  bool _showAlbums = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedLibrary();
  }

  /// Load the previously-scanned library from disk so the user doesn't
  /// have to rescan (and re-grant permission) on every app launch.
  Future<void> _loadPersistedLibrary() async {
    final saved = await LibraryStore.instance.load();
    if (!mounted) return;
    setState(() {
      _tracks = saved;
      _loadedFromDisk = true;
    });
    if (saved.isNotEmpty) {
      await widget.engine.setQueue(saved);
    }
  }

  static const _audioExtensions = [
    'mp3',
    'm4a',
    'wav',
    'flac',
    'aac',
    'ogg',
    'opus'
  ];

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
      setState(() => _tracks = [..._tracks, ...scanned]);
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

  /// Returns the correct root directory for a "whole phone" scan.
  ///
  /// - Android: /storage/emulated/0 (external storage)
  /// - iOS: app documents (sandboxed)
  /// - Desktop: user home directory
  Future<Directory?> _platformRoot() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      // Android external storage root — the whole phone's music.
      // getExternalStorageDirectory() returns the app-specific dir, which
      // is NOT what we want for a "whole phone" scan.
      final root = Directory('/storage/emulated/0');
      if (root.existsSync()) return root;
      final external = await getExternalStorageDirectory();
      return external;
    }
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return docs;
    }
    // Desktop (Windows/Linux/macOS): user home.
    return Directory(Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.');
  }

  Future<void> _playTrack(BaseTrack track) async {
    final index = _tracks.indexWhere((candidate) => candidate.id == track.id);
    if (index < 0) return;
    await widget.engine.setQueue(_tracks, startIndex: index);
    await widget.engine.playAt(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = buildLibrarySections(_tracks,
        viewMode: _viewMode, showAlbums: _showAlbums);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.audio_file),
            tooltip: 'Add audio files',
            onPressed: _loading ? null : _pickAndAdd,
          ),
        ],
      ),
      body: _loading
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
                          child: Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<LibraryViewMode>(
                                  segments: const [
                                    ButtonSegment(
                                        value: LibraryViewMode.songs,
                                        label: Text('Songs'),
                                        icon: Icon(Icons.music_note)),
                                    ButtonSegment(
                                        value: LibraryViewMode.artists,
                                        label: Text('Artists'),
                                        icon: Icon(Icons.person)),
                                    ButtonSegment(
                                        value: LibraryViewMode.genres,
                                        label: Text('Genres'),
                                        icon: Icon(Icons.tag)),
                                  ],
                                  selected: {_viewMode},
                                  onSelectionChanged: (value) {
                                    setState(() => _viewMode = value.first);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilterChip(
                                label: const Text('Albums'),
                                selected: _showAlbums,
                                onSelected: (value) =>
                                    setState(() => _showAlbums = value),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: sections.length,
                            itemBuilder: (context, index) {
                              final section = sections[index];
                              return _buildSection(section, depth: 0);
                            },
                          ),
                        ),
                      ],
                    ),
    );
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
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.music_note)),
            title:
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_subtitle(track)),
            trailing: _currentTrackIcon(track),
            onTap: () => _playTrack(track),
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
    return parts.isEmpty ? 'No metadata' : parts.join(' • ');
  }
}
