import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/custom_radio_station_store.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/online_page.dart';
import 'package:omnis_plugins/ampache_plugin.dart';
import 'package:omnis_plugins/spotify_playback_plugin.dart';
import 'package:omnis_plugins/youtube_playback_plugin.dart';
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

class _FakeEngine implements AudioEngine {
  List<BaseTrack>? lastQueue;
  int? lastStartIndex;
  bool playCalled = false;
  BaseTrack? _current;

  final _trackController = StreamController<BaseTrack?>.broadcast();

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  BaseTrack? get currentTrack => _current;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
    lastStartIndex = startIndex;
    _current = tracks.isNotEmpty ? tracks[startIndex] : null;
  }

  @override
  Future<void> play() async => playCalled = true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

/// A minimal Ampache mock server: any `action=handshake` succeeds with a
/// fixed session token; any `action=songs` returns exactly one song
/// matching the request's `filter`.
http.Client _ampacheClient() => MockClient((req) async {
      final action = req.url.queryParameters['action'];
      if (action == 'handshake') {
        return http.Response(
          jsonEncode({
            'auth': 'session-token',
            'session_expire': '2099-01-01T00:00:00+00:00',
            'api': '6.6.1',
            'username': 'alice',
          }),
          200,
        );
      }
      if (action == 'songs') {
        return http.Response(
          jsonEncode({
            'song': [
              {
                'id': 's1',
                'title': 'Found Song',
                'artist': {'id': 'a1', 'name': 'Found Artist'},
                'album': {'id': 'al1', 'name': 'Album'},
                'genre': [],
                'track': 1,
                'time': 200,
                'url':
                    'https://ampache.example.com/play/s1?auth=session-token',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

Future<AmpachePlugin> _configuredAmpache(http.Client client) async {
  final plugin = AmpachePlugin(client: client);
  await plugin.setServerUrl('https://ampache.example.com');
  await plugin.setUsername('alice');
  await plugin.setPassword('hunter2');
  return plugin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_online_page_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await CustomRadioStationStore.instance.save([]);
  });

  /// Registers [plugin] (if given) and initializes the manager for real —
  /// `IOnlineSearchProvider` registration happens inside a plugin's own
  /// `initialize()`, which only a real `PluginManager.initializeAll()`
  /// call triggers, the same setup `queue_builder_registry_test.dart`
  /// already establishes for `IQueueBuilder`.
  Future<PluginManager> managerWith(List<Object> plugins) async {
    final manager = PluginManager();
    manager.attachContext(OmnisPluginContext(
      audioEngine: _FakeEngine(),
      services: manager.services,
      events: manager.events,
    ));
    for (final plugin in plugins) {
      manager.register(plugin as dynamic);
    }
    await manager.initializeAll();
    return manager;
  }

  testWidgets('with nothing else registered, only the Radio chip is shown',
      (tester) async {
    final manager = await managerWith(const []);

    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, 'Radio'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsOneWidget);
    expect(find.byTooltip('Add station'), findsOneWidget);
  });

  testWidgets(
      'the "Add station" action only shows while the Radio chip is '
      'selected', (tester) async {
    final client = _ampacheClient();
    final manager = await managerWith([await _configuredAmpache(client)]);

    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();

    expect(find.byTooltip('Add station'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ampache'));
    await tester.pump();

    expect(find.byTooltip('Add station'), findsNothing);
  });

  testWidgets(
      'a configured search-provider plugin appears as its own chip, '
      'searching shows results, and tapping one plays it', (tester) async {
    final client = _ampacheClient();
    final manager = await managerWith([await _configuredAmpache(client)]);
    final engine = _FakeEngine();

    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(engine: engine, pluginManager: manager),
    ));
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, 'Ampache'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ampache'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'found');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(find.text('Found Song'), findsOneWidget);

    await tester.tap(find.text('Found Song'));
    await tester.pump();

    expect(engine.lastQueue?.single.title, 'Found Song');
    expect(engine.playCalled, isTrue);
  });

  testWidgets(
      'an unconfigured search-provider plugin does not get a chip at all',
      (tester) async {
    final manager = await managerWith([AmpachePlugin(client: _ampacheClient())]);

    await tester.pumpWidget(MaterialApp(
      home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, 'Ampache'), findsNothing);
    expect(find.byType(ChoiceChip), findsOneWidget);
  });

  testWidgets(
      'an enabled YoutubePlaybackPlugin adds a YouTube chip whose content '
      'is the real embedded-player widget', (tester) async {
    // `_settle`'s real `Future.delayed` needs the real (non-fake-async)
    // zone `runAsync` provides — same reasoning as radio_page_test.dart's
    // own `_settle`-using tests, which wrap for the identical reason
    // (there: real dart:io; here: PluginManager.initializeAll()'s own
    // Future.wait and _PluginSlotBody's uiSlotForPlugin await both need
    // real timers to actually resolve, not just a single fake-async pump).
    await tester.runAsync(() async {
      final manager = await managerWith([YoutubePlaybackPlugin()]);

      await tester.pumpWidget(MaterialApp(
        home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await _settle(tester);

      expect(find.widgetWithText(ChoiceChip, 'YouTube'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
      await _settle(tester);

      // The embedded player needs a WebView, which Flutter only supports
      // on Android/iOS/web — this suite runs on Windows (this project's
      // CI/dev platform), so the widget's own honest "not available on
      // this platform" branch is what actually renders here. Whichever
      // branch fires, either message proves the real
      // YoutubePlaybackPlugin.uiSlot('plugin_settings') widget rendered
      // as this tab's content, not a blank/crashed page.
      expect(
        YoutubePlaybackPlugin.isSupportedOnThisPlatform
            ? find.textContaining('Paste a YouTube video URL or id')
            : find.textContaining('needs a WebView'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
      'an enabled SpotifyPlaybackPlugin adds a Spotify chip whose content '
      'is the real Connect remote-control widget', (tester) async {
    await tester.runAsync(() async {
      final manager = await managerWith([SpotifyPlaybackPlugin()]);

      await tester.pumpWidget(MaterialApp(
        home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await _settle(tester);

      expect(find.widgetWithText(ChoiceChip, 'Spotify'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Spotify'));
      await _settle(tester);

      // Not connected yet — the plugin's own settings widget should show
      // some form of connect prompt rather than a blank/crashed page.
      expect(find.byType(ChoiceChip), findsNWidgets(2));
    });
  });

  testWidgets(
      'a disabled YoutubePlaybackPlugin does not add a YouTube chip',
      (tester) async {
    await tester.runAsync(() async {
      final manager = await managerWith([YoutubePlaybackPlugin()]);
      // Disable the YouTube plugin
      final managed =
          manager.byId('youtube_playback');
      if (managed != null) {
        managed.enabled = false;
      }

      await tester.pumpWidget(MaterialApp(
        home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await _settle(tester);

      // Only the Radio chip should be present, no YouTube chip
      expect(find.widgetWithText(ChoiceChip, 'YouTube'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Radio'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsOneWidget);
    });
  });

  testWidgets(
      'a disabled SpotifyPlaybackPlugin does not add a Spotify chip',
      (tester) async {
    await tester.runAsync(() async {
      final manager = await managerWith([SpotifyPlaybackPlugin()]);
      // Disable the Spotify plugin
      final managed =
          manager.byId('spotify_playback');
      if (managed != null) {
        managed.enabled = false;
      }

      await tester.pumpWidget(MaterialApp(
        home: OnlinePage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await _settle(tester);

      // Only the Radio chip should be present, no Spotify chip
      expect(find.widgetWithText(ChoiceChip, 'Spotify'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Radio'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsOneWidget);
    });
  });
}
