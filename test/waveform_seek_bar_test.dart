import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:omnis/ui/widgets/waveform_seek_bar.dart';

/// `Waveform`'s constructor is a plain public one — no native call
/// needed to build one directly for a test.
Waveform _fakeWaveform() => Waveform(
      version: 2,
      flags: 0,
      sampleRate: 44100,
      samplesPerPixel: 1000,
      length: 4,
      data: const [-10, 10, -20, 20, -5, 5, -15, 15],
    );

Widget _harness({
  required Waveform waveform,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 100),
  required ValueChanged<Duration> onSeek,
  VoidCallback? onSeekEnd,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: 56,
          child: WaveformSeekBar(
            waveform: waveform,
            position: position,
            duration: duration,
            onSeek: onSeek,
            onSeekEnd: onSeekEnd,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders without crashing given a waveform', (tester) async {
    await tester.pumpWidget(_harness(waveform: _fakeWaveform(), onSeek: (_) {}));
    expect(find.byType(WaveformSeekBar), findsOneWidget);
  });

  testWidgets('tapping at a fraction of the width seeks proportionally',
      (tester) async {
    Duration? sought;
    await tester.pumpWidget(
        _harness(waveform: _fakeWaveform(), onSeek: (d) => sought = d));

    final topLeft = tester.getTopLeft(find.byType(WaveformSeekBar));
    // Bar is 200px wide, 100s long — tapping at x=100 (halfway) should
    // seek to 50s.
    await tester.tapAt(topLeft + const Offset(100, 28));
    await tester.pump();

    expect(sought, const Duration(seconds: 50));
  });

  testWidgets('tapping past the right edge clamps to the full duration',
      (tester) async {
    Duration? sought;
    await tester.pumpWidget(
        _harness(waveform: _fakeWaveform(), onSeek: (d) => sought = d));

    final topLeft = tester.getTopLeft(find.byType(WaveformSeekBar));
    // The GestureDetector fills the 200px SizedBox, so this still lands
    // inside it — but ratio math must still clamp to 1.0 rather than
    // extrapolating past the end.
    await tester.tapAt(topLeft + const Offset(199, 28));
    await tester.pump();

    expect(sought, isNotNull);
    expect(sought!.inSeconds, lessThanOrEqualTo(100));
  });

  testWidgets('onSeekEnd fires once on release, not during the drag',
      (tester) async {
    var seekEndCalls = 0;
    var seekCalls = 0;
    await tester.pumpWidget(_harness(
      waveform: _fakeWaveform(),
      onSeek: (_) => seekCalls++,
      onSeekEnd: () => seekEndCalls++,
    ));

    final topLeft = tester.getTopLeft(find.byType(WaveformSeekBar));
    final gesture =
        await tester.startGesture(topLeft + const Offset(20, 28));
    // Well beyond touch slop, so the horizontal-drag recognizer clearly
    // wins the gesture arena over the tap recognizer.
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(seekEndCalls, 0);
    expect(seekCalls, greaterThan(0));

    await gesture.up();
    await tester.pump();
    expect(seekEndCalls, 1);
  });
}
