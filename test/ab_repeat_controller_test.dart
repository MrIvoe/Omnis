import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/ab_repeat_controller.dart';

/// [AbRepeatController] is deliberately decoupled from `just_audio`'s
/// `AudioPlayer` — see its class doc — so this test drives it with a
/// plain [StreamController]<Duration> and a recording fake seek, rather
/// than a real player.
void main() {
  late StreamController<Duration> position;
  late List<Duration> seeks;
  late Duration current;
  late AbRepeatController controller;

  setUp(() {
    position = StreamController<Duration>.broadcast();
    seeks = [];
    current = Duration.zero;
    controller = AbRepeatController(
      positionStream: position.stream,
      currentPosition: () => current,
      seek: (d) async => seeks.add(d),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await position.close();
  });

  test('a freshly constructed controller has no range or A marker', () {
    expect(controller.range, isNull);
    expect(controller.markerA, isNull);
  });

  test('markA sets the A marker but no range yet (B not marked)', () {
    controller.markA(const Duration(seconds: 10));

    expect(controller.markerA, const Duration(seconds: 10));
    expect(controller.range, isNull);
  });

  test('markA defaults to the current position when none is given', () {
    current = const Duration(seconds: 5);

    controller.markA();

    expect(controller.markerA, const Duration(seconds: 5));
  });

  test('markB after markA starts the loop and sets range', () {
    controller.markA(const Duration(seconds: 10));
    final started = controller.markB(const Duration(seconds: 20));

    expect(started, isTrue);
    expect(controller.range, (const Duration(seconds: 10), const Duration(seconds: 20)));
  });

  test('markB before markA is rejected', () {
    final started = controller.markB(const Duration(seconds: 20));

    expect(started, isFalse);
    expect(controller.range, isNull);
  });

  test('markB at or before A is rejected — a zero/negative loop makes no '
      'sense', () {
    controller.markA(const Duration(seconds: 10));

    expect(controller.markB(const Duration(seconds: 10)), isFalse);
    expect(controller.markB(const Duration(seconds: 5)), isFalse);
    expect(controller.range, isNull);
  });

  test('once looping, reaching B seeks back to A', () async {
    controller.markA(const Duration(seconds: 10));
    controller.markB(const Duration(seconds: 20));

    position.add(const Duration(seconds: 15));
    await Future<void>.delayed(Duration.zero);
    expect(seeks, isEmpty, reason: 'not at B yet');

    position.add(const Duration(seconds: 20));
    await Future<void>.delayed(Duration.zero);
    expect(seeks, [const Duration(seconds: 10)]);

    // A subsequent tick past B seeks again — the loop keeps repeating,
    // not just fires once.
    position.add(const Duration(seconds: 21));
    await Future<void>.delayed(Duration.zero);
    expect(seeks, [const Duration(seconds: 10), const Duration(seconds: 10)]);
  });

  test('position ticks before any loop is armed never seek', () async {
    position.add(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);

    expect(seeks, isEmpty);
  });

  test('clear() stops the loop and resets both markers', () async {
    controller.markA(const Duration(seconds: 10));
    controller.markB(const Duration(seconds: 20));

    controller.clear();

    expect(controller.markerA, isNull);
    expect(controller.range, isNull);

    position.add(const Duration(seconds: 25));
    await Future<void>.delayed(Duration.zero);
    expect(seeks, isEmpty, reason: 'no more seeking once cleared');
  });

  test('markA while a loop is active clears B, requiring a fresh markB',
      () {
    controller.markA(const Duration(seconds: 10));
    controller.markB(const Duration(seconds: 20));

    controller.markA(const Duration(seconds: 30));

    expect(controller.markerA, const Duration(seconds: 30));
    expect(controller.range, isNull);
  });
}
