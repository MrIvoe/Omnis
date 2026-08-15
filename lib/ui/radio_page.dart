import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/custom_radio_station_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
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
  List<CustomRadioStation> _customStations = const [];
  bool _loading = false;
  bool _searched = false;

  RadioPlugin? get _plugin =>
      widget.pluginManager.bundled<RadioPlugin>(onlyEnabled: true);

  FavoritesPlugin? get _favoritesPlugin =>
      widget.pluginManager.bundled<FavoritesPlugin>(onlyEnabled: true);

  bool _isFavorite(String stationId) =>
      _favoritesPlugin?.isFavorite(stationId) ?? false;

  /// [station] is passed through to [FavoritesPlugin.toggleFavorite] so a
  /// newly-favorited station gets a real snapshot captured (a station is
  /// never part of the scanned local library, so without one it would be
  /// genuinely favorited but invisible in the Playlists page's aggregate
  /// "Favorites" list).
  Future<void> _toggleFavorite(BaseTrack station) async {
    final plugin = _favoritesPlugin;
    if (plugin == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The Favorites plugin is disabled in Settings.'),
      ));
      return;
    }
    OmnisHaptics.selectionClick();
    await plugin.toggleFavorite(station.id, track: station);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadTopStations();
    _loadCustomStations();
  }

  Future<void> _loadCustomStations() async {
    final stations = await CustomRadioStationStore.instance.load();
    if (!mounted) return;
    setState(() => _customStations = stations);
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

  Future<void> _playCustom(CustomRadioStation station) async {
    await widget.engine.setQueue([station.toTrack()]);
    await widget.engine.play();
  }

  Future<void> _deleteCustomStation(CustomRadioStation station) async {
    final updated = await CustomRadioStationStore.instance.delete(station.id);
    if (!mounted) return;
    setState(() => _customStations = updated);
  }

  /// Prompts for a name + stream URL and, once both look real (a
  /// non-empty name, a URL that parses with an http/https scheme —
  /// no attempt to actually reach the stream first, the same
  /// "trust what's entered, fail at play time if it's wrong" stance a
  /// Radio Browser-fetched URL already gets), persists it via
  /// [CustomRadioStationStore].
  Future<void> _addCustomStation() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add radio station'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Station name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Stream URL',
                hintText: 'https://stream.example.com/live',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final name = nameController.text.trim();
    final url = urlController.text.trim();
    final uri = Uri.tryParse(url);
    final validUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (name.isEmpty || !validUrl) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Enter a station name and a valid http(s) stream URL.'),
      ));
      return;
    }

    final updated = await CustomRadioStationStore.instance.add(name, url);
    if (!mounted) return;
    setState(() => _customStations = updated);
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
      appBar: AppBar(
        title: const Text('Radio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add station',
            onPressed: _addCustomStation,
          ),
        ],
      ),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      if (_customStations.isNotEmpty) ...[
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'My stations',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                        for (final custom in _customStations)
                          _buildCustomStationTile(custom),
                        const Divider(),
                      ],
                      if (_stations.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _searched ? 'Search results' : 'Top stations',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                      if (_stations.isEmpty && _customStations.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              _searched
                                  ? 'No stations found.'
                                  : 'No stations available right now.',
                            ),
                          ),
                        ),
                      for (var index = 0; index < _stations.length; index++)
                        _buildStationTile(_stations[index], index),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationTile(BaseTrack station, int index) {
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
          if (station.artists.isNotEmpty) station.artists.first,
          if (station.genres.isNotEmpty) station.genres.take(2).join(', '),
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isFavorite(station.id) ? Icons.favorite : Icons.favorite_border,
            ),
            color: _isFavorite(station.id)
                ? Theme.of(context).colorScheme.primary
                : null,
            tooltip: _isFavorite(station.id)
                ? 'Remove from favorites'
                : 'Add to favorites',
            onPressed: () => _toggleFavorite(station),
          ),
          isPlaying
              ? const Icon(Icons.graphic_eq, color: Colors.deepPurple)
              : const Icon(Icons.play_circle_outline),
        ],
      ),
      onTap: () => _play(index),
    );
  }

  Widget _buildCustomStationTile(CustomRadioStation custom) {
    final current = widget.engine.currentTrack;
    final isPlaying = current?.id == custom.id;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.radio)),
      title: Text(
        custom.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        custom.streamUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isFavorite(custom.id) ? Icons.favorite : Icons.favorite_border,
            ),
            color: _isFavorite(custom.id)
                ? Theme.of(context).colorScheme.primary
                : null,
            tooltip:
                _isFavorite(custom.id) ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => _toggleFavorite(custom.toTrack()),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove station',
            onPressed: () => _deleteCustomStation(custom),
          ),
          isPlaying
              ? const Icon(Icons.graphic_eq, color: Colors.deepPurple)
              : const Icon(Icons.play_circle_outline),
        ],
      ),
      onTap: () => _playCustom(custom),
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
