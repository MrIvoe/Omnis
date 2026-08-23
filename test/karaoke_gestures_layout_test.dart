import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/lyric_line.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/player_layouts/karaoke_gestures_layout.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A provider that also implements the separate, optional
/// `ISyncedLyricsProvider` capability — see that interface's own doc in
/// `service_interfaces.dart` for why it's a second interface rather than
/// a method added onto `ILyricsProvider` itself.
class _FakeSyncedLyricsProvider implements ILyricsProvider, ISyncedLyricsProvider {
  final List<LyricLine> lines;

  _FakeSyncedLyricsProvider(this.lines);

  @override
  String currentLyricFor(BaseTrack track, Duration position) =>
      'single-block fallback — should not render when synced lines exist';

  @override
  bool hasLyrics(BaseTrack track) => lines.isNotEmpty;

  @override
  List<LyricLine>? syncedLyricsFor(BaseTrack track) => lines;
}

/// Fifteen lines, five seconds apart (0s..70s) — enough total content
/// (15 * 72px karaoke line extent = 1080px) to genuinely overflow a
/// modest test viewport.
List<LyricLine> _manySyncedLines() => [
      for (var i = 0; i < 15; i++)
        LyricLine(timestamp: Duration(seconds: i * 5), text: 'Line $i'),
    ];

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
  ILyricsProvider? lyricsPlugin,
  String? lyricText,
  Duration position = const Duration(seconds: 30),
}) =>
    PlayerLayoutData(
      track: _track(),
      position: position,
      duration: const Duration(seconds: 180),
      playing: true,
      buffering: false,
      settings: AppSettings.instance,
      pluginManager: PluginManager(),
      lyricsPlugin: lyricsPlugin,
      equalizerPlugin: null,
      visualizerPlugin: null,
      sleepTimerPlugin: null,
      lyricText: lyricText,
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

  tearDown(PlatformCapabilities.resetOverridesForTesting);

  // A tall, wide fixed viewport rather than simulated scroll gestures —
  // `tester.scrollUntilVisible`/`dragUntilVisible` are known to throw a
  // spurious "Bad state: No element" against a ListView's sliver cache
  // extent even for a target confirmed present via a plain
  // `find(...).evaluate()` check (a real bug already found and fixed in a
  // sibling PR this same batch).
  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  group('KaraokeGesturesLayout synced lyrics', () {
    testWidgets(
        'renders the synced lyric list, with the active line highlighted',
        (tester) async {
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(
            context,
            _dataFor(
              lyricsPlugin: _FakeSyncedLyricsProvider(_manySyncedLines()),
              position: const Duration(seconds: 32), // active index 6
            ),
          );
        }),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget,
          reason: 'synced lyrics render as a scrolling list, matching the '
              'layout\'s own "current line highlighted" description for '
              'real, not just for a single visible line');
      expect(find.text('Line 6'), findsOneWidget);

      final active = tester.widget<Text>(find.text('Line 6'));
      final inactive = tester.widget<Text>(find.text('Line 5'));
      expect(active.style?.color, isNot(equals(inactive.style?.color)));
    });

    testWidgets('auto-scrolls so the active line is centered', (tester) async {
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(
            context,
            _dataFor(
              lyricsPlugin: _FakeSyncedLyricsProvider(_manySyncedLines()),
              position: const Duration(seconds: 32), // active index 6
            ),
          );
        }),
      );
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.hasClients, isTrue);

      const lineExtent = 72.0;
      const activeIndex = 6;
      final viewport = controller.position.viewportDimension;
      final expectedTarget = ((activeIndex * lineExtent) -
              (viewport / 2) +
              (lineExtent / 2))
          .clamp(0.0, controller.position.maxScrollExtent);

      expect(controller.offset, closeTo(expectedTarget, 0.5));
    });

    testWidgets(
        'falls back to the existing single-line rendering when nothing is '
        'synced for this track', (tester) async {
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(
            context,
            _dataFor(lyricsPlugin: null, lyricText: null),
          );
        }),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsNothing);
      expect(
        find.text('The Lyrics plugin is disabled — enable it in Settings.'),
        findsOneWidget,
      );
    });
  });

  group('desktop-primary platforms (Task 5): swipe-as-shortcut is hidden',
      () {
    testWidgets(
        'onHorizontalDragEnd is null on a desktop-primary platform — a '
        'mouse "drag" is not a gesture desktop users reach for',
        (tester) async {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(context, _dataFor());
        }),
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
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(context, _dataFor());
        }),
      );

      final detector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(detector.onHorizontalDragEnd, isNotNull);
    });

    testWidgets(
        'onTap (play/pause) stays wired on a desktop-primary platform — a '
        'mouse click is still a real tap', (tester) async {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(context, _dataFor());
        }),
      );

      final detector = tester.widget<GestureDetector>(
        find.byType(GestureDetector),
      );
      expect(detector.onTap, isNotNull);
    });

    testWidgets(
        'Next/Previous screen-reader actions stay wired on a '
        'desktop-primary platform regardless of swipe being hidden from '
        'sighted users', (tester) async {
      PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
      await pumpTall(
        tester,
        Builder(builder: (context) {
          return KaraokeGesturesLayout().build(context, _dataFor());
        }),
      );

      final semanticsWidget = tester.widget<Semantics>(find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.customSemanticsActions != null));
      final actions = semanticsWidget.properties.customSemanticsActions!;
      expect(actions.keys.map((a) => a.label),
          containsAll(['Next track', 'Previous track']));
    });
  });
}
