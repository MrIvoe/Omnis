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
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/radio_page.dart';
import 'package:omnis_plugins/favorites_plugin.dart';
import 'package:omnis_plugins/radio_plugin.dart';
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

/// Same reasoning as this session's other page tests: CustomRadioStationStore
/// reads/writes a real (fake-path-provider-backed) file — real dart:io —
/// so a plain `pump()` inside the fake-async test zone never gives that a
/// chance to actually finish, even inside `tester.runAsync()`. An explicit
/// real delay between two pumps does.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Spies on setQueue/play — same noSuchMethod-throws-if-unstubbed pattern
/// home_dashboard_page_test.dart's own `_FakeEngine` uses.
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

Map<String, dynamic> _station(String uuid, String name) => {
      'stationuuid': uuid,
      'name': name,
      'url_resolved': 'https://stream.example.com/$uuid.mp3',
      'url': null,
      'country': 'Testland',
      'tags': 'test',
      'codec': 'mp3',
      'bitrate': 128,
      'favicon': null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_radio_page_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await CustomRadioStationStore.instance.save([]);
  });

  testWidgets('shows a disabled message when the Radio plugin is not '
      'registered', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RadioPage(engine: _FakeEngine(), pluginManager: PluginManager()),
    ));
    await tester.pump();

    expect(
      find.text('The Internet Radio plugin is disabled in Settings.'),
      findsOneWidget,
    );
  });

  testWidgets('loads top stations on open and renders them', (tester) async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode([_station('a', 'Alpha FM'), _station('b', 'Beta FM')]),
        200,
      );
    });
    final manager = PluginManager();
    manager.register(RadioPlugin(client: client));

    await tester.pumpWidget(MaterialApp(
      home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Top stations'), findsOneWidget);
    expect(find.text('Alpha FM'), findsOneWidget);
    expect(find.text('Beta FM'), findsOneWidget);
  });

  testWidgets('an empty top-stations result shows the empty state, not a '
      'blank screen', (tester) async {
    final client = MockClient((req) async {
      return http.Response(jsonEncode([]), 200);
    });
    final manager = PluginManager();
    manager.register(RadioPlugin(client: client));

    await tester.pumpWidget(MaterialApp(
      home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('No stations available right now.'), findsOneWidget);
  });

  testWidgets('searching replaces the list with results and switches the '
      'section label', (tester) async {
    Uri? lastUri;
    final client = MockClient((req) async {
      lastUri = req.url;
      if (req.url.path.contains('search')) {
        return http.Response(jsonEncode([_station('j1', 'Jazz Station')]), 200);
      }
      return http.Response(jsonEncode([_station('t1', 'Top Station')]), 200);
    });
    final manager = PluginManager();
    manager.register(RadioPlugin(client: client));

    await tester.pumpWidget(MaterialApp(
      home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Top Station'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'jazz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    expect(lastUri!.queryParameters['name'], 'jazz');
    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('Jazz Station'), findsOneWidget);
    expect(find.text('Top Station'), findsNothing);
  });

  testWidgets('tapping a station sets it as the queue start index and '
      'plays', (tester) async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode([_station('a', 'Alpha FM'), _station('b', 'Beta FM')]),
        200,
      );
    });
    final manager = PluginManager();
    manager.register(RadioPlugin(client: client));
    final engine = _FakeEngine();

    await tester.pumpWidget(MaterialApp(
      home: RadioPage(engine: engine, pluginManager: manager),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Beta FM'));
    await tester.pump();

    expect(engine.lastStartIndex, 1);
    expect(engine.lastQueue?[1].title, 'Beta FM');
    expect(engine.lastQueue?[1].type, TrackType.radio);
    expect(engine.playCalled, isTrue);
  });

  group('favoriting a station (item 41)', () {
    testWidgets(
        'tapping the favorite icon marks a station favorited and fills '
        'the heart', (tester) async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode([_station('a', 'Alpha FM'), _station('b', 'Beta FM')]),
          200,
        );
      });
      final manager = PluginManager();
      manager.register(RadioPlugin(client: client));
      manager.register(FavoritesPlugin());

      await tester.pumpWidget(MaterialApp(
        home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite), findsNothing);

      await tester.tap(find.byIcon(Icons.favorite_border).first);
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(
        manager.bundled<FavoritesPlugin>()!.isFavorite('radio:a'),
        isTrue,
      );
    });

    testWidgets('tapping the favorite icon again un-favorites the station',
        (tester) async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode([_station('a', 'Alpha FM')]),
          200,
        );
      });
      final manager = PluginManager();
      manager.register(RadioPlugin(client: client));
      manager.register(FavoritesPlugin());

      await tester.pumpWidget(MaterialApp(
        home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(
        manager.bundled<FavoritesPlugin>()!.isFavorite('radio:a'),
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();

      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(
        manager.bundled<FavoritesPlugin>()!.isFavorite('radio:a'),
        isFalse,
      );
    });

    testWidgets(
        'tapping the favorite icon with the Favorites plugin disabled '
        'shows a message instead of crashing', (tester) async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode([_station('a', 'Alpha FM')]), 200);
      });
      final manager = PluginManager();
      manager.register(RadioPlugin(client: client));
      // Favorites deliberately not registered — same shape as it being
      // disabled in Settings, since `bundled` only ever sees registered
      // plugins.

      await tester.pumpWidget(MaterialApp(
        home: RadioPage(engine: _FakeEngine(), pluginManager: manager),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(find.text('The Favorites plugin is disabled in Settings.'),
          findsOneWidget);
    });
  });

  group('Custom radio stations (item 41)', () {
    Future<void> pumpNoStations(WidgetTester tester, AudioEngine engine) async {
      final client = MockClient((req) async => http.Response(jsonEncode([]), 200));
      final manager = PluginManager();
      manager.register(RadioPlugin(client: client));
      manager.register(FavoritesPlugin());
      await tester.pumpWidget(MaterialApp(
        home: RadioPage(engine: engine, pluginManager: manager),
      ));
      await _settle(tester);
    }

    testWidgets('a previously-saved custom station appears under "My '
        'stations" on open', (tester) async {
      await tester.runAsync(() async {
        await CustomRadioStationStore.instance
            .add('My Jazz Station', 'https://stream.example.com/jazz');

        await pumpNoStations(tester, _FakeEngine());

        expect(find.text('My stations'), findsOneWidget);
        expect(find.text('My Jazz Station'), findsOneWidget);
      });
    });

    testWidgets(
        'adding a station via the dialog persists it and shows it in '
        'the list', (tester) async {
      await tester.runAsync(() async {
        await pumpNoStations(tester, _FakeEngine());
        expect(find.text('My stations'), findsNothing);

        await tester.tap(find.byTooltip('Add station'));
        await _settle(tester);
        await tester.enterText(
            find.widgetWithText(TextField, 'Station name'), 'Deep House FM');
        await tester.enterText(find.widgetWithText(TextField, 'Stream URL'),
            'https://stream.example.com/deephouse');
        await tester.tap(find.text('Add'));
        await _settle(tester);

        expect(find.text('Deep House FM'), findsOneWidget);
        final saved = await CustomRadioStationStore.instance.load();
        expect(saved.single.name, 'Deep House FM');
      });
    });

    testWidgets(
        'adding a station with an invalid URL shows a message and does '
        'not persist anything', (tester) async {
      await tester.runAsync(() async {
        await pumpNoStations(tester, _FakeEngine());

        await tester.tap(find.byTooltip('Add station'));
        await _settle(tester);
        await tester.enterText(
            find.widgetWithText(TextField, 'Station name'), 'Bad Station');
        await tester.enterText(
            find.widgetWithText(TextField, 'Stream URL'), 'not a url');
        await tester.tap(find.text('Add'));
        await _settle(tester);

        expect(
          find.textContaining('Enter a station name and a valid'),
          findsOneWidget,
        );
        expect(await CustomRadioStationStore.instance.load(), isEmpty);
      });
    });

    testWidgets('tapping a custom station queues just that station and '
        'plays it', (tester) async {
      await tester.runAsync(() async {
        await CustomRadioStationStore.instance
            .add('My Jazz Station', 'https://stream.example.com/jazz');
        final engine = _FakeEngine();

        await pumpNoStations(tester, engine);

        await tester.tap(find.text('My Jazz Station'));
        await _settle(tester);

        expect(engine.lastQueue, hasLength(1));
        expect(engine.lastQueue!.single.title, 'My Jazz Station');
        expect(engine.lastQueue!.single.streamUrl,
            'https://stream.example.com/jazz');
        expect(engine.playCalled, isTrue);
      });
    });

    testWidgets('deleting a custom station removes it from the list and '
        'from persistence', (tester) async {
      await tester.runAsync(() async {
        await CustomRadioStationStore.instance
            .add('My Jazz Station', 'https://stream.example.com/jazz');

        await pumpNoStations(tester, _FakeEngine());
        expect(find.text('My Jazz Station'), findsOneWidget);

        await tester.tap(find.byTooltip('Remove station'));
        await _settle(tester);

        expect(find.text('My Jazz Station'), findsNothing);
        expect(await CustomRadioStationStore.instance.load(), isEmpty);
      });
    });
  });
}
