import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A simple visualizer plugin that renders animated bars in the now-playing UI.
class VisualizerPlugin extends MusicPlugin {
  final StreamController<List<double>> _levelsController = StreamController.broadcast();

  Stream<List<double>> get levels => _levelsController.stream;

  void emitLevels(List<double> levels) {
    _levelsController.add(levels);
  }

  @override
  String get id => 'visualizer';

  @override
  String get name => 'Visualizer';

  @override
  String get description => 'Shows a simple animated spectrum for the current track.';

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
  Future<void> dispose() async {
    await _levelsController.close();
  }
}

class VisualizerBars extends StatefulWidget {
  final VisualizerPlugin plugin;

  const VisualizerBars({super.key, required this.plugin});

  @override
  State<VisualizerBars> createState() => _VisualizerBarsState();
}

class _VisualizerBarsState extends State<VisualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final StreamSubscription<List<double>> _sub;
  List<double> _levels = List.filled(8, 0.2);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _sub = widget.plugin.levels.listen((levels) {
      if (mounted) setState(() => _levels = levels);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_levels.length, (index) {
            final base = _levels[index].clamp(0.0, 1.0);
            final height = 18.0 + base * 70.0 + (progress * 10.0 * ((index % 2) == 0 ? 1 : -1));
            return Container(
              width: 8,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        );
      },
    );
  }
}
