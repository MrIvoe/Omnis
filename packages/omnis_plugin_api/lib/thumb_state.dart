/// A track's thumbs-up/down preference — MusicBee comparison §36:
/// distinct from `IRatingsProvider`'s 0-5 star scale, a coarse "yes/no"
/// signal some listeners prefer over picking a specific star count.
///
/// Its own file, not declared inline in `service_interfaces.dart`, so
/// `smart_playlist_rule.dart` (whose `RuleCondition.matches` takes a
/// `ThumbState Function(String trackId)?` lookup) can depend on this type
/// without depending on the whole interfaces file — which itself depends
/// on `smart_playlist_rule.dart` for `ISmartPlaylistProvider.savedRules`.
/// That would otherwise be a real import cycle within this package.
enum ThumbState { none, up, down }
