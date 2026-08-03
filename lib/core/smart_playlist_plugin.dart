import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A bundled plugin that suggests smart autoplay queues based on mood or genre.
class SmartPlaylistPlugin extends MusicPlugin {
  final List<String> _moods = ['Chill', 'Focus', 'Workout'];

  List<String> get moods => List.unmodifiable(_moods);

  List<BaseTrack> buildQueue(List<BaseTrack> tracks, {String? mood}) {
    final requestedMood = mood ?? _moods.first;
    return tracks.where((track) {
      final matched = track.mood?.toLowerCase() ?? '';
      return matched.contains(requestedMood.toLowerCase()) || requestedMood.toLowerCase() == 'focus' && track.genres.any((g) => g.toLowerCase().contains('ambient'));
    }).toList();
  }

  @override
  String get id => 'smart_playlist';

  @override
  String get name => 'Smart Playlist';

  @override
  String get description => 'Builds mood-based queues for autoplay and playlist suggestions.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {}

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}
