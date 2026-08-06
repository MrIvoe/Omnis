/// One play event: which track, and when.
///
/// Lives in `lib/plugin_api/` (not `lib/plugins/scrobble_plugin.dart`,
/// where it used to be defined) because [IPlayHistoryProvider] needs a
/// return type both the plugin that implements it and any caller that
/// looks it up can import — see `lib/plugin_api/service_interfaces.dart`'s
/// doc for why that can't be `lib/core/` either.
class PlayRecord {
  final String trackId;
  final String title;
  final String artist;
  final DateTime playedAt;

  const PlayRecord({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artist': artist,
        'playedAtMs': playedAt.millisecondsSinceEpoch,
      };

  factory PlayRecord.fromJson(Map<String, dynamic> json) => PlayRecord(
        trackId: json['trackId']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        playedAt: DateTime.fromMillisecondsSinceEpoch(
          json['playedAtMs'] is int
              ? json['playedAtMs'] as int
              : int.tryParse(json['playedAtMs']?.toString() ?? '') ?? 0,
        ),
      );
}
