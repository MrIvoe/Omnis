/// Published whenever a track's favorite status changes (`FavoritesPlugin`
/// is the only current emitter). Lets anything with a favorites-derived
/// view (the Playlists page's "Favorites" smart list, in the same
/// `IndexedStack` as the Library page that likely triggered this) react
/// immediately instead of only refreshing the next time it happens to
/// rebuild for some unrelated reason.
///
/// Event types published on `EventBus` (reached via `PluginContext.events`
/// or `PluginManager.events`, both in `lib/core/`) live in
/// `lib/plugin_api/` for the same reason the interfaces in
/// `service_interfaces.dart` do: an event is capability-specific
/// knowledge (part of a contract between whoever emits it and whoever
/// listens), not part of the generic, stable event-bus mechanism itself —
/// see that file's doc for the full reasoning on why that split keeps
/// `lib/core/` from growing every time a new event is added.
class FavoriteChangedEvent {
  final String trackId;
  final bool isFavorite;

  const FavoriteChangedEvent(this.trackId, this.isFavorite);
}
