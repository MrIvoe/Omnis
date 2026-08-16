import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_statistics.dart';

/// Spec §35's "Library Statistics" dashboard, "Library" subsection —
/// total tracks/albums/artists/genres, duration, bitrate, lossless/
/// hi-res ratios. A point-in-time snapshot computed once from [tracks]
/// (the already-scanned library), the same "no new I/O, work from
/// what's already loaded" contract `LibraryCleanupReportPage`'s own
/// synchronous pass established.
class LibraryStatisticsPage extends StatelessWidget {
  final List<BaseTrack> tracks;

  const LibraryStatisticsPage({super.key, required this.tracks});

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final minutes = d.inMinutes.remainder(60);
    if (days > 0) return '$days d $hours h';
    if (hours > 0) return '$hours h $minutes m';
    return '$minutes m';
  }

  String _formatShortDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = LibraryStatistics.compute(tracks);

    final tiles = <(String, String)>[
      ('Tracks', '${stats.trackCount}'),
      ('Albums', '${stats.albumCount}'),
      ('Artists', '${stats.artistCount}'),
      ('Genres', '${stats.genreCount}'),
      ('Total duration', _formatDuration(stats.totalDuration)),
      if (stats.averageTrackLength != null)
        ('Average track length', _formatShortDuration(stats.averageTrackLength!)),
      if (stats.averageBitrateKbps != null)
        ('Average bitrate', '${stats.averageBitrateKbps} kbps'),
      ('Lossless tracks', '${stats.losslessCount}'),
      ('Lossy tracks', '${stats.lossyCount}'),
      ('Hi-res tracks', '${stats.hiResCount}'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Library Statistics')),
      body: tracks.isEmpty
          ? Center(
              child: Text('Your library is empty.',
                  style: theme.textTheme.bodyMedium),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tiles.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final (label, value) = tiles[index];
                return ListTile(
                  title: Text(label),
                  trailing: Text(value, style: theme.textTheme.titleMedium),
                );
              },
            ),
    );
  }
}
