import 'package:flutter/foundation.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/core/equalizer_plugin.dart';
import 'package:omnis/core/lyrics_plugin.dart';
import 'package:omnis/core/queue_preset_plugin.dart';
import 'package:omnis/core/replay_gain_plugin.dart';
import 'package:omnis/core/scrobble_plugin.dart';
import 'package:omnis/core/sleep_timer_plugin.dart';
import 'package:omnis/core/smart_playlist_plugin.dart';
import 'package:omnis/core/visualizer_plugin.dart';

/// MainCore is the entry point for the Omnis micro-kernel music engine.
///
/// It owns the two "indestructible" layers:
///  - the [AudioEngine] (playback never stops)
///  - the [PluginManager] (plugin crashes are sandboxed + health-logged)
class MainCore {
  /// Audio engine instance.
  final AudioEngine _audioEngine;

  /// Plugin manager instance.
  final PluginManager _pluginManager;

  /// Constructor.
  MainCore()
      : _audioEngine = AudioEngine(),
        _pluginManager = PluginManager();

  /// Initialize the core engine: audio engine, plugin manager, and any
  /// previously installed plugins.
  Future<void> initialize() async {
    debugPrint('Initializing Omnis Core...');

    // Audio engine first — the player must be ready before any plugin hook.
    await _audioEngine.initialize();

    // Wire the engine's track-started callback to the plugin hooks.
    _audioEngine.onTrackStarted = (track) {
      // Ignore failures: the plugin manager sandboxes every call.
      // ignore: unawaited_futures
      _pluginManager.onTrackStart(track);
    };

    _pluginManager.register(SleepTimerPlugin());
    _pluginManager.register(QueuePresetPlugin());
    _pluginManager.register(ReplayGainPlugin());
    _pluginManager.register(LyricsPlugin());
    _pluginManager.register(EqualizerPlugin());
    _pluginManager.register(VisualizerPlugin());
    _pluginManager.register(SmartPlaylistPlugin());
    _pluginManager.register(ScrobblePlugin());

    // Initialize bundled plugins registered so far, then load any plugins
    // installed on disk from previous sessions.
    await _pluginManager.initializeAll();
    await _pluginManager.loadInstalled();

    debugPrint('Omnis Core initialized successfully');
  }

  /// Dispose the core engine.
  Future<void> dispose() async {
    debugPrint('Disposing Omnis Core...');
    await _pluginManager.dispose();
    await _audioEngine.dispose();
    debugPrint('Omnis Core disposed successfully');
  }

  /// The audio engine.
  AudioEngine get audioEngine => _audioEngine;

  /// The plugin manager.
  PluginManager get pluginManager => _pluginManager;

  /// The shared plugin sandbox (exposes health records for dashboards).
  PluginSandbox get sandbox => _pluginManager.sandbox;
}
