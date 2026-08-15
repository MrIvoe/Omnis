import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/queue_history_store.dart';
import 'package:omnis/ui/queue_history_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Spies on setQueue/play — same noSuchMethod-throws-if-unstubbed pattern
/// this session's other page tests already use.
class _FakeEngine implements AudioEngine {
  List<BaseTrack>? lastQueue;
  bool playCalled = false;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
  }

  @override
  Future<void> play() async => playCalled = true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

BaseTrack _track(String id, {String title = 'Title'}) => BaseTrack(
      id: id,
      title: title,
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

/// Same reasoning as home_dashboard_page_test.dart's own `_settle`:
/// QueueHistoryPage reads a real (fake-path-provider-backed)
/// QueueHistoryStore singleton — real dart:io — so a plain `pump()`
/// inside the fake-async test zone never gives that a chance to
/// actually finish, even inside `tester.runAsync()`. An explicit real
/// delay between two pumps does.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;

  setUp(() async {
    tempDir = (await Directory.systemTemp
            .createTemp('omnis_queue_history_page_test'))
        .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await QueueHistoryStore.instance.save([]);
  });

  testWidgets('shows the empty state when nothing has ever been recorded',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: QueueHistoryPage(engine: _FakeEngine()),
      ));
      await _settle(tester);

      expect(find.text('No past queues yet.'), findsOneWidget);
    });
  });

  testWidgets(
      'shows a named snapshot by its name and an auto entry by its '
      'first-track description', (tester) async {
    await tester.runAsync(() async {
      await QueueHistoryStore.instance
          .saveSnapshot('Road Trip Mix', [_track('a', title: 'Sunrise')]);
      await QueueHistoryStore.instance
          .recordAutoHistory([_track('b', title: 'Moonlight'), _track('c')]);

      await tester.pumpWidget(MaterialApp(
        home: QueueHistoryPage(engine: _FakeEngine()),
      ));
      await _settle(tester);

      expect(find.text('Road Trip Mix'), findsOneWidget);
      expect(find.text('Moonlight and 1 more'), findsOneWidget);
    });
  });

  testWidgets('tapping restore sets the engine queue and plays',
      (tester) async {
    await tester.runAsync(() async {
      await QueueHistoryStore.instance
          .saveSnapshot('Road Trip Mix', [_track('a'), _track('b')]);
      final engine = _FakeEngine();

      await tester.pumpWidget(MaterialApp(
        home: QueueHistoryPage(engine: engine),
      ));
      await _settle(tester);

      await tester.tap(find.byTooltip('Restore this queue'));
      await _settle(tester);

      expect(engine.lastQueue?.map((t) => t.id), ['a', 'b']);
      expect(engine.playCalled, isTrue);
    });
  });

  testWidgets('tapping delete removes the entry from the list and from '
      'the store', (tester) async {
    await tester.runAsync(() async {
      await QueueHistoryStore.instance
          .saveSnapshot('Delete Me', [_track('a')]);

      await tester.pumpWidget(MaterialApp(
        home: QueueHistoryPage(engine: _FakeEngine()),
      ));
      await _settle(tester);
      expect(find.text('Delete Me'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete'));
      await _settle(tester);

      expect(find.text('Delete Me'), findsNothing);
      final saved = await QueueHistoryStore.instance.load();
      expect(saved, isEmpty);
    });
  });

  testWidgets(
      'a snapshot is visually distinguished from an auto entry (bookmark '
      'vs history icon)', (tester) async {
    await tester.runAsync(() async {
      await QueueHistoryStore.instance.saveSnapshot('Snap', [_track('a')]);
      await QueueHistoryStore.instance.recordAutoHistory([_track('b')]);

      await tester.pumpWidget(MaterialApp(
        home: QueueHistoryPage(engine: _FakeEngine()),
      ));
      await _settle(tester);

      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });
  });
}
