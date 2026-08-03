import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';

/// Playlist-focused screen with the current queue as the primary playlist.
class PlaylistPage extends StatefulWidget {
  final AudioEngine engine;

  const PlaylistPage({super.key, required this.engine});

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queue = widget.engine.queue;

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      body: queue.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.playlist_play,
                        size: 72, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    const Text('No queued tracks yet.'),
                    const SizedBox(height: 8),
                    Text(
                      'Add songs from the Library to build a queue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.queue_music),
                    ),
                    title: const Text('Current queue'),
                    subtitle: Text('${queue.length} tracks ready to play'),
                    trailing: Icon(Icons.play_arrow,
                        color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Queue', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...queue.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value;
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(track.title),
                    subtitle: Text(_subtitle(track)),
                    trailing: widget.engine.currentIndex == index
                        ? Icon(Icons.graphic_eq,
                            color: theme.colorScheme.primary)
                        : null,
                  );
                }),
              ],
            ),
    );
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
