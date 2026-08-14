import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/home_widget_service.dart';

import 'fakes/fake_home_widget_track_source.dart';

BaseTrack _track({String title = 'Sunrise', List<String> artists = const [
  'Ava'
]}) =>
    BaseTrack(
      id: 't1',
      title: title,
      artists: artists,
      album: 'Morning',
      duration: 180,
      type: TrackType.local,
      localPath: '/music/sunrise.mp3',
    );

/// [HomeWidgetService] mirrors playback state into the `home_widget`
/// plugin's SharedPreferences bridge for the real Android home-screen
/// widget (`OmnisWidgetProvider.kt`) to read. This only exercises the
/// Dart-side glue — formatting and forwarding track/play-state changes
/// through the `home_widget` MethodChannel — not the native widget
/// itself, which has no `flutter_test` equivalent and is verified on a
/// real device instead (see docs/OMNIS_2_0_MISSED_DEEP_PHASE.md item 49).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('home_widget');
  late List<MethodCall> calls;
  late FakeHomeWidgetTrackSource source;
  late HomeWidgetService service;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'saveWidgetData') return true;
      if (call.method == 'updateWidget') return true;
      return null;
    });
    source = FakeHomeWidgetTrackSource();
    service = HomeWidgetService.instance;
  });

  tearDown(() async {
    await service.dispose();
    await source.dispose();
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize() pushes the current state immediately, even with '
      'nothing playing', () async {
    service.initialize(source);
    await Future<void>.delayed(Duration.zero);

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    expect(saves.any((c) => c.arguments['id'] == 'title' &&
        c.arguments['data'] == 'Not playing'), isTrue);
    expect(saves.any((c) => c.arguments['id'] == 'artist' &&
        c.arguments['data'] == ''), isTrue);
    expect(saves.any((c) => c.arguments['id'] == 'playing' &&
        c.arguments['data'] == false), isTrue);
    expect(calls.any((c) => c.method == 'updateWidget'), isTrue);
  });

  test('a track change pushes the real title and comma-joined artists',
      () async {
    service.initialize(source);
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    source.emitTrack(_track(title: 'Sunrise', artists: const ['Ava', 'Bo']));
    await Future<void>.delayed(Duration.zero);

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    expect(saves.any((c) => c.arguments['id'] == 'title' &&
        c.arguments['data'] == 'Sunrise'), isTrue);
    expect(saves.any((c) => c.arguments['id'] == 'artist' &&
        c.arguments['data'] == 'Ava, Bo'), isTrue);
  });

  test('a play/pause toggle pushes the new playing state without '
      'touching the current track', () async {
    source.emitTrack(_track());
    service.initialize(source);
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    source.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    expect(saves.any((c) => c.arguments['id'] == 'playing' &&
        c.arguments['data'] == true), isTrue);
    expect(saves.any((c) => c.arguments['id'] == 'title' &&
        c.arguments['data'] == 'Sunrise'), isTrue);
  });

  test('the queue going empty (track becomes null) falls back to '
      '"Not playing" with no artist', () async {
    source.emitTrack(_track());
    service.initialize(source);
    await Future<void>.delayed(Duration.zero);
    calls.clear();

    source.emitTrack(null);
    await Future<void>.delayed(Duration.zero);

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    expect(saves.any((c) => c.arguments['id'] == 'title' &&
        c.arguments['data'] == 'Not playing'), isTrue);
    expect(saves.any((c) => c.arguments['id'] == 'artist' &&
        c.arguments['data'] == ''), isTrue);
  });

  test('dispose() stops forwarding further state changes', () async {
    service.initialize(source);
    await Future<void>.delayed(Duration.zero);
    await service.dispose();
    calls.clear();

    source.emitTrack(_track());
    await Future<void>.delayed(Duration.zero);

    expect(calls, isEmpty);
  });
}
