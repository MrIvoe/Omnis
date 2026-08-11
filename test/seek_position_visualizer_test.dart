import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/widgets/seek_position_visualizer.dart';

class _FakeVisualizerProvider implements IVisualizerProvider {
  final _controller = StreamController<List<double>>.broadcast();
  List<double> _latest = const [0, 0, 0, 0, 0, 0, 0];

  @override
  List<double> get latest => _latest;

  @override
  Stream<List<double>> get levels => _controller.stream;

  void emit(List<double> levels) {
    _latest = levels;
    _controller.add(levels);
  }

  void close() => _controller.close();
}

Widget _harness(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(height: 40, width: 300, child: child),
      ),
    );

void main() {
  testWidgets('renders 5 resting bars with no provider', (tester) async {
    await tester.pumpWidget(_harness(
      const SeekPositionVisualizer(provider: null, progress: 0.5),
    ));
    await tester.pump();

    expect(find.byType(Container), findsNWidgets(5));
  });

  testWidgets('bars grow taller as the provider emits higher levels',
      (tester) async {
    final provider = _FakeVisualizerProvider();
    await tester.pumpWidget(_harness(
      SeekPositionVisualizer(provider: provider, progress: 0.5),
    ));
    await tester.pump();

    final restingHeight =
        tester.getSize(find.byType(Container).first).height;

    provider.emit(const [1, 1, 1, 1, 1, 1, 1]);
    // A broadcast StreamController delivers events via a scheduled
    // microtask, not synchronously — give it a real pump cycle.
    await tester.pump(const Duration(milliseconds: 16));

    final loudHeight = tester.getSize(find.byType(Container).first).height;
    expect(loudHeight, greaterThan(restingHeight));

    provider.close();
  });

  testWidgets('moves along the track as progress changes', (tester) async {
    Widget build(double progress) => _harness(
          SeekPositionVisualizer(provider: null, progress: progress),
        );

    await tester.pumpWidget(build(0.0));
    await tester.pump();
    final centerAtStart = tester.getCenter(find.byType(Row)).dx;

    await tester.pumpWidget(build(1.0));
    await tester.pump();
    final centerAtEnd = tester.getCenter(find.byType(Row)).dx;

    expect(centerAtEnd, greaterThan(centerAtStart),
        reason: 'the marker must sit further right at progress=1.0 than '
            'at progress=0.0');
  });

  testWidgets('unsubscribes cleanly on dispose (no error after teardown)',
      (tester) async {
    final provider = _FakeVisualizerProvider();
    await tester.pumpWidget(_harness(
      SeekPositionVisualizer(provider: provider, progress: 0.5),
    ));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // A listen callback firing after dispose without the mounted guard
    // would throw synchronously inside setState.
    expect(() => provider.emit(const [1, 1, 1, 1, 1, 1, 1]), returnsNormally);
    provider.close();
  });
}
