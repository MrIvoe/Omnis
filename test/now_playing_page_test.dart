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
}
