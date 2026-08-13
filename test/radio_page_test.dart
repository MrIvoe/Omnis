import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/radio_page.dart';
import 'package:omnis_plugins/radio_plugin.dart';

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
}
