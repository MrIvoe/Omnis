import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/queue_continuation.dart';
import 'package:omnis/ui/settings/output_devices_page.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// Playback & Audio: everything that shapes how a track actually sounds
/// and transitions to the next one. Split out of the old single-page
/// Settings screen so this reads as one coherent group instead of being
/// interleaved with theme/layout/library settings.
class PlaybackSettingsPage extends StatefulWidget {
  final AudioEngine engine;

  /// Set when opened from `SettingsPage`'s search with a specific row in
  /// mind — that row scrolls into view and flashes once this page mounts.
  final String? highlightField;

  const PlaybackSettingsPage(
      {super.key, required this.engine, this.highlightField});

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
  QueueContinuationMode _continuationMode = QueueContinuationMode.off;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in [
      'gapless',
      'crossfade',
      'queue_continuation',
      'seek_increment',
      'volume',
      'playback_speed',
      'pitch',
      'skip_silence',
      'output_devices',
    ])
      field: GlobalKey<SettingsHighlightState>(),
  };

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
    _continuationMode = _settings.queueContinuationMode;
    scrollToAndFlashSetting(_keys[widget.highlightField]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Playback & Audio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsHighlight(
            key: _keys['gapless'],
            child: SwitchListTile(
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
          ),
          SettingsHighlight(
            key: _keys['crossfade'],
            child: ListTile(
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
          ),
          SettingsHighlight(
            key: _keys['queue_continuation'],
            child: ListTile(
              title: const Text('Queue continuation'),
              subtitle: Text(_continuationMode == QueueContinuationMode.off
                  ? 'Off — the queue just stops when it runs out.'
                  : 'Automatically extends the queue with more tracks '
                      'when it runs out.'),
              trailing: DropdownButton<QueueContinuationMode>(
                value: _continuationMode,
                items: const [
                  DropdownMenuItem(
                      value: QueueContinuationMode.off, child: Text('Off')),
                  DropdownMenuItem(
                      value: QueueContinuationMode.similarTrack,
                      child: Text('Similar track')),
                  DropdownMenuItem(
                      value: QueueContinuationMode.similarArtist,
                      child: Text('Similar artist')),
                  DropdownMenuItem(
                      value: QueueContinuationMode.sameGenre,
                      child: Text('Same genre')),
                  DropdownMenuItem(
                      value: QueueContinuationMode.sameMood,
                      child: Text('Same mood')),
                  DropdownMenuItem(
                      value: QueueContinuationMode.sameAlbum,
                      child: Text('Same album')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _continuationMode = v);
                  _settings.queueContinuationMode = v;
                },
              ),
            ),
          ),
          SettingsHighlight(
            key: _keys['seek_increment'],
            child: ListTile(
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
          ),
          SettingsHighlight(
            key: _keys['volume'],
            child: ListTile(
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
          ),
          SettingsHighlight(
            key: _keys['playback_speed'],
            child: ListTile(
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
          ),
          SettingsHighlight(
            key: _keys['pitch'],
            child: ListTile(
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
          ),
          Text(
            'Independent of speed — Poweramp-style separate tempo/pitch '
            'controls, so changing playback speed doesn\'t have to shift '
            'pitch (or vice versa).',
            style: theme.textTheme.bodySmall,
          ),
          SettingsHighlight(
            key: _keys['skip_silence'],
            child: SwitchListTile(
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
          ),
          SettingsHighlight(
            key: _keys['output_devices'],
            child: ListTile(
              leading: const Icon(Icons.speaker_group),
              title: const Text('Output devices'),
              subtitle: const Text(
                  'See connected speakers/headsets/USB DACs and (on '
                  'Android) choose one to route playback to.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OutputDevicesPage(),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
