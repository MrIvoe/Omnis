import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/player_layouts/full_art_gestures_layout.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/widgets/track_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseTrack _track() => BaseTrack(
      id: 't1',
      title: 'Sunrise',
      artists: const ['Ava'],
      album: 'Morning',
      duration: 180,
      type: TrackType.local,
      localPath: '/music/sunrise.mp3',
    );

PlayerLayoutData _dataFor({
  required VoidCallback onPlayPause,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
}) =>
    PlayerLayoutData(
      track: _track(),
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 180),
      playing: true,
      buffering: false,
      settings: AppSettings.instance,
      pluginManager: PluginManager(),
      lyricsPlugin: null,
      equalizerPlugin: null,
      visualizerPlugin: null,
      sleepTimerPlugin: null,
      lyricText: null,
      crossfadeStatusText: null,
      shuffleEnabled: false,
      repeatMode: RepeatMode.off,
      loopAMarker: null,
      abRepeatRange: null,
      onPlayPause: onPlayPause,
      onNext: onNext,
      onPrevious: onPrevious,
      onSeek: (_) {},
      onOpenEqualizer: () {},
      onEditLyrics: () {},
      onActivateVisualizer: () {},
      onOpenQueue: () {},
      onStartSleepTimer: () {},
      onCyclePlayMode: () {},
      onCycleAbRepeat: () {},
      onLongPressAbRepeat: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  tearDown(PlatformCapabilities.resetOverridesForTesting);

  Future<void> pump(WidgetTester tester, PlayerLayoutData data) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FullArtGesturesLayout().build(context, data),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // No case for touch-primary explicitly: this layout's swipe-to-skip is
  // its long-standing default behavior for every platform this test suite
  // ran against before Task 5, already covered by the "swipe skips" test
  // this file didn't previously have — the new coverage this task adds is
  // specifically the *desktop-primary* branch, which didn't exist before.
  group('desktop-primary platforms (Task 5): swipe-as-shortcut is hidden',
      () {
    testWidgets(
        'onHorizontalDragEnd is null on a desktop-primary platform — a '
        'mouse "drag" is not a gesture desktop users reach for',
        (tester) async {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pump(
        tester,
        _dataFor(onPlayPause: () {}, onNext: () {}, onPrevious: () {}),
      );

      final detector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(detector.onHorizontalDragEnd, isNull);
    });

    testWidgets(
        'onHorizontalDragEnd is wired (non-null) when not desktop-primary',
        (tester) async {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
      await pump(
        tester,
        _dataFor(onPlayPause: () {}, onNext: () {}, onPrevious: () {}),
      );

      final detector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(detector.onHorizontalDragEnd, isNotNull);
    });

    testWidgets(
        'onTap (play/pause) stays wired on a desktop-primary platform — a '
        'mouse click is still a real tap', (tester) async {
      var playPauseCalled = false;
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pump(
        tester,
        _dataFor(
          onPlayPause: () => playPauseCalled = true,
          onNext: () {},
          onPrevious: () {},
        ),
      );

      await tester.tap(find.byType(GestureDetector));
      expect(playPauseCalled, isTrue);
    });

    testWidgets(
        'Next/Previous screen-reader actions stay wired on a '
        'desktop-primary platform regardless of swipe being hidden from '
        'sighted users', (tester) async {
      var nextCalled = false;
      var previousCalled = false;
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pump(
        tester,
        _dataFor(
          onPlayPause: () {},
          onNext: () => nextCalled = true,
          onPrevious: () => previousCalled = true,
        ),
      );

      final semanticsWidget = tester.widget<Semantics>(find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.customSemanticsActions != null));
      final actions = semanticsWidget.properties.customSemanticsActions!;
      final nextAction =
          actions.keys.firstWhere((a) => a.label == 'Next track');
      final previousAction =
          actions.keys.firstWhere((a) => a.label == 'Previous track');
      actions[nextAction]?.call();
      actions[previousAction]?.call();

      expect(nextCalled, isTrue);
      expect(previousCalled, isTrue);
    });
  });

  testWidgets(
      'Task 10 Step 3: renders the track\'s real artwork rather than an '
      'Icons.album placeholder, despite the whole layout\'s premise being '
      'fullscreen album art', (tester) async {
    await pump(
      tester,
      _dataFor(onPlayPause: () {}, onNext: () {}, onPrevious: () {}),
    );

    expect(find.byType(TrackArtwork), findsOneWidget);
    expect(find.byIcon(Icons.album), findsNothing);
  });
}
