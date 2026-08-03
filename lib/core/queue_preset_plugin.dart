import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A bundled plugin that suggests curated queue presets such as chill or focus.
class QueuePresetPlugin extends MusicPlugin {
  final List<String> presets = ['Chill', 'Focus', 'Workout', 'Sleep'];

  @override
  String get id => 'queue_presets';

  @override
  String get name => 'Queue Presets';

  @override
  String get description => 'Provides mood-based queue presets for the player.';

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
  dynamic uiSlot(String locationID) {
    if (locationID == 'library_header') {
      return null;
    }
    return null;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
