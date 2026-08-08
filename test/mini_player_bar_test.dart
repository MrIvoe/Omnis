import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/widgets/mini_player_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controllable fake — real streams (not just stubbed getters), since
/// MiniPlayerBar subscribes to them directly.
class _FakeEngine implements AudioEngine {
  BaseTrack? _track;
  final _trackController = StreamController<BaseTrack?>.broadcast();
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  bool playCalled = false;
  bool pauseCalled = false;

  @override
  BaseTrack? get currentTrack => _track;

  void setTrack(BaseTrack? track) {
    _track = track;
    _trackController.add(track);
  }

  void setPlaying(bool playing) {
    _stateController.add(PlayerState(playing, ProcessingState.ready));
  }

  void setPosition(Duration position) => _positionController.add(position);
  void setDuration(Duration? duration) => _durationController.add(duration);

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;
  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> play() async => playCalled = true;
  @override
  Future<void> pause() async => pauseCalled = true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

BaseTrack _track({String id = 't1'}) => BaseTrack(
      id: id,
      title: 'Sunrise',
      artists: const ['Ava'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders nothing when no track is loaded', (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MiniPlayerBar(engine: engine)),
    ));

    expect(find.byType(MiniPlayerBar), findsOneWidget);
    expect(find.text('Sunrise'), findsNothing);
  });

  testWidgets('shows title/artist and reacts to play state once a track '
      'loads', (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MiniPlayerBar(engine: engine)),
    ));

    engine.setTrack(_track());
    await tester.pump();

    expect(find.text('Sunrise'), findsOneWidget);
    expect(find.text('Ava'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    engine.setPlaying(true);
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('the play/pause button calls the engine, not a route push',
      (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MiniPlayerBar(engine: engine)),
    ));
    engine.setTrack(_track());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(engine.playCalled, isTrue);
    // Still on the same route — tapping the icon didn't also trigger the
    // bar's own onTap navigation underneath it.
    expect(find.byType(MiniPlayerBar), findsOneWidget);
  });

  testWidgets(
      'tapping the bar itself pushes a new route, and the real '
      'NowPlayingPage it pushes renders without crashing', (tester) async {
    // NowPlayingPage (what MiniPlayerBar actually pushes) reads several
    // GetIt singletons (AudioEngine, MainCore, LayoutManager) and
    // AppSettings.instance — the same bootstrap main.dart itself runs.
    // Registered directly here rather than via ensureCoreReady()/
    // ensureLayoutManagerReady(): both those helpers await real dart:io
    // (LayoutManager.loadInstalled() reads installed layouts from disk),
    // and a real dart:io await inside a testWidgets() zone reliably hangs
    // forever on this Windows setup (same issue documented in
    // declarative_layout_test.dart). MainCore()'s bare constructor and
    // LayoutManager()'s bare constructor do no I/O — only .initialize()/
    // .loadInstalled() do — and allLayouts already returns the bundled
    // layouts with nothing installed, which is all this test needs.
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    final core = MainCore();
    final layoutManager = LayoutManager();
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(core.audioEngine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
    });

    final engine = _FakeEngine();
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: Scaffold(body: MiniPlayerBar(engine: engine)),
    ));
    engine.setTrack(_track());
    await tester.pump();

    // Tap the track title area, not the play/pause button.
    await tester.tap(find.text('Sunrise'));
    await tester.pumpAndSettle();

    expect(observer.pushedCount, 1);
    // The real registered engine has nothing loaded, so the pushed page
    // correctly shows its own empty-state — proving it's the real
    // NowPlayingPage that rendered, not a stand-in.
    expect(find.text('Nothing playing — pick a track from the Library.'),
        findsOneWidget);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushedCount = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    if (previousRoute != null) pushedCount++;
  }
}
