import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/forgotten_tracks.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/play_history_store.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';

/// Spec §37 / item 39's "Forgotten Music" browsing page — a real,
/// browsable list of every owned track not heard within a threshold
/// ("147 tracks you haven't heard in 6+ months"), not just a queue-only
/// preset. `QueuePresetPlugin`'s "Forgotten Favorites" mood tile only
/// ever considers a listener's top-N *most played* tracks and builds a
/// queue directly with no list view at all; this covers every owned
/// track — including ones barely played, or never played — and lets a
/// listener actually see and browse what it found before playing.
class ForgottenMusicPage extends StatefulWidget {
  final AudioEngine engine;

  const ForgottenMusicPage({super.key, required this.engine});

  @override
  State<ForgottenMusicPage> createState() => _ForgottenMusicPageState();
}

class _ForgottenMusicPageState extends State<ForgottenMusicPage> {
  static const _thresholds = [
    Duration(days: 30),
    Duration(days: 90),
    Duration(days: 180),
    Duration(days: 365),
  ];

  bool _loading = true;
  List<BaseTrack> _tracks = const [];
  Map<String, DateTime> _lastPlayed = const {};
  Duration _threshold = const Duration(days: 180);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracks = await LibraryRepository.instance.load();
    final lastPlayed = await PlayHistoryStore.instance.lastPlayedByTrackId();
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _lastPlayed = lastPlayed;
      _loading = false;
    });
  }

  List<BaseTrack> get _forgotten =>
      findForgottenTracks(_tracks, _lastPlayed, threshold: _threshold);

  String get _thresholdLabel {
    final days = _threshold.inDays;
    if (days == 30) return '1 month';
    if (days == 365) return '1 year';
    return '${days ~/ 30} months';
  }

  Future<void> _play(List<BaseTrack> tracks, {int startIndex = 0}) async {
    await widget.engine.setQueue(tracks, startIndex: startIndex);
    await widget.engine.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forgotten = _forgotten;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgotten Music'),
        actions: [
          PopupMenuButton<Duration>(
            tooltip: 'Not heard in…',
            initialValue: _threshold,
            onSelected: (value) => setState(() => _threshold = value),
            itemBuilder: (context) => _thresholds
                .map((d) => PopupMenuItem(
                      value: d,
                      child: Text(d.inDays == 30
                          ? '1 month'
                          : d.inDays == 365
                              ? '1 year'
                              : '${d.inDays ~/ 30} months'),
                    ))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play all',
            onPressed: forgotten.isEmpty ? null : () => _play(forgotten),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      forgotten.isEmpty
                          ? 'Nothing forgotten — every track has been '
                              'played within the last $_thresholdLabel.'
                          : '${forgotten.length} track'
                              '${forgotten.length == 1 ? '' : 's'} you '
                              'haven\'t heard in $_thresholdLabel+',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                Expanded(
                  child: forgotten.isEmpty
                      ? Center(
                          child: Text('Nothing here yet.',
                              style: theme.textTheme.bodyMedium),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: forgotten.length,
                          itemBuilder: (context, index) {
                            final track = forgotten[index];
                            final lastPlayed = _lastPlayed[track.id];
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: TrackArtwork(
                                    track: track,
                                    width: 44,
                                    height: 44,
                                    iconSize: 20),
                              ),
                              title: Text(track.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                lastPlayed == null
                                    ? '${track.artists.join(', ')} · never '
                                        'played'
                                    : '${track.artists.join(', ')} · last '
                                        'played ${_formatDate(lastPlayed)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () =>
                                  _play(forgotten, startIndex: index),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
