import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/play_history_store.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';
import 'package:omnis_plugins/favorites_plugin.dart';

/// Home tab: Recently Played / Most Played / Recently Added / Continue
/// Listening / Favorites, each a horizontally-scrolling row of cards.
///
/// Recently Played/Most Played/Continue Listening are sourced from
/// `PlayHistoryStore` (core, always on — works regardless of whether the
/// optional `ScrobblePlugin` is installed). Favorites reads
/// `FavoritesPlugin` by type the same way `NowPlayingPage` looks up
/// optional plugins — the section simply doesn't render if that plugin
/// is disabled or nothing's favorited, the same graceful-absence pattern
/// used throughout this app.
class HomeDashboardPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;

  const HomeDashboardPage({
    super.key,
    required this.engine,
    required this.pluginManager,
  });

  @override
  State<HomeDashboardPage> createState() => _HomeDashboardPageState();
}

class _HomeSection {
  final String title;
  final List<BaseTrack> tracks;
  const _HomeSection(this.title, this.tracks);
}

class _HomeDashboardPageState extends State<HomeDashboardPage> {
  bool _loading = true;
  List<BaseTrack> _recentlyPlayed = const [];
  List<BaseTrack> _mostPlayed = const [];
  List<BaseTrack> _recentlyAdded = const [];
  List<BaseTrack> _continueListening = const [];
  List<BaseTrack> _favorites = const [];

  StreamSubscription<BaseTrack?>? _trackSub;
  StreamSubscription<FavoriteChangedEvent>? _favoriteSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep every section fresh while this tab stays alive in the
    // background (HomePage's IndexedStack never disposes it) — otherwise
    // returning to Home after playing or favoriting something elsewhere
    // would show stale data until some unrelated rebuild happened to
    // occur. Same event-bus pattern playlist_page.dart's Favorites smart
    // list already uses to decouple from FavoritesPlugin.
    _trackSub = widget.engine.trackStream.listen((_) => _load());
    _favoriteSub =
        widget.pluginManager.events.on<FavoriteChangedEvent>().listen((_) {
      _load();
    });
    // A scan, tag edit, or delete on the Library tab calls
    // LibraryRepository.save(), which this page wouldn't otherwise hear
    // about at all (it has no track-change or favorite-change reason to
    // reload for those) — this is what actually makes those changes show
    // up here without the user needing to leave and come back.
    LibraryRepository.instance.addListener(_load);
  }

  @override
  void dispose() {
    _trackSub?.cancel();
    _favoriteSub?.cancel();
    LibraryRepository.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final library = await LibraryRepository.instance.load();
    final libraryById = {for (final t in library) t.id: t};

    // A played track that was never scanned/imported into the library —
    // a radio station, a Spotify/YouTube/Jellyfin/Plex/Subsonic/DLNA/
    // Emby track — has no entry in `libraryById` by definition, but its
    // play was still genuinely recorded. `TrackPlayStats.trackSnapshot`
    // (captured at record time, only for a non-local track) is the
    // fallback that makes it displayable/replayable here too instead of
    // the entry silently vanishing — item 41's "recorded but never
    // rendered" gap.
    // A snapshot decode failure (a corrupted/partially-written record,
    // the same real-world failure mode every other JSON-backed store in
    // this app defends against per-entry) must skip just that one
    // history entry, not the whole dashboard load.
    BaseTrack? decodeSnapshot(Map<String, dynamic> json) {
      try {
        return BaseTrack.fromJson(json);
      } catch (_) {
        return null;
      }
    }

    List<BaseTrack> joinStats(List<TrackPlayStats> stats) => [
          for (final s in stats)
            if (libraryById[s.trackId] != null)
              libraryById[s.trackId]!
            else if (s.trackSnapshot != null)
              if (decodeSnapshot(s.trackSnapshot!) case final track?) track,
        ];

    final recentlyPlayed =
        joinStats(await PlayHistoryStore.instance.recentlyPlayed());
    final mostPlayed = joinStats(await PlayHistoryStore.instance.mostPlayed());
    final continueListening =
        joinStats(await PlayHistoryStore.instance.continueListening());

    final recentlyAdded = library.where((t) => t.dateAdded != null).toList()
      ..sort((a, b) => b.dateAdded!.compareTo(a.dateAdded!));

    final favorites = widget.pluginManager
            .bundled<FavoritesPlugin>(onlyEnabled: true)
            ?.favoritesFrom(library) ??
        const <BaseTrack>[];

    if (!mounted) return;
    setState(() {
      _recentlyPlayed = recentlyPlayed;
      _mostPlayed = mostPlayed;
      _recentlyAdded = recentlyAdded.take(20).toList();
      _continueListening = continueListening;
      _favorites = favorites.take(20).toList();
      _loading = false;
    });
  }

  Future<void> _play(List<BaseTrack> section, int index) async {
    await widget.engine.setQueue(section, startIndex: index);
    await widget.engine.play();
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sections = <_HomeSection>[
      if (_continueListening.isNotEmpty)
        _HomeSection('Continue Listening', _continueListening),
      if (_recentlyPlayed.isNotEmpty)
        _HomeSection('Recently Played', _recentlyPlayed),
      if (_mostPlayed.isNotEmpty) _HomeSection('Most Played', _mostPlayed),
      if (_recentlyAdded.isNotEmpty)
        _HomeSection('Recently Added', _recentlyAdded),
      if (_favorites.isNotEmpty) _HomeSection('Favorites', _favorites),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: sections.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Play some music to see it here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [for (final s in sections) _buildSection(s)],
            ),
    );
  }

  Widget _buildSection(_HomeSection section) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(section.title, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SizedBox(
            key: ValueKey('home_section_${section.title}'),
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: section.tracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final track = section.tracks[index];
                return _HomeCard(
                  track: track,
                  onTap: () => _play(section.tracks, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final BaseTrack track;
  final VoidCallback onTap;

  const _HomeCard({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: TrackArtwork(
                track: track,
                width: 130,
                height: 130,
                iconSize: 40,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              track.artists.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
