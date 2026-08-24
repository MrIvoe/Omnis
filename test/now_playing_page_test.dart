import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/ui/now_playing_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controllable fake, following the same `implements AudioEngine { ...
/// noSuchMethod }` pattern `mini_player_bar_test.dart`'s own `_FakeEngine`
/// uses — extended with the extra getters `NowPlayingPage.build()`
/// unconditionally reads while building `PlayerLayoutData` (crossfade/
/// shuffle/repeat/A-B-loop state), none of which `MiniPlayerBar` itself
/// touches.
class _FakeEngine implements AudioEngine {
  final BaseTrack? _track;
  _FakeEngine(this._track);

  final _trackController = StreamController<BaseTrack?>.broadcast();
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  @override
  BaseTrack? get currentTrack => _track;
  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;
  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Duration get crossfadeDuration => Duration.zero;
  @override
  bool get isCrossfading => false;
  @override
  bool get shuffleEnabled => false;
  @override
  RepeatMode get repeatMode => RepeatMode.off;
  @override
  Duration? get loopAMarker => null;
  @override
  (Duration a, Duration b)? get abRepeatRange => null;

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'a wide-but-not-rotated window (the default flutter test viewport, '
      'and every normal desktop window) does not force-substitute the '
      'Landscape layout for the default Standard layout', (tester) async {
    await AppSettings.instance.initialize();
    final core = MainCore();
    final layoutManager = LayoutManager();
    final engine = _FakeEngine(_track());
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(engine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
    });

    // Defaults: playerLayoutId == 'standard' (a "portrait-oriented" layout
    // eligible for the auto-landscape override) and autoLandscapeLayout ==
    // true — exactly the combination that used to force-substitute
    // Landscape whenever `MediaQuery.orientationOf` read as landscape,
    // which the default 800x600 test surface (wider than tall) always
    // does.
    expect(AppSettings.instance.playerLayoutId, 'standard');
    expect(AppSettings.instance.autoLandscapeLayout, isTrue);

    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pump();

    // PlayerAlbumArt is the fixed-size artwork widget Landscape (and every
    // other non-Standard bundled layout) renders; Standard instead paints
    // TrackArtwork full-bleed behind the controls. Its absence here proves
    // the resolved layout stayed Standard — i.e. `PlatformCapabilities
    // .isRotatable` being `false` on the `flutter test` host platform
    // correctly suppressed the old orientation-derived override.
    expect(find.byType(PlayerAlbumArt), findsNothing);
  });

  testWidgets(
      'Task 10 Step 2: the app bar over an active layout is transparent '
      'and title-less rather than a generic opaque strip, so it doesn\'t '
      'get in the way of layouts deliberately designed not to look like a '
      'conventional player', (tester) async {
    await AppSettings.instance.initialize();
    final core = MainCore();
    final layoutManager = LayoutManager();
    final engine = _FakeEngine(_track());
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(engine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
    });

    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pump();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.elevation, 0);
    expect(appBar.title, isNull);
    expect(find.text('Now Playing'), findsNothing);
    // Standard sets `PlayerLayout.usesOverlayChrome`, so it must keep the
    // full overlay treatment: white foreground/icon colors and an
    // extended body so its own full-bleed art/scrim reads as the real
    // background.
    expect(appBar.foregroundColor, Colors.white);
    expect((appBar.iconTheme)?.color, Colors.white);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);
  });

  testWidgets(
      'a non-overlay-chrome layout (Top Controls) keeps the app bar '
      'theme-derived instead of the Standard-only hardcoded transparent/'
      'white treatment, and does not extend its body behind it',
      (tester) async {
    await AppSettings.instance.initialize();
    AppSettings.instance.playerLayoutId = 'top_controls';
    final core = MainCore();
    final layoutManager = LayoutManager();
    final engine = _FakeEngine(_track());
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(engine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
      AppSettings.instance.playerLayoutId = 'standard';
    });

    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pump();

    // The Critical finding this guards against: Top Controls paints no
    // full-bleed background of its own, so a hardcoded transparent
    // background plus hardcoded white icons here would leave the back
    // button — the only way out of this screen on a platform with no
    // OS-level back gesture, e.g. Windows — at roughly no contrast
    // against a plain, light-theme scaffold background.
    expect(tester.takeException(), isNull);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, isNot(Colors.transparent));
    expect(appBar.foregroundColor, isNull,
        reason: 'omitting the override lets the app bar inherit '
            "OmnisTheme's own theme-derived AppBarTheme colors instead of "
            'a hardcoded white that has no contrast guarantee here');
    expect(appBar.iconTheme, isNull);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isFalse);

    // The Important finding this guards against: real content (Top
    // Controls' transport row, its first child) must render below the
    // app bar, not underneath it — the narrow-phone button/back-button
    // collision the review flagged.
    final appBarRect = tester.getRect(find.byType(AppBar));
    final controlsRect =
        tester.getRect(find.byType(PlayerControlsRow).first);
    expect(controlsRect.top, greaterThanOrEqualTo(appBarRect.bottom),
        reason: 'the transport row must not sit underneath the app bar');
  });

  testWidgets(
      'announces a "Now Playing" semantic heading even on a layout with '
      'no Semantics of its own (Car Mode)', (tester) async {
    final handle = tester.ensureSemantics();
    await AppSettings.instance.initialize();
    AppSettings.instance.playerLayoutId = 'car_mode';
    final core = MainCore();
    final layoutManager = LayoutManager();
    final engine = _FakeEngine(_track());
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(engine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
      AppSettings.instance.playerLayoutId = 'standard';
    });

    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pump();

    expect(find.bySemanticsLabel('Now Playing'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'the "Now Playing" heading coexists with Full Art + Gestures\' own '
      'gesture-area Semantics rather than replacing it', (tester) async {
    final handle = tester.ensureSemantics();
    await AppSettings.instance.initialize();
    AppSettings.instance.playerLayoutId = 'full_art_gestures';
    final core = MainCore();
    final layoutManager = LayoutManager();
    final engine = _FakeEngine(_track());
    locator.registerSingleton<MainCore>(core);
    locator.registerSingleton<AudioEngine>(engine);
    locator.registerSingleton<LayoutManager>(layoutManager);
    addTearDown(() async {
      await locator.unregister<AudioEngine>();
      await locator.unregister<MainCore>();
      await locator.unregister<LayoutManager>();
      await layoutManager.dispose();
      AppSettings.instance.playerLayoutId = 'standard';
    });

    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pump();

    // Both nodes must be reachable — the page's own heading, and the
    // layout's pre-existing gesture-area label — as two separate
    // semantics nodes, not one clobbering the other.
    expect(find.bySemanticsLabel('Now Playing'), findsOneWidget);
    expect(find.bySemanticsLabel('Now playing. Double tap to play.'),
        findsOneWidget);
    handle.dispose();
  });
}
