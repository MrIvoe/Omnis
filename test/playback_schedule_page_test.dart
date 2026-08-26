import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/playback_schedule.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/settings/playback_schedule_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Only used to satisfy `OmnisPluginContext`'s constructor — nothing
/// under test here ever calls through to a real `AudioEngine` member
/// (`_FakeRadioStationsPlugin.initialize` only touches `context.services`),
/// same "stub only what's used" shape this session's other fakes follow.
class _FakeEngine implements AudioEngine {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// A minimal stand-in for `RadioPlugin`'s [ICustomRadioStationProvider]
/// registration — a spy rather than the real `omnis_plugins.RadioPlugin`,
/// the same "app-side test uses a fake plugin implementing the
/// interface, never the plugin-owned store directly" shape
/// `home_page_plugin_destinations_test.dart`'s own
/// `_SpyHomeCustomizerPlugin`/`_SpyMoodPlayerPlugin` already establish
/// for `IHomeCustomizer`/`IMoodPlayer`.
class _FakeRadioStationsPlugin extends MusicPlugin
    implements ICustomRadioStationProvider {
  final List<(String id, String name)> summaries;

  _FakeRadioStationsPlugin({this.summaries = const []});

  @override
  Future<List<(String id, String name)>> customStationSummaries() async =>
      summaries;

  // Not exercised by this page (only MainCore's scheduler calls this) —
  // never called here, so a fixed null is enough.
  @override
  Future<BaseTrack?> trackForCustomStation(String stationId) async => null;

  @override
  String get id => 'fake_radio_stations';
  @override
  String get name => 'Fake Radio Stations';
  @override
  String get description => 'test plugin';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'test';
  @override
  Future<void> initialize() async {
    context?.services.register(ICustomRadioStationProvider, this);
  }
  @override
  Future<void> onTrackStart(BaseTrack track) async {}
  @override
  Future<void> onLibraryScan(String file) async {}
  @override
  dynamic uiSlot(String locationID) => null;
  @override
  Future<void> dispose() async {}
}

/// Same reasoning as other pages that read real (fake-path-provider-
/// backed) stores from `initState` — a bare `pumpAndSettle()` doesn't
/// give that real dart:io a chance to finish, and a `DropdownButton`/
/// popup needs a trailing `pumpAndSettle()` of its own to finish
/// animating open.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // `PluginManager.register` reads `AppSettings.instance
    // .isPluginDisabled(...)` to seed a newly-registered plugin's
    // `enabled` flag — without a fresh mock backing store per test, that
    // reads whatever shared_preferences state happens to carry over from
    // an earlier test in the same process, the classic cross-test
    // contamination gotcha `playlist_page_test.dart`'s own setUp already
    // guards against the same way.
    SharedPreferences.setMockInitialValues({});
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_schedule_page_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await PlaybackScheduleStore.instance.save([]);
    await PlaylistStore.instance.save([]);
  });

  /// Wires a [PluginManager] with a [_FakeRadioStationsPlugin] registered
  /// and initialized, so `pluginManager.services
  /// .get<ICustomRadioStationProvider>()` resolves to it — the fixture
  /// every "scheduled radio" test below needs. Tests that don't care
  /// about radio stations at all just pass a bare `PluginManager()`
  /// straight to `pumpPage`, matching how [_stationName] degrades to
  /// "not found" with nothing registered.
  Future<PluginManager> managerWithStations(
      List<(String id, String name)> summaries) async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    manager.register(_FakeRadioStationsPlugin(summaries: summaries));
    await manager.initializeAll();
    return manager;
  }

  Future<void> pumpPage(WidgetTester tester,
      {PluginManager? pluginManager}) async {
    await tester.pumpWidget(MaterialApp(
      home: PlaybackSchedulePage(
          pluginManager: pluginManager ?? PluginManager()),
    ));
    await _settle(tester);
  }

  testWidgets('an empty schedule list shows the empty state', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);

      expect(find.textContaining('No schedules yet'), findsOneWidget);
    });
  });

  testWidgets('adding a schedule via the editor persists it and shows it '
      'in the list', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Morning Wake-up');
      // Save's onPressed is null (disabled) until the name is non-empty
      // — a real pump is needed for that setState to actually rebuild
      // the button as enabled before tapping it.
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);

      expect(find.text('Morning Wake-up'), findsOneWidget);
      final saved = await PlaybackScheduleStore.instance.load();
      expect(saved.single.name, 'Morning Wake-up');
      expect(saved.single.weekdays, {1, 2, 3, 4, 5});
    });
  });

  testWidgets('Save is disabled until a name is entered', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester);

      final saveButton =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(saveButton.onPressed, isNull);
    });
  });

  testWidgets('deselecting every day disables Save — an empty weekdays '
      'set is never a valid schedule', (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);

      await tester.tap(find.byIcon(Icons.add));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Test');
      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']) {
        await tester.tap(find.widgetWithText(FilterChip, day));
        await tester.pump();
      }

      final saveButton =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(saveButton.onPressed, isNull);
    });
  });

  testWidgets('toggling the enable switch persists the change',
      (tester) async {
    await tester.runAsync(() async {
      await PlaybackScheduleStore.instance.add(PlaybackSchedule(
        id: 's1',
        name: 'Evening',
        minuteOfDay: 1200,
        weekdays: const {6, 7},
        enabled: true,
        createdAt: DateTime(2026, 1, 1),
      ));

      await pumpPage(tester);
      await tester.tap(find.byType(Switch));
      await _settle(tester);

      final saved = await PlaybackScheduleStore.instance.load();
      expect(saved.single.enabled, isFalse);
    });
  });

  testWidgets('deleting a schedule removes it from the store and the '
      'list', (tester) async {
    await tester.runAsync(() async {
      await PlaybackScheduleStore.instance.add(PlaybackSchedule(
        id: 's1',
        name: 'Evening',
        minuteOfDay: 1200,
        weekdays: const {6, 7},
        enabled: true,
        createdAt: DateTime(2026, 1, 1),
      ));

      await pumpPage(tester);
      expect(find.text('Evening'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await _settle(tester);

      expect(find.text('Evening'), findsNothing);
      expect(await PlaybackScheduleStore.instance.load(), isEmpty);
    });
  });

  testWidgets('a schedule with a playlist shows the playlist name in its '
      'subtitle', (tester) async {
    await tester.runAsync(() async {
      await PlaylistStore.instance.save([
        Playlist(
          id: 'p1',
          name: 'Road Trip',
          trackIds: const [],
          createdAt: DateTime(2026, 1, 1),
        ),
      ]);
      await PlaybackScheduleStore.instance.add(PlaybackSchedule(
        id: 's1',
        name: 'Morning',
        minuteOfDay: 450,
        weekdays: const {1},
        enabled: true,
        playlistId: 'p1',
        createdAt: DateTime(2026, 1, 1),
      ));

      await pumpPage(tester);

      expect(find.textContaining('Road Trip'), findsOneWidget);
    });
  });

  group('PlaybackScheduleAction (item 50, "stop playback at a time")', () {
    testWidgets('a new schedule defaults to Play, with the playlist '
        'picker visible', (tester) async {
      await tester.runAsync(() async {
        await pumpPage(tester);

        await tester.tap(find.byIcon(Icons.add));
        await _settle(tester);

        expect(find.text('Playlist or station (optional)'), findsOneWidget);
      });
    });

    testWidgets('switching to Stop hides the playlist picker', (tester) async {
      await tester.runAsync(() async {
        await pumpPage(tester);

        await tester.tap(find.byIcon(Icons.add));
        await _settle(tester);
        await tester.tap(find.text('Stop'));
        await tester.pump();

        expect(find.text('Playlist or station (optional)'), findsNothing);
      });
    });

    testWidgets('saving a Stop schedule persists action: stop and no '
        'playlistId', (tester) async {
      await tester.runAsync(() async {
        await pumpPage(tester);

        await tester.tap(find.byIcon(Icons.add));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'Bedtime');
        await tester.tap(find.text('Stop'));
        await tester.pump();
        await tester.tap(find.text('Save'));
        await _settle(tester);

        final saved = await PlaybackScheduleStore.instance.load();
        expect(saved.single.action, PlaybackScheduleAction.stop);
        expect(saved.single.playlistId, isNull);
      });
    });

    testWidgets('a Stop schedule\'s row subtitle says "Stops playback"',
        (tester) async {
      await tester.runAsync(() async {
        await PlaybackScheduleStore.instance.add(PlaybackSchedule(
          id: 's1',
          name: 'Bedtime',
          minuteOfDay: 1320,
          weekdays: const {1, 2, 3, 4, 5},
          enabled: true,
          action: PlaybackScheduleAction.stop,
          createdAt: DateTime(2026, 1, 1),
        ));

        await pumpPage(tester);

        expect(find.textContaining('Stops playback'), findsOneWidget);
      });
    });

    testWidgets('editing an existing Stop schedule preselects Stop and '
        'still hides the playlist picker', (tester) async {
      await tester.runAsync(() async {
        await PlaybackScheduleStore.instance.add(PlaybackSchedule(
          id: 's1',
          name: 'Bedtime',
          minuteOfDay: 1320,
          weekdays: const {1, 2, 3, 4, 5},
          enabled: true,
          action: PlaybackScheduleAction.stop,
          createdAt: DateTime(2026, 1, 1),
        ));

        await pumpPage(tester);
        await tester.tap(find.text('Bedtime'));
        await _settle(tester);

        expect(find.text('Playlist or station (optional)'), findsNothing);
        final segmentedButton =
            tester.widget<SegmentedButton<PlaybackScheduleAction>>(
                find.byType(SegmentedButton<PlaybackScheduleAction>));
        expect(segmentedButton.selected, {PlaybackScheduleAction.stop});
      });
    });
  });

  group('scheduled radio (item 50, "scheduled radio")', () {
    testWidgets('the editor lists a saved custom station, selecting it '
        'and saving persists radioStationId and leaves playlistId null',
        (tester) async {
      await tester.runAsync(() async {
        final manager = await managerWithStations([('chill-fm', 'Chill FM')]);

        await pumpPage(tester, pluginManager: manager);
        await tester.tap(find.byIcon(Icons.add));
        await _settle(tester);
        await tester.enterText(find.byType(TextField), 'Wake to radio');
        await tester.pump();

        await tester.tap(find.text('Playlist or station (optional)'));
        await _settle(tester);
        await tester.tap(find.text('Chill FM (radio)').last);
        await _settle(tester);
        await tester.tap(find.text('Save'));
        await _settle(tester);

        final saved = await PlaybackScheduleStore.instance.load();
        expect(saved.single.radioStationId, 'chill-fm');
        expect(saved.single.playlistId, isNull);
      });
    });

    testWidgets('a schedule with a radio station shows "Plays radio: '
        '<name>" in its subtitle', (tester) async {
      await tester.runAsync(() async {
        final manager = await managerWithStations([('chill-fm', 'Chill FM')]);
        await PlaybackScheduleStore.instance.add(PlaybackSchedule(
          id: 's1',
          name: 'Morning',
          minuteOfDay: 450,
          weekdays: const {1},
          enabled: true,
          radioStationId: 'chill-fm',
          createdAt: DateTime(2026, 1, 1),
        ));

        await pumpPage(tester, pluginManager: manager);

        expect(find.textContaining('Plays radio: Chill FM'), findsOneWidget);
      });
    });

    testWidgets('a schedule whose radio station has since been deleted '
        'shows a "(deleted station)" placeholder instead of crashing',
        (tester) async {
      await tester.runAsync(() async {
        await PlaybackScheduleStore.instance.add(PlaybackSchedule(
          id: 's1',
          name: 'Morning',
          minuteOfDay: 450,
          weekdays: const {1},
          enabled: true,
          radioStationId: 'no-longer-exists',
          createdAt: DateTime(2026, 1, 1),
        ));

        // No ICustomRadioStationProvider registered at all — the same
        // "deleted/never-registered station" shape a bare PluginManager
        // (Radio plugin disabled/uninstalled) already produces, since
        // _stationName only ever finds a name for an id actually present
        // in the provider's summaries.
        await pumpPage(tester);

        expect(find.textContaining('(deleted station)'), findsOneWidget);
      });
    });

    testWidgets('switching the picker from a radio station to a playlist '
        'clears the radio station selection', (tester) async {
      await tester.runAsync(() async {
        await PlaylistStore.instance.save([
          Playlist(
            id: 'p1',
            name: 'Road Trip',
            trackIds: const [],
            createdAt: DateTime(2026, 1, 1),
          ),
        ]);
        final manager = await managerWithStations([('chill-fm', 'Chill FM')]);
        await PlaybackScheduleStore.instance.add(PlaybackSchedule(
          id: 's1',
          name: 'Morning',
          minuteOfDay: 450,
          weekdays: const {1},
          enabled: true,
          radioStationId: 'chill-fm',
          createdAt: DateTime(2026, 1, 1),
        ));

        await pumpPage(tester, pluginManager: manager);
        await tester.tap(find.text('Morning'));
        await _settle(tester);
        await tester.tap(find.text('Playlist or station (optional)'));
        await _settle(tester);
        await tester.tap(find.text('Road Trip').last);
        await _settle(tester);
        await tester.tap(find.text('Save'));
        await _settle(tester);

        final saved = await PlaybackScheduleStore.instance.load();
        expect(saved.single.playlistId, 'p1');
        expect(saved.single.radioStationId, isNull);
      });
    });
  });
}
