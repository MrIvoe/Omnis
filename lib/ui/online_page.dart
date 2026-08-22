import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/radio_page.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis_plugins/spotify_playback_plugin.dart';
import 'package:omnis_plugins/youtube_playback_plugin.dart';

/// "Online" tab (spec §63/item 38's "user access" gap): a single place to
/// reach every online music source — Radio (unchanged, via [RadioBody]),
/// each self-hosted connectivity plugin (Ampache/Koel/OpenSubsonic/
/// Jellyfin/Plex/Emby — any [IOnlineSearchProvider] that's both enabled
/// and [IOnlineSearchProvider.isConfigured]), and YouTube/Spotify.
/// Previously Radio was the only online source with a real tab; the
/// connectivity plugins had full working search backends
/// (`AmpachePlugin.search`, etc.) with **no UI anywhere** that called
/// them, and YouTube/Spotify playback were reachable only by burying into
/// Settings → Plugins → tap the plugin — this page is what makes "we have
/// a way of user access" to all of it actually true.
///
/// YouTube/Spotify are deliberately **not** [IOnlineSearchProvider]s (see
/// that interface's own doc comment): both only ever return metadata-only
/// tracks `AudioEngine` can't actually play. Rather than force them
/// through a "tap a result to play" contract they can't honestly satisfy,
/// their tabs embed each plugin's own existing `uiSlot('plugin_settings')`
/// widget directly — `YoutubePlaybackPlugin`'s real paste-a-URL-and-play
/// embedded player, `SpotifyPlaybackPlugin`'s real Spotify Connect
/// remote-control UI — reusing fully-working functionality instead of
/// inventing a new, misleading search-and-play UI neither plugin can
/// back up.
class OnlinePage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;

  const OnlinePage({
    super.key,
    required this.engine,
    required this.pluginManager,
  });

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

/// One selectable entry in the top selector bar.
enum _OnlineSectionKind { radio, searchProvider, youtube, spotify }

class _OnlineSection {
  final _OnlineSectionKind kind;
  final String label;
  final IOnlineSearchProvider? provider;

  const _OnlineSection(this.kind, this.label, {this.provider});
}

class _OnlinePageState extends State<OnlinePage> {
  int _selectedIndex = 0;
  final _radioBodyKey = GlobalKey<RadioBodyState>();

  List<IOnlineSearchProvider> get _searchProviders => widget.pluginManager.services
      .getAll<IOnlineSearchProvider>()
      .where((p) => p.isConfigured)
      .toList();

  ManagedPlugin? get _youtubePlaybackManaged =>
      widget.pluginManager.bundled<YoutubePlaybackPlugin>(onlyEnabled: true) ==
              null
          ? null
          : widget.pluginManager.byId('youtube_playback');

  ManagedPlugin? get _spotifyPlaybackManaged =>
      widget.pluginManager.bundled<SpotifyPlaybackPlugin>(onlyEnabled: true) ==
              null
          ? null
          : widget.pluginManager.byId('spotify_playback');

  List<_OnlineSection> get _sections {
    final sections = <_OnlineSection>[
      const _OnlineSection(_OnlineSectionKind.radio, 'Radio'),
      for (final provider in _searchProviders)
        _OnlineSection(_OnlineSectionKind.searchProvider,
            provider.providerName,
            provider: provider),
    ];
    if (_youtubePlaybackManaged != null) {
      sections.add(const _OnlineSection(_OnlineSectionKind.youtube, 'YouTube'));
    }
    if (_spotifyPlaybackManaged != null) {
      sections.add(const _OnlineSection(_OnlineSectionKind.spotify, 'Spotify'));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    // The set of available sections can shrink (a plugin disabled mid-
    // session) — clamp rather than index out of range.
    final selected = _selectedIndex >= sections.length ? 0 : _selectedIndex;
    final current = sections[selected];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online'),
        actions: current.kind == _OnlineSectionKind.radio
            ? [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add station',
                  onPressed: () => _radioBodyKey.currentState?.addStation(),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(sections[i].label),
                      selected: i == selected,
                      onSelected: (_) {
                        OmnisHaptics.selectionClick();
                        setState(() => _selectedIndex = i);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: _buildSection(current)),
        ],
      ),
    );
  }

  Widget _buildSection(_OnlineSection section) {
    switch (section.kind) {
      case _OnlineSectionKind.radio:
        return RadioBody(
          key: _radioBodyKey,
          engine: widget.engine,
          pluginManager: widget.pluginManager,
        );
      case _OnlineSectionKind.searchProvider:
        // A fresh key per provider so switching providers doesn't reuse
        // another provider's search results/text-field state.
        return _ProviderSearchView(
          key: ValueKey(section.provider!.providerName),
          engine: widget.engine,
          pluginManager: widget.pluginManager,
          provider: section.provider!,
        );
      case _OnlineSectionKind.youtube:
        return _PluginSlotBody(
          pluginManager: widget.pluginManager,
          managedPlugin: _youtubePlaybackManaged!,
        );
      case _OnlineSectionKind.spotify:
        return _PluginSlotBody(
          pluginManager: widget.pluginManager,
          managedPlugin: _spotifyPlaybackManaged!,
        );
    }
  }
}

/// Search-and-play for one [IOnlineSearchProvider] — a self-hosted server
/// whose results are real, directly playable [BaseTrack]s, so this
/// mirrors [RadioBody]'s own search-box-plus-list shape rather than
/// inventing a different pattern for what's functionally the same kind
/// of source. No "top results on open" the way Radio has (Radio Browser
/// has a real "most voted" endpoint; a generic media server's `search`
/// has no equivalent "show me something" query), so this starts empty
/// with a prompt instead.
class _ProviderSearchView extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;
  final IOnlineSearchProvider provider;

  const _ProviderSearchView({
    super.key,
    required this.engine,
    required this.pluginManager,
    required this.provider,
  });

  @override
  State<_ProviderSearchView> createState() => _ProviderSearchViewState();
}

class _ProviderSearchViewState extends State<_ProviderSearchView> {
  final _searchController = TextEditingController();
  List<BaseTrack> _results = const [];
  bool _loading = false;
  bool _searched = false;

  IFavoritesProvider? get _favoritesProvider =>
      widget.pluginManager.services.get<IFavoritesProvider>();

  bool _isFavorite(String trackId) =>
      _favoritesProvider?.isFavorite(trackId) ?? false;

  Future<void> _toggleFavorite(BaseTrack track) async {
    final provider = _favoritesProvider;
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No favorites provider is installed/enabled.'),
      ));
      return;
    }
    OmnisHaptics.selectionClick();
    await provider.setFavorite(track.id, !provider.isFavorite(track.id),
        track: track);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await widget.provider.search(trimmed);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _play(int index) async {
    await widget.engine.setQueue(_results, startIndex: index);
    await widget.engine.play();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search ${widget.provider.providerName}',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _results = const [];
                          _searched = false;
                        });
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
              : !_searched
                  ? Center(
                      child: Text(
                        'Search ${widget.provider.providerName}\'s library.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : _results.isEmpty
                      ? const Center(child: Text('No matches found.'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) =>
                              _buildResultTile(_results[index], index),
                        ),
        ),
      ],
    );
  }

  Widget _buildResultTile(BaseTrack track, int index) {
    final current = widget.engine.currentTrack;
    final isPlaying = current?.id == track.id;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.cloud_queue)),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isFavorite(track.id) ? Icons.favorite : Icons.favorite_border,
            ),
            color: _isFavorite(track.id)
                ? Theme.of(context).colorScheme.primary
                : null,
            tooltip: _isFavorite(track.id)
                ? 'Remove from favorites'
                : 'Add to favorites',
            onPressed: () => _toggleFavorite(track),
          ),
          isPlaying
              ? const Icon(Icons.graphic_eq, color: Colors.deepPurple)
              : const Icon(Icons.play_circle_outline),
        ],
      ),
      onTap: () => _play(index),
    );
  }
}

/// Loads and renders exactly one bundled plugin's own
/// `uiSlot('plugin_settings')` widget as a tab body — the same call
/// `PluginSettingsPage` makes, just without that page's own Scaffold/
/// AppBar/description-card chrome, since here it's one section among
/// several under the Online tab's own shared AppBar.
class _PluginSlotBody extends StatefulWidget {
  final PluginManager pluginManager;
  final ManagedPlugin managedPlugin;

  const _PluginSlotBody({
    required this.pluginManager,
    required this.managedPlugin,
  });

  @override
  State<_PluginSlotBody> createState() => _PluginSlotBodyState();
}

class _PluginSlotBodyState extends State<_PluginSlotBody> {
  dynamic _content;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PluginSlotBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.managedPlugin.id != widget.managedPlugin.id) {
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    final result = await widget.pluginManager
        .uiSlotForPlugin(widget.managedPlugin, 'plugin_settings');
    if (mounted) {
      setState(() {
        _content = result;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_content is! Widget) {
      return Center(
        child: Text('${widget.managedPlugin.name} has nothing to show here.'),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _content as Widget,
    );
  }
}
