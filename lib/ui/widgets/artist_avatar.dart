import 'package:flutter/material.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';

/// Resolves and caches artist photo URLs looked up via
/// [IArtistImageProvider] (today, `ArtistImagePlugin`'s Deezer search) —
/// same "cache the lookup Future by key" shape as `ArtworkProvider`, just
/// keyed by artist name instead of track id, so scrolling a long Artists
/// list doesn't re-query the same name every rebuild.
class ArtistImageLookup {
  ArtistImageLookup._();

  static final Map<String, Future<String?>> _cache = {};

  static Future<String?> urlFor(
    String artistName,
    IArtistImageProvider? provider,
  ) {
    if (provider == null || !provider.isAvailable || artistName.isEmpty) {
      return Future.value(null);
    }
    return _cache.putIfAbsent(artistName, () => provider.imageUrlFor(artistName));
  }
}

/// A circular artist photo, falling back to a generic person icon while
/// loading, on lookup failure, or when no [IArtistImageProvider] is
/// registered (e.g. the Artist Photos plugin is disabled) — the same
/// "never a permanent blank box" contract [TrackArtwork] follows for album
/// art.
class ArtistAvatar extends StatelessWidget {
  final String artistName;
  final IArtistImageProvider? imageProvider;
  final double radius;

  const ArtistAvatar({
    super.key,
    required this.artistName,
    required this.imageProvider,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<String?>(
      future: ArtistImageLookup.urlFor(artistName, imageProvider),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url != null && url.isNotEmpty) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundImage: NetworkImage(url),
            onForegroundImageError: (error, stackTrace) {},
            child: _fallbackIcon(theme),
          );
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: _fallbackIcon(theme),
        );
      },
    );
  }

  Widget _fallbackIcon(ThemeData theme) => Icon(
        Icons.person,
        size: radius,
        color: theme.colorScheme.onPrimaryContainer,
      );
}
