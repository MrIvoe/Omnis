import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/widgets/queue_panel.dart';

/// A controllable fake exposing exactly what [QueuePanel] touches: the
/// queue/currentIndex pair, their change streams, and the three mutating
/// calls (moveTrack/removeTrack/playAt) — recorded rather than actually
/// applied, so a test can assert on the exact indices [QueuePanel] itself
/// computed without needing a real reorder/removal to also work.
class _FakeEngine implements AudioEngine {
  List<BaseTrack> _queue = const [];
  int _currentIndex = -1;
  final _queueController = StreamController<List<BaseTrack>>.broadcast();
  final _trackController = StreamController<BaseTrack?>.broadcast();

  (int, int)? lastMoveCall;
  int? lastRemoveCall;
  int? lastPlayAtCall;

  /// Not [AudioEngine.setQueue] (a different signature/purpose) — this
  /// just feeds the fake's own state/streams for a test to observe.
  void emitQueue(List<BaseTrack> queue, {int currentIndex = -1}) {
    _queue = queue;
    _currentIndex = currentIndex;
    _queueController.add(queue);
    _trackController.add(
        currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null);
  }

  @override
  List<BaseTrack> get queue => _queue;
  @override
  int get currentIndex => _currentIndex;
  @override
  Stream<List<BaseTrack>> get queueStream => _queueController.stream;
  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  Future<void> moveTrack(int from, int to) async {
    lastMoveCall = (from, to);
  }

  @override
  Future<void> removeTrack(int index) async {
    lastRemoveCall = index;
  }

  @override
  Future<void> playAt(int index) async {
    lastPlayAtCall = index;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

BaseTrack _track(String id, {String title = 'Title'}) => BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPanel(WidgetTester tester, _FakeEngine engine) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => QueuePanel.show(context, engine),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing playing, shows an empty state', (tester) async {
    final engine = _FakeEngine();
    await pumpPanel(tester, engine);

    expect(find.text('Nothing playing.'), findsOneWidget);
  });

  testWidgets(
      'shows the current track under NOW PLAYING and the rest under NEXT',
      (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue(
      [_track('a', title: 'Alpha'), _track('b', title: 'Beta'), _track('c', title: 'Gamma')],
      currentIndex: 0,
    );
    await pumpPanel(tester, engine);

    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('NEXT (2)'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('a track already played (before currentIndex) is not shown '
      'under NEXT', (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue(
      [_track('a', title: 'Alpha'), _track('b', title: 'Beta'), _track('c', title: 'Gamma')],
      currentIndex: 1,
    );
    await pumpPanel(tester, engine);

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('NEXT (1)'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('with nothing left in the queue after the current track, no '
      'NEXT section renders', (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue([_track('a', title: 'Alpha')], currentIndex: 0);
    await pumpPanel(tester, engine);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('NEXT'), findsNothing);
  });

  testWidgets('tapping a NEXT track calls playAt with its real queue index',
      (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue(
      [_track('a', title: 'Alpha'), _track('b', title: 'Beta'), _track('c', title: 'Gamma')],
      currentIndex: 0,
    );
    await pumpPanel(tester, engine);

    await tester.tap(find.text('Gamma'));
    await tester.pump();

    // Gamma sits at real queue index 2 (splitAt=1, NEXT-relative index 1).
    expect(engine.lastPlayAtCall, 2);
  });

  testWidgets('swiping a NEXT track calls removeTrack with its real queue '
      'index', (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue(
      [_track('a', title: 'Alpha'), _track('b', title: 'Beta'), _track('c', title: 'Gamma')],
      currentIndex: 0,
    );
    await pumpPanel(tester, engine);

    await tester.drag(find.text('Gamma'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(engine.lastRemoveCall, 2);
  });

  testWidgets(
      'reordering within NEXT offsets both raw indices by the NOW PLAYING '
      'split point before calling moveTrack', (tester) async {
    final engine = _FakeEngine();
    engine.emitQueue(
      [
        _track('a', title: 'Alpha'),
        _track('b', title: 'Beta'),
        _track('c', title: 'Gamma'),
      ],
      currentIndex: 0,
    );
    await pumpPanel(tester, engine);

    // Drag "Beta" (the first NEXT row, real queue index 1) down past
    // "Gamma" (real queue index 2) — ReorderableListView needs a real
    // long-press-then-move gesture sequence (a plain drag/timedDrag
    // never starts the reorder at all), the standard way to drive it in
    // a widget test.
    final betaCenter = tester.getCenter(find.text('Beta'));
    final gammaCenter = tester.getCenter(find.text('Gamma'));

    final gesture = await tester.startGesture(betaCenter);
    await tester.pump(const Duration(seconds: 1)); // triggers the long-press
    await gesture.moveTo(Offset(betaCenter.dx, gammaCenter.dy + 20));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(engine.lastMoveCall, isNotNull);
    // Real queue indices: splitAt=1, so NEXT-relative old index 0 becomes
    // real index 1 — the `from` half of the (from, to) pair passed to
    // moveTrack, which does its own Flutter-reorder-convention adjustment
    // internally, is exactly this NEXT-relative-plus-splitAt value.
    expect(engine.lastMoveCall!.$1, 1);
  });
}
