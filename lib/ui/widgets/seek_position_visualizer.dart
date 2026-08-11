import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';

/// A small cluster of live spectrum bars pinned to the current playhead
/// position on a seek bar — not a separate full-width visualizer display,
/// and not stretched across the bar's whole length, since live capture
/// only ever has a reading for *right now*: there is no historical level
/// data for any other point on the track. Degrades to flat resting bars
/// (rather than disappearing) whenever [provider] is `null` or simply
/// hasn't emitted a non-zero reading yet — e.g. the Visualizer plugin is
/// disabled, or is enabled but the user hasn't tapped "Activate
/// visualizer" this session.
class SeekPositionVisualizer extends StatefulWidget {
  final IVisualizerProvider? provider;

  /// Playback progress, 0.0 (start) to 1.0 (end) — where along the seek
  /// bar's width to pin the marker.
  final double progress;

  const SeekPositionVisualizer({
    super.key,
    required this.provider,
    required this.progress,
  });

  @override
  State<SeekPositionVisualizer> createState() =>
      _SeekPositionVisualizerState();
}

class _SeekPositionVisualizerState extends State<SeekPositionVisualizer> {
  static const _barCount = 5;

  StreamSubscription<List<double>>? _sub;
  List<double> _levels = const [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(SeekPositionVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _sub?.cancel();
      _levels = const [];
      _subscribe();
    }
  }

  void _subscribe() {
    final provider = widget.provider;
    if (provider == null) return;
    _levels = provider.latest;
    _sub = provider.levels.listen((levels) {
      if (mounted) setState(() => _levels = levels);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Down-samples (or pads) whatever band count [provider] emits to
  /// exactly [_barCount] readings, so this stays a fixed-size compact
  /// cluster regardless of the source's own resolution.
  List<double> _sampledLevels() {
    if (_levels.isEmpty) return List.filled(_barCount, 0.0);
    return List.generate(_barCount, (i) {
      final index = (i * _levels.length / _barCount).floor();
      return _levels[index.clamp(0, _levels.length - 1)].clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levels = _sampledLevels();
    return Align(
      alignment: Alignment(
        (widget.progress.clamp(0.0, 1.0) * 2) - 1,
        -1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final level in levels)
            Container(
              width: 3,
              height: 4 + level * 14,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}
