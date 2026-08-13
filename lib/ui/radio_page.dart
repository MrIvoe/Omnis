import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis_plugins/radio_plugin.dart';

/// Internet Radio tab: search and browse live streaming stations via
/// `RadioPlugin` (the Radio Browser directory), and play one straight
/// through the normal queue — a station is just a [BaseTrack] with
/// `type: TrackType.radio` and a real `streamUrl`, so [AudioEngine]
/// needs no special-casing at all to play it (`AudioEngine.uriFor`
/// already plays any track with a `streamUrl`).
///
/// Shows the most-voted stations by default (before the user has typed
/// anything), the same "something to look at immediately" pattern
/// `_MoodsPage` and `HomeDashboardPage` already use elsewhere.
class RadioPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;

  const RadioPage({
    super.key,
    required this.engine,
    required this.pluginManager,
  });

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  final _searchController = TextEditingController();
  List<BaseTrack> _stations = const [];
  bool _loading = false;
  bool _searched = false;

  RadioPlugin? get _plugin =>
      widget.pluginManager.bundled<RadioPlugin>(onlyEnabled: true);

  @override
  void initState() {
    super.initState();
    _loadTopStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTopStations() async {
    final plugin = _plugin;
    if (plugin == null) return;
    setState(() => _loading = true);
    final stations = await plugin.topStations();
    if (!mounted) return;
    setState(() {
      _stations = stations;
      _loading = false;
      _searched = false;
    });
  }

  Future<void> _search(String query) async {
    final plugin = _plugin;
    if (plugin == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      await _loadTopStations();
      return;
    }
    setState(() => _loading = true);
    final stations = await plugin.searchStations(trimmed);
    if (!mounted) return;
    setState(() {
      _stations = stations;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _play(int index) async {
    await widget.engine.setQueue(_stations, startIndex: index);
    await widget.engine.play();
  }

  @override
  Widget build(BuildContext context) {
    final plugin = _plugin;
    if (plugin == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Radio')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The Internet Radio plugin is disabled in Settings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Radio')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search stations (e.g. "jazz", "BBC")',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadTopStations();
                        },
                      )
                    : null,
              ),
              onSubmitted: _search,
            ),
          ),
          if (!_loading && _stations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _searched ? 'Search results' : 'Top stations',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _stations.isEmpty
                    ? Center(
                        child: Text(
                          _searched
                              ? 'No stations found.'
                              : 'No stations available right now.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _stations.length,
                        itemBuilder: (context, index) {
                          final station = _stations[index];
                          final current = widget.engine.currentTrack;
                          final isPlaying = current?.id == station.id;
                          return ListTile(
                            leading: _StationIcon(station: station),
                            title: Text(
                              station.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (station.artists.isNotEmpty)
                                  station.artists.first,
                                if (station.genres.isNotEmpty)
                                  station.genres.take(2).join(', '),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isPlaying
                                ? const Icon(Icons.graphic_eq,
                                    color: Colors.deepPurple)
                                : const Icon(Icons.play_circle_outline),
                            onTap: () => _play(index),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// A station's favicon when it has one and it actually loads, otherwise a
/// generic radio icon — never a broken-image placeholder. Deliberately
/// separate from `ArtworkProvider`/`TrackArtwork`: those resolve *real*
/// embedded/MediaStore artwork for local/library tracks and cache decoded
/// bytes in memory, a different contract from a plain remote favicon URL
/// that `Image.network` already caches on its own.
class _StationIcon extends StatelessWidget {
  final BaseTrack station;

  const _StationIcon({required this.station});

  @override
  Widget build(BuildContext context) {
    final favicon = station.coverArt;
    const size = 40.0;
    if (favicon == null || favicon.isEmpty) {
      return const CircleAvatar(
        radius: size / 2,
        child: Icon(Icons.radio),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.network(
        favicon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const CircleAvatar(
          radius: size / 2,
          child: Icon(Icons.radio),
        ),
      ),
    );
  }
}
