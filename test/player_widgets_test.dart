import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/lyric_line.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis/ui/theme/omnis_icon_style.dart';
import 'package:omnis/ui/widgets/seek_position_visualizer.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLyricsProvider implements ILyricsProvider {
  @override
  String currentLyricFor(BaseTrack track, Duration position) => 'La la la';
}

/// A provider that also implements the separate, optional
/// `ISyncedLyricsProvider` capability — see that interface's own doc in
/// `service_interfaces.dart` for why it's a second interface rather than
/// a method added onto `ILyricsProvider` itself.
class _FakeSyncedLyricsProvider implements ILyricsProvider, ISyncedLyricsProvider {
  final List<LyricLine> lines;

  _FakeSyncedLyricsProvider(this.lines);

  @override
  String currentLyricFor(BaseTrack track, Duration position) =>
      'single-block fallback text — should not render when synced lines exist';

  @override
  List<LyricLine>? syncedLyricsFor(BaseTrack track) => lines;
}

/// Fifteen lines, five seconds apart (0s..70s) — enough total content
/// (15 * 44px default line extent = 660px) to genuinely overflow a modest
/// test viewport, so the auto-scroll-to-center assertions exercise a real
/// non-zero scroll rather than a no-op on unscrollable content.
List<LyricLine> _manySyncedLines() => [
      for (var i = 0; i < 15; i++)
        LyricLine(
          timestamp: Duration(seconds: i * 5),
          text: 'Line $i',
        ),
    ];

class _FakeVisualizerProvider implements IVisualizerProvider {
  final _controller = StreamController<List<double>>.broadcast();

  @override
  List<double> get latest => const [0, 0, 0, 0, 0, 0, 0];

  @override
  Stream<List<double>> get levels => _controller.stream;

  void close() => _controller.close();
}

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
  bool playing = true,
  bool shuffleEnabled = false,
  RepeatMode repeatMode = RepeatMode.off,
  SleepTimerPlugin? sleepTimerPlugin,
  ILyricsProvider? lyricsPlugin,
  IVisualizerProvider? visualizerPlugin,
  String? lyricText,
  Duration? position,
  Duration? duration,
  ValueChanged<Duration>? onSeek,
  VoidCallback? onCyclePlayMode,
  VoidCallback? onStartSleepTimer,
  VoidCallback? onCancelSleepTimer,
  VoidCallback? onOpenQueue,
}) =>
    PlayerLayoutData(
      track: _track(),
      position: position ?? const Duration(seconds: 30),
      duration: duration ?? const Duration(seconds: 180),
      playing: playing,
      buffering: false,
      settings: AppSettings.instance,
      pluginManager: PluginManager(),
      lyricsPlugin: lyricsPlugin,
      equalizerPlugin: null,
      visualizerPlugin: visualizerPlugin,
      sleepTimerPlugin: sleepTimerPlugin,
      lyricText: lyricText,
      crossfadeStatusText: null,
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      loopAMarker: null,
      abRepeatRange: null,
      onPlayPause: () {},
      onNext: () {},
      onPrevious: () {},
      onSeek: onSeek ?? (_) {},
      onOpenEqualizer: () {},
      onEditLyrics: () {},
      onActivateVisualizer: () {},
      onOpenQueue: onOpenQueue ?? () {},
      onStartSleepTimer: onStartSleepTimer ?? () {},
      onCancelSleepTimer: onCancelSleepTimer,
      onCyclePlayMode: onCyclePlayMode ?? () {},
      onCycleAbRepeat: () {},
      onLongPressAbRepeat: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  group('PlayerControlsRow combined play-mode icon', () {
    testWidgets('tapping it fires onCyclePlayMode exactly once',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsRow(
            data: _dataFor(onCyclePlayMode: () => calls++),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('shows the repeat icon (dim) when off', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerControlsRow(data: _dataFor())),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byIcon(Icons.repeat_one), findsNothing);
      expect(find.byIcon(Icons.shuffle), findsNothing);
    });

    testWidgets('shows repeat_one when repeatMode is one', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsRow(
            data: _dataFor(repeatMode: RepeatMode.one),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.repeat_one), findsOneWidget);
      expect(find.byIcon(Icons.shuffle), findsNothing);
    });

    testWidgets(
        'shows the shuffle icon when shuffle is enabled, taking '
        'priority over any repeat glyph', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsRow(
            data: _dataFor(shuffleEnabled: true, repeatMode: RepeatMode.all),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.shuffle), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsNothing);
      expect(find.byIcon(Icons.repeat_one), findsNothing);
    });

    testWidgets(
        'the full 6-button standard layout does not overflow at a real '
        'narrow phone width — item 47\'s TV-mode verification found this '
        'exact overflow (~4.6px on a real ~360dp device) and left it '
        'unfixed at the time; FittedBox(scaleDown) is the fix', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(MaterialApp(
        home:
            Scaffold(body: Center(child: PlayerControlsRow(data: _dataFor()))),
      ));
      await tester.pump();

      expect(errors, isEmpty,
          reason: 'a RenderFlex overflow (or any other render error) at a '
              'narrow width means the button row is clipping/overflowing '
              'again');
      // All six buttons are still genuinely present and tappable —
      // scaleDown shrinks the row, it doesn't drop any of its children.
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
    });
  });

  group('PlayerControlsRow icon style (OmnisIconStyle.current)', () {
    // OmnisIconStyle.current is a plain global static (mirrors
    // OmnisMotion.styleMultiplier — see that class's own doc comment for
    // why this codebase deliberately has no BuildContext-based theme
    // lookup), so any test that changes it must restore the default
    // before the next test runs, or it leaks into unrelated tests in
    // this same file that assume the default `Icons.xxx` (filled) glyphs.
    testWidgets(
        'transport row glyphs (prev/next/repeat/seek) switch to the '
        'outlined variant when OmnisIconStyle.current is outlined',
        (tester) async {
      addTearDown(() => OmnisIconStyle.current = OmnisIconStyleKind.filled);
      OmnisIconStyle.current = OmnisIconStyleKind.outlined;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsRow(
            data: _dataFor(repeatMode: RepeatMode.one),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.skip_previous_outlined), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_outlined), findsOneWidget);
      expect(find.byIcon(Icons.repeat_one_outlined), findsOneWidget);
      expect(find.byIcon(Icons.replay_10_outlined), findsOneWidget);
      expect(find.byIcon(Icons.forward_10_outlined), findsOneWidget);
      // The filled defaults must be genuinely gone, not just
      // additionally present alongside the outlined ones.
      expect(find.byIcon(Icons.skip_previous), findsNothing);
      expect(find.byIcon(Icons.skip_next), findsNothing);
      expect(find.byIcon(Icons.repeat_one), findsNothing);
    });

    testWidgets(
        'play/pause stays an AnimatedIcon regardless of OmnisIconStyle.'
        'current — it has no outlined/rounded/sharp counterpart to switch '
        'to', (tester) async {
      addTearDown(() => OmnisIconStyle.current = OmnisIconStyleKind.filled);
      OmnisIconStyle.current = OmnisIconStyleKind.sharp;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerControlsRow(data: _dataFor())),
      ));
      await tester.pump();

      expect(find.byType(AnimatedIcon), findsOneWidget);
      final animatedIcon = tester.widget<AnimatedIcon>(find.byType(AnimatedIcon));
      expect(animatedIcon.icon, AnimatedIcons.play_pause);
    });

    testWidgets(
        'defaults to the plain filled Icons.xxx constants when '
        'OmnisIconStyle.current is left untouched', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerControlsRow(data: _dataFor())),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
    });
  });

  group('PlayerControlsRow accessibility', () {
    testWidgets(
        'every transport IconButton has a real tooltip/semantic label — '
        'previous, seek back/forward, play/pause (state-aware), next',
        (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerControlsRow(data: _dataFor())),
      ));
      await tester.pump();

      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.tooltip, allOf(isNotNull, isNotEmpty),
            reason: 'every transport IconButton must have a tooltip, not '
                'just an icon');
      }

      IconButton buttonWithIcon(IconData icon) => buttons.firstWhere((b) {
            // The play/pause button's icon is an AnimatedIcon, not a
            // plain Icon (see player_widgets.dart) — skip it rather than
            // casting unsafely, since only skip_previous/skip_next are
            // looked up by this helper.
            final i = b.icon;
            return i is Icon && i.icon == icon;
          });

      expect(buttonWithIcon(Icons.skip_previous).tooltip, 'Previous');
      expect(buttonWithIcon(Icons.skip_next).tooltip, 'Next');

      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
      );
      handle.dispose();
    });

    testWidgets('the play/pause tooltip flips with playing state',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerControlsRow(data: _dataFor(playing: false)),
        ),
      ));
      await tester.pump();

      final animatedIconButton = tester.widget<IconButton>(find.ancestor(
          of: find.byType(AnimatedIcon), matching: find.byType(IconButton)));
      expect(animatedIconButton.tooltip, 'Play');
    });
  });

  group('PlayerSleepTimerRow compact dropdown', () {
    testWidgets('renders nothing when no sleep timer plugin is available',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerSleepTimerRow(data: _dataFor())),
      ));
      await tester.pump();

      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
    });

    testWidgets(
        'inactive timer: opening the dropdown offers "Start sleep timer", '
        'and tapping it calls onStartSleepTimer', (tester) async {
      var startCalls = 0;
      final plugin = SleepTimerPlugin();
      addTearDown(plugin.stopTimer);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerSleepTimerRow(
            data: _dataFor(
              sleepTimerPlugin: plugin,
              onStartSleepTimer: () => startCalls++,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsNothing);

      await tester.tap(find.byIcon(Icons.bedtime_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Start sleep timer'), findsOneWidget);
      expect(find.text('Cancel timer'), findsNothing);

      await tester.tap(find.text('Start sleep timer'));
      await tester.pumpAndSettle();

      expect(startCalls, 1);
    });

    testWidgets(
        'active timer: shows the filled icon with a remaining-time badge, '
        'and the dropdown offers "Change duration" and "Cancel timer"',
        (tester) async {
      var cancelCalls = 0;
      final plugin = SleepTimerPlugin()..startTimer(const Duration(minutes: 5));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerSleepTimerRow(
            data: _dataFor(
              sleepTimerPlugin: plugin,
              onCancelSleepTimer: () => cancelCalls++,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.bedtime), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.bedtime));
      await tester.pumpAndSettle();

      expect(find.text('Change duration'), findsOneWidget);
      expect(find.text('Cancel timer'), findsOneWidget);

      await tester.tap(find.text('Cancel timer'));
      await tester.pumpAndSettle();

      expect(cancelCalls, 1);
      // The dropdown only forwards the tap via onCancelSleepTimer, same as
      // the real Now Playing wiring — the plugin's own timer isn't stopped
      // by this fake callback, so stop it directly to leave no pending
      // Timer behind for the test framework's invariant check.
      plugin.stopTimer();
    });
  });

  group('PlayerLyricsPanel text size setting', () {
    testWidgets('renders at bodyMedium by default (medium)', (tester) async {
      ThemeData? resolvedTheme;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            resolvedTheme = Theme.of(context);
            return PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeLyricsProvider(),
                lyricText: 'La la la',
              ),
            );
          }),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('La la la'));
      expect(
          text.style?.fontSize, resolvedTheme!.textTheme.bodyMedium?.fontSize);
    });

    testWidgets('renders larger text as the setting is raised', (tester) async {
      AppSettings.instance.lyricsTextSize = LyricsTextSize.extraLarge;
      ThemeData? resolvedTheme;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            resolvedTheme = Theme.of(context);
            return PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeLyricsProvider(),
                lyricText: 'La la la',
              ),
            );
          }),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('La la la'));
      expect(text.style?.fontSize,
          resolvedTheme!.textTheme.headlineSmall?.fontSize);
      expect(
        text.style!.fontSize!,
        greaterThan(resolvedTheme!.textTheme.bodyMedium!.fontSize!),
        reason: 'extraLarge must actually read larger than the default',
      );
    });

    // Regression coverage for the bug where a caller-supplied `style:`
    // fully replaced the size-driven TextStyle instead of layering on top
    // of it, silently disabling the Settings lyrics-text-size picker under
    // the default (Standard) layout. `PlayerLyricsPanel` no longer accepts
    // a raw `style:` override at all — only `color` and `fontWeight`,
    // which must always compose with `_sizeStyle(...)` via `.copyWith()`.
    for (final size in LyricsTextSize.values) {
      testWidgets(
          'lyricsTextSize.$size drives the actual rendered font size',
          (tester) async {
        AppSettings.instance.lyricsTextSize = size;
        ThemeData? resolvedTheme;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              resolvedTheme = Theme.of(context);
              return PlayerLyricsPanel(
                data: _dataFor(
                  lyricsPlugin: _FakeLyricsProvider(),
                  lyricText: 'La la la',
                ),
              );
            }),
          ),
        ));
        await tester.pump();

        final expectedFontSize = switch (size) {
          LyricsTextSize.small => resolvedTheme!.textTheme.bodySmall?.fontSize,
          LyricsTextSize.medium =>
            resolvedTheme!.textTheme.bodyMedium?.fontSize,
          LyricsTextSize.large =>
            resolvedTheme!.textTheme.titleMedium?.fontSize,
          LyricsTextSize.extraLarge =>
            resolvedTheme!.textTheme.headlineSmall?.fontSize,
        };

        final text = tester.widget<Text>(find.text('La la la'));
        expect(text.style?.fontSize, expectedFontSize,
            reason: 'the $size setting must actually change the rendered '
                'font size, not just be stored/loaded correctly');
      });
    }

    testWidgets('passing color does not affect the size-driven font size',
        (tester) async {
      AppSettings.instance.lyricsTextSize = LyricsTextSize.large;
      ThemeData? resolvedTheme;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            resolvedTheme = Theme.of(context);
            return PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeLyricsProvider(),
                lyricText: 'La la la',
              ),
              color: Colors.white,
            );
          }),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('La la la'));
      expect(text.style?.fontSize,
          resolvedTheme!.textTheme.titleMedium?.fontSize,
          reason: 'color must layer on top of the size-driven base style, '
              'not replace it');
      expect(text.style?.color, Colors.white);
    });

    testWidgets(
        'karaoke-mode bold composes with a non-default text size — bold '
        'AND larger, not one replacing the other', (tester) async {
      AppSettings.instance.lyricsTextSize = LyricsTextSize.extraLarge;
      ThemeData? resolvedTheme;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            resolvedTheme = Theme.of(context);
            return PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeLyricsProvider(),
                lyricText: 'La la la',
              ),
              color: Colors.white,
              fontWeight: FontWeight.bold,
            );
          }),
        ),
      ));
      await tester.pump();

      final text = tester.widget<Text>(find.text('La la la'));
      expect(text.style?.fontSize,
          resolvedTheme!.textTheme.headlineSmall?.fontSize,
          reason: 'the extraLarge size must still take effect with bold on');
      expect(text.style?.fontWeight, FontWeight.bold);
      expect(text.style?.color, Colors.white);
    });
  });

  group('activeLyricLineIndex', () {
    // First line starts at 10s, not 0s — representing a real intro before
    // the synced lyrics begin, so "before the first line's own timestamp"
    // is actually reachable (a first line at 0s can never have a position
    // "before" it).
    final lines = [
      const LyricLine(timestamp: Duration(seconds: 10), text: 'a'),
      const LyricLine(timestamp: Duration(seconds: 20), text: 'b'),
      const LyricLine(timestamp: Duration(seconds: 30), text: 'c'),
    ];

    test('null before the first line\'s own timestamp — nothing has '
        'started yet, matching LyricsPlugin.currentLyricFor\'s own guard',
        () {
      expect(activeLyricLineIndex(lines, const Duration(seconds: 5)), null);
    });

    test('the exact timestamp of a line selects that line', () {
      expect(activeLyricLineIndex(lines, const Duration(seconds: 20)), 1);
    });

    test('between two timestamps selects the earlier (still-active) line',
        () {
      expect(activeLyricLineIndex(lines, const Duration(seconds: 25)), 1);
    });

    test('past the last line\'s timestamp selects the last line', () {
      expect(activeLyricLineIndex(lines, const Duration(seconds: 999)), 2);
    });

    test('an empty list is always null', () {
      expect(activeLyricLineIndex(const [], const Duration(seconds: 5)), null);
    });
  });

  group('PlayerLyricsPanel synced lyrics', () {
    testWidgets(
        'renders every synced line at once, not just the current one',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeSyncedLyricsProvider(_manySyncedLines()),
                position: const Duration(seconds: 32),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Every line is a real widget in the tree — a `ListView` lazily
      // builds only what's near the viewport, so this only asserts on
      // lines close to the (centered) active one rather than every one
      // of the 15.
      expect(find.text('Line 6'), findsOneWidget); // the active line itself
      expect(find.text('Line 5'), findsOneWidget);
      expect(find.text('Line 7'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget,
          reason: 'synced lyrics render as a scrolling list, not the old '
              'single Text block');
    });

    testWidgets('highlights the line active at the given position',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeSyncedLyricsProvider(_manySyncedLines()),
                // 32s: line index 6 starts at 30s, index 7 at 35s — 6 is
                // active.
                position: const Duration(seconds: 32),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final active = tester.widget<Text>(find.text('Line 6'));
      final inactive = tester.widget<Text>(find.text('Line 5'));

      expect(active.style?.fontWeight, FontWeight.bold);
      expect(inactive.style?.fontWeight, isNot(FontWeight.bold));
      expect(active.style?.color, isNot(equals(inactive.style?.color)),
          reason: 'the active line must read as visually distinct from '
              'every inactive one');
    });

    testWidgets(
        'auto-scrolls so the active line lands vertically centered in '
        'the viewport', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: PlayerLyricsPanel(
              data: _dataFor(
                lyricsPlugin: _FakeSyncedLyricsProvider(_manySyncedLines()),
                position: const Duration(seconds: 32), // active index 6
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.hasClients, isTrue);

      const lineExtent = 44.0;
      const activeIndex = 6;
      final viewport = controller.position.viewportDimension;
      final expectedTarget = ((activeIndex * lineExtent) -
              (viewport / 2) +
              (lineExtent / 2))
          .clamp(0.0, controller.position.maxScrollExtent);

      expect(controller.offset, closeTo(expectedTarget, 0.5));
      expect(expectedTarget, greaterThan(0),
          reason: 'the fixture is set up so the active line is genuinely '
              'below the fold — a target of 0 here would mean the test '
              'can\'t actually distinguish "scrolled correctly" from '
              '"never scrolled at all"');
    });

    testWidgets(
        'falls back to the existing single-block rendering when nothing '
        'is synced for this track', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerLyricsPanel(
            data: _dataFor(
              lyricsPlugin: _FakeLyricsProvider(),
              lyricText: 'La la la',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('La la la'), findsOneWidget);
      expect(find.byType(ListView), findsNothing,
          reason: 'a provider with no ISyncedLyricsProvider capability '
              'must render exactly like before this feature existed');
    });
  });

  group('PlayerProgressBar seek-position visualizer overlay', () {
    testWidgets('no overlay when no visualizer plugin is available',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayerProgressBar(data: _dataFor())),
      ));
      await tester.pump();

      expect(find.byType(SeekPositionVisualizer), findsNothing);
    });

    testWidgets(
        'overlays a SeekPositionVisualizer when a visualizer '
        'plugin is available', (tester) async {
      final provider = _FakeVisualizerProvider();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerProgressBar(
            data: _dataFor(visualizerPlugin: provider),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(SeekPositionVisualizer), findsOneWidget);
      provider.close();
    });

    testWidgets('the overlay never blocks the seek gesture underneath it',
        (tester) async {
      final provider = _FakeVisualizerProvider();
      Duration? sought;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerProgressBar(
            data: _dataFor(
              visualizerPlugin: provider,
              onSeek: (d) => sought = d,
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(Slider));
      await tester.pump();

      expect(sought, isNotNull,
          reason: 'IgnorePointer on the overlay must let the Slider '
              'underneath still receive the tap');
      provider.close();
    });
  });

  group('PlayerExtrasRow Queue button', () {
    testWidgets('always renders and calls onOpenQueue when tapped, '
        'regardless of equalizer/visualizer availability', (tester) async {
      var opened = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlayerExtrasRow(
              data: _dataFor(onOpenQueue: () => opened = true)),
        ),
      ));
      await tester.pump();

      expect(find.text('Queue'), findsOneWidget);

      await tester.tap(find.text('Queue'));
      await tester.pump();

      expect(opened, isTrue);
    });
  });
}
