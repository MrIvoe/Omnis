import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/player_layouts/registry.dart';
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

PlayerLayoutData _dataFor(AppSettings settings) => PlayerLayoutData(
      track: _track(),
      position: const Duration(seconds: 30),
      duration: const Duration(seconds: 180),
      playing: true,
      buffering: false,
      settings: settings,
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
      onPlayPause: () {},
      onNext: () {},
      onPrevious: () {},
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

  group('player layout registry', () {
    test('every layout has a unique, non-empty id', () {
      final layouts = createPlayerLayouts();
      expect(layouts, isNotEmpty);
      expect(
        layouts.map((l) => l.id).toSet(),
        hasLength(layouts.length),
        reason: 'a duplicate id would make resolvePlayerLayout ambiguous',
      );
      expect(layouts.every((l) => l.id.isNotEmpty), isTrue);
    });

    test('resolvePlayerLayout finds a registered layout by id', () {
      final layout = resolvePlayerLayout('car_mode');
      expect(layout.id, 'car_mode');
    });

    test('resolvePlayerLayout falls back to the first layout for an unknown id',
        () {
      // Simulates a persisted preference from a layout that was since
      // removed, or a corrupt/garbage stored value.
      final layout = resolvePlayerLayout('does_not_exist');
      expect(layout.id, createPlayerLayouts().first.id);
    });

    test('exactly the gesture-first layouts declare their own gestures', () {
      final byId = {for (final l in createPlayerLayouts()) l.id: l};
      expect(byId['full_art_gestures']!.definesOwnGestures, isTrue);
      expect(byId['karaoke_gestures']!.definesOwnGestures, isTrue);
      expect(byId['standard']!.definesOwnGestures, isFalse);
      expect(byId['top_controls']!.definesOwnGestures, isFalse);
      expect(byId['landscape']!.definesOwnGestures, isFalse);
      expect(byId['car_mode']!.definesOwnGestures, isFalse);
      expect(byId['tv_mode']!.definesOwnGestures, isFalse);
    });
  });

  group('swipeSkipActionFor', () {
    test('a fast leftward swipe skips forward', () {
      expect(swipeSkipActionFor(-300), SwipeSkipAction.next);
    });

    test('a fast rightward swipe skips backward', () {
      expect(swipeSkipActionFor(300), SwipeSkipAction.previous);
    });

    test('a slow swipe below the threshold does nothing', () {
      expect(swipeSkipActionFor(50), isNull);
      expect(swipeSkipActionFor(-50), isNull);
    });

    test('no velocity (e.g. a tap, not a drag) does nothing', () {
      expect(swipeSkipActionFor(null), isNull);
    });
  });

  group('PlayerLayoutData.formatDuration', () {
    test('renders m:ss under an hour', () {
      final data = _dataFor(AppSettings.instance);
      expect(
          data.formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
    });

    test('renders h:mm:ss at or past an hour', () {
      final data = _dataFor(AppSettings.instance);
      expect(
        data.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('every registered layout renders without throwing', () {
    // Exercises all six layouts' build() methods with no plugins available
    // (the "everything disabled" degraded path each one has to handle) —
    // this is what actually would have caught a null Theme.of/MediaQuery
    // dependency or a layout assuming a plugin is always present, none of
    // which `flutter analyze` checks.
    for (final layout in createPlayerLayouts()) {
      testWidgets('${layout.id} builds cleanly with no plugins available',
          (tester) async {
        final data = _dataFor(AppSettings.instance);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => layout.build(context, data),
            ),
          ),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Sunrise'), findsWidgets);
      });
    }

    testWidgets('landscape layout renders cleanly at a wide, short size',
        (tester) async {
      final layout = resolvePlayerLayout('landscape');
      final data = _dataFor(AppSettings.instance);
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tv_mode layout renders without overflow at a real '
        "phone's logical width — not just this test file's 800px "
        "default, which a real device's much narrower ~360-400dp "
        "screen doesn't match (a real overflow bug only a narrower "
        "viewport catches)", (tester) async {
      final layout = resolvePlayerLayout('tv_mode');
      final data = _dataFor(AppSettings.instance);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('landscape/car_mode album art overflow guard', () {
    // Regression tests for the bug fixed by wrapping each layout's Row in
    // a LayoutBuilder and clamping its fixed-size children to the
    // actually-available height (see landscape_layout.dart and
    // car_mode_layout.dart). Both heights below were picked by measuring
    // the pre-fix behavior directly (reverting the fix locally, per this
    // suite's own discipline for regression tests) rather than guessed:
    //
    // - Landscape's fixed 160px `PlayerAlbumArt` sits directly in a Row,
    //   whose cross axis (height) is NOT what a Flex's own "overflowed"
    //   assertion covers — a Row only asserts on horizontal (main-axis)
    //   overflow. So a too-tall fixed-height child in a Row never throws;
    //   Flutter instead silently *forces* it down to whatever height is
    //   available while leaving its width alone, squishing a square into
    //   a rectangle. Confirmed directly: at this exact 800x300 viewport,
    //   the pre-fix widget renders PlayerAlbumArt at Size(160, 112) — not
    //   Size(160, 160) — with tester.takeException() still null either
    //   way. So "no exception" (what Step 3 of this task's brief
    //   suggested asserting) cannot distinguish pre-fix from post-fix
    //   here; the real, verified regression is the squished aspect
    //   ratio, which this test asserts against directly.
    // - Car Mode's fixed 120-ish px-tall rail buttons and 140px album art
    //   sit in actual vertical Columns, so a too-short window there does
    //   throw a real "RenderFlex overflowed" — confirmed by reverting the
    //   fix locally and seeing this exact test fail at height 250.
    testWidgets(
        'landscape layout scales album art to a square that fits a short '
        "window, instead of letting the Row it sits in force a fixed "
        '160px square into a squished rectangle', (tester) async {
      final layout = resolvePlayerLayout('landscape');
      final data = _dataFor(AppSettings.instance);
      tester.view.physicalSize = const Size(800, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(PlayerAlbumArt));
      expect(
        size.width,
        closeTo(size.height, 0.5),
        reason: 'pre-fix this renders as Size(160, 112) — a squished, '
            'non-square rectangle — because the fixed 160px art is a '
            "direct Row child with no shrink guard on its height",
      );
    });

    testWidgets(
        'car_mode layout renders without overflowing at a short window '
        'that overflowed before the rail buttons and album art were '
        'clamped to the available height', (tester) async {
      final layout = resolvePlayerLayout('car_mode');
      final data = _dataFor(AppSettings.instance);
      tester.view.physicalSize = const Size(800, 250);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('TV Mode layout — real D-pad/keyboard navigation', () {
    // Verifies the actual claim in tv_mode_layout.dart's doc comment:
    // Flutter's default focus traversal moves focus between the
    // transport buttons on arrow-key input with no custom key-handling
    // code in the layout itself. A real Android D-pad's KEYCODE_DPAD_*
    // events arrive at Flutter as these same logical arrow keys, so
    // this is the same mechanism a real remote would exercise, not a
    // simulation of a different one.
    FocusNode focusNodeFor(WidgetTester tester, Key key) =>
        Focus.of(tester.element(find.byKey(key)));

    testWidgets(
        'Play/Pause has focus as soon as the layout appears — a '
        'remote never lands with nothing focused at all', (tester) async {
      final layout = resolvePlayerLayout('tv_mode');
      final data = _dataFor(AppSettings.instance);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      expect(
        focusNodeFor(tester, const ValueKey('tv_mode_play_pause')).hasFocus,
        isTrue,
      );
    });

    testWidgets(
        'arrow-right moves focus from Play/Pause to Next, '
        'arrow-left moves it back — real focus traversal, not just a '
        'visual claim', (tester) async {
      final layout = resolvePlayerLayout('tv_mode');
      final data = _dataFor(AppSettings.instance);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        focusNodeFor(tester, const ValueKey('tv_mode_next')).hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        focusNodeFor(tester, const ValueKey('tv_mode_play_pause')).hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        focusNodeFor(tester, const ValueKey('tv_mode_previous')).hasFocus,
        isTrue,
      );
    });

    testWidgets(
        'activating the focused button (Enter/DPAD_CENTER) '
        'actually invokes its callback, not just moves a visual '
        'highlight', (tester) async {
      final layout = resolvePlayerLayout('tv_mode');
      var playPauseCalled = false;
      final data = PlayerLayoutData(
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
        onPlayPause: () => playPauseCalled = true,
        onNext: () {},
        onPrevious: () {},
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

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => layout.build(context, data)),
        ),
      ));
      await tester.pump();
      // Autofocus lands on Play/Pause per the test above — activating it
      // directly here (Enter is the keyboard-test-harness equivalent of
      // a D-pad's center/OK button) confirms the button is not just
      // visually highlighted but genuinely wired to the real callback.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(playPauseCalled, isTrue);
    });
  });
}
