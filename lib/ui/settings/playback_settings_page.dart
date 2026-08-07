import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';

/// Playback & Audio: everything that shapes how a track actually sounds
/// and transitions to the next one. Split out of the old single-page
/// Settings screen so this reads as one coherent group instead of being
/// interleaved with theme/layout/library settings.
class PlaybackSettingsPage extends StatefulWidget {
  final AudioEngine engine;

  const PlaybackSettingsPage({super.key, required this.engine});

  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  late AppSettings _settings;
  double _volume = 1.0;
  double _speed = 1.0;
  double _pitch = 1.0;
  bool _skipSilence = false;
  double _crossfadeSec = 0;
  bool _gapless = true;
  int _seekIncrement = 10;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _volume = _settings.volume;
    _speed = _settings.playbackSpeed;
    _pitch = _settings.pitch;
    _skipSilence = _settings.skipSilenceEnabled;
    _crossfadeSec = _settings.crossfadeSeconds;
    _gapless = _settings.gaplessEnabled;
    _seekIncrement = _settings.seekIncrementSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Playback & Audio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Gapless playback'),
            subtitle: const Text(
                'The queue always loads as one concatenated source, so '
                'playback is gapless. Turning this off is not wired up yet.'),
            value: _gapless,
            onChanged: (v) {
              setState(() => _gapless = v);
              widget.engine.setGaplessEnabled(v);
              _settings.gaplessEnabled = v;
            },
          ),
          ListTile(
            title: const Text('Crossfade'),
            subtitle: Text(_crossfadeSec <= 0
                ? 'Off'
                : 'Overlaps the last ${_crossfadeSec.toStringAsFixed(1)}s of '
                    'each track into the next.'),
            trailing: DropdownButton<double>(
              value: _crossfadeSec <= 0 ? 0 : _crossfadeSec,
              items: const [
                DropdownMenuItem(value: 0.0, child: Text('Off')),
                DropdownMenuItem(value: 3.0, child: Text('3 sec')),
                DropdownMenuItem(value: 5.0, child: Text('5 sec')),
                DropdownMenuItem(value: 8.0, child: Text('8 sec')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _crossfadeSec = v);
                widget.engine
                    .setCrossfadeDuration(Duration(seconds: v.round()));
                _settings.crossfadeSeconds = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Skip forward/backward'),
            subtitle: const Text(
                'How far the skip buttons on Now Playing move playback.'),
            trailing: DropdownButton<int>(
              value: _seekIncrement,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10 sec')),
                DropdownMenuItem(value: 15, child: Text('15 sec')),
                DropdownMenuItem(value: 30, child: Text('30 sec')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _seekIncrement = v);
                _settings.seekIncrementSeconds = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Volume'),
            subtitle: Slider(
              value: _volume,
              min: 0,
              max: 1,
              onChanged: (v) {
                setState(() => _volume = v);
                widget.engine.setVolume(v);
                _settings.volume = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Playback speed'),
            subtitle: Slider(
              value: _speed,
              min: 0.25,
              max: 2.0,
              divisions: 14,
              label: '${_speed.toStringAsFixed(2)}x',
              onChanged: (v) {
                setState(() => _speed = v);
                widget.engine.setSpeed(v);
                _settings.playbackSpeed = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Pitch'),
            subtitle: Slider(
              value: _pitch,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: '${_pitch.toStringAsFixed(2)}x',
              onChanged: (v) {
                setState(() => _pitch = v);
                widget.engine.setPitch(v);
                _settings.pitch = v;
              },
            ),
          ),
          Text(
            'Independent of speed — Poweramp-style separate tempo/pitch '
            'controls, so changing playback speed doesn\'t have to shift '
            'pitch (or vice versa).',
            style: theme.textTheme.bodySmall,
          ),
          SwitchListTile(
            title: const Text('Skip silence'),
            subtitle: const Text(
                'Shortens silent gaps instead of playing through them at '
                'normal speed'),
            value: _skipSilence,
            onChanged: (v) {
              setState(() => _skipSilence = v);
              widget.engine.setSkipSilenceEnabled(v);
              _settings.skipSilenceEnabled = v;
            },
          ),
        ],
      ),
    );
  }
}
