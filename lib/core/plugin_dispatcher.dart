import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';

/// Legacy facade for the plugin hook system.
///
/// The real implementation now lives in [PluginManager], which owns the
/// sandbox and the health dashboard. This class exists only so callers
/// written against the earlier API (`registerPlugin`, `onTrackStart`,
/// `uiSlot`) keep working.
@Deprecated('Use PluginManager instead — it is the canonical dispatcher.')
class PluginDispatcher {
  final PluginManager _manager;

  PluginDispatcher([PluginManager? manager])
      : _manager = manager ?? PluginManager();

  /// Register a plugin (in-process [MusicPlugin]).
  // ignore: deprecated_member_use
  void registerPlugin(MusicPlugin plugin) => _manager.register(plugin);

  /// Trigger the onTrackStart hook (an alias for [PluginManager.onTrackStart]).
  Future<void> onTrackStart(BaseTrack track) => _manager.onTrackStart(track);

  /// Trigger the onLibraryScan hook (an alias for [PluginManager.onLibraryScan]).
  Future<void> onLibraryScan(String file) => _manager.onLibraryScan(file);

  /// Collect UI widgets at [locationID].
  Future<List<dynamic>> uiSlot(String locationID) =>
      _manager.uiSlot(locationID);
}
