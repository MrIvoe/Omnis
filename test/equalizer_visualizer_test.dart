import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/plugins/equalizer_plugin.dart';
import 'package:omnis/plugins/visualizer_plugin.dart';

void main() {
  test('equalizer plugin adjusts gain values', () {
    final plugin = EqualizerPlugin();
    plugin.setBand('bass', 6.0);
    plugin.setBand('mid', -2.0);
    plugin.setBand('treble', 1.0);

    expect(plugin.getBand('bass'), 6.0);
    expect(plugin.getBand('mid'), -2.0);
    expect(plugin.applyGain(0.5), greaterThan(0.5));
  });

  test('visualizer plugin emits levels', () async {
    final plugin = VisualizerPlugin();
    final levels = <List<double>>[];
    plugin.levels.listen(levels.add);

    plugin.emitLevels([0.1, 0.2, 0.3]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(levels.first, [0.1, 0.2, 0.3]);
  });

  test('VisualizerPlugin satisfies IVisualizerProvider, and levels emitted '
      'through the concrete plugin are visible through the interface type', () async {
    final plugin = VisualizerPlugin();
    final IVisualizerProvider provider = plugin;
    final levels = <List<double>>[];
    provider.levels.listen(levels.add);

    plugin.emitLevels([0.4, 0.5, 0.6]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(levels.first, [0.4, 0.5, 0.6]);
    expect(provider.latest, [0.4, 0.5, 0.6]);
  });
}
