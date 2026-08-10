import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/player_layouts/player_widgets.dart';
import 'package:omnis_plugins/sleep_timer_plugin.dart';
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
  bool shuffleEnabled = false,
  RepeatMode repeatMode = RepeatMode.off,
  SleepTimerPlugin? sleepTimerPlugin,
  VoidCallback? onCyclePlayMode,
  VoidCallback? onStartSleepTimer,
  VoidCallback? onCancelSleepTimer,
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
      sleepTimerPlugin: sleepTimerPlugin,
      lyricText: null,
      crossfadeStatusText: null,
      shuffleEnabled: shuffleEnabled,
      repeatMode: repeatMode,
      loopAMarker: null,
      abRepeatRange: null,
      onPlayPause: () {},
      onNext: () {},
      onPrevious: () {},
      onSeek: (_) {},
      onOpenEqualizer: () {},
      onEditLyrics: () {},
      onActivateVisualizer: () {},
      onStartSleepTimer: onStartSleepTimer ?? () {},
      onCancelSleepTimer: onCancelSleepTimer,
      onCyclePlayMode: onCyclePlayMode ?? () {},
      onCycleAbRepeat: () {},
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

    testWidgets('shows the shuffle icon when shuffle is enabled, taking '
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
}
