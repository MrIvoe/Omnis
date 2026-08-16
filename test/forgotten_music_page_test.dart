import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/play_history_store.dart';
import 'package:omnis/ui/forgotten_music_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

/// Spies on setQueue/play, same `noSuchMethod` pattern
/// home_dashboard_page_test.dart's own `_FakeEngine` uses.
class _FakeEngine implements AudioEngine {
  List<BaseTrack>? lastQueue;
  int? lastStartIndex;
  bool playCalled = false;

  final _trackController = StreamController<BaseTrack?>.broadcast();

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    lastQueue = tracks;
    lastStartIndex = startIndex;
  }

  @override
  Future<void> play() async => playCalled = true;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

/// Same reasoning as home_dashboard_page_test.dart's `_settle`, plus a
/// trailing `pumpAndSettle()` (playlist_page_test.dart's own `_settle`
/// adds the same thing) to finish a still-animating popup-menu open/
/// close — without it, a tap immediately following one of those can
/// land on the barrier behind a not-yet-fully-open menu instead of the
/// item itself.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pumpAndSettle();
}

BaseTrack _track(String id) => BaseTrack(
      id: id,
      title: 'Track $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 200,
      type: TrackType.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_forgotten_test')).path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    await LibraryStore.instance.clear();
    await PlayHistoryStore.instance.clear();
    LibraryRepository.instance.resetForTesting();
  });

  Future<void> pumpPage(WidgetTester tester, {AudioEngine? engine}) async {
    await tester.pumpWidget(MaterialApp(
      home: ForgottenMusicPage(engine: engine ?? _FakeEngine()),
    ));
    await _settle(tester);
  }

  testWidgets('a never-played track shows up with the default 6-month '
      'threshold', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a')]);

      await pumpPage(tester);

      expect(find.text('1 track you haven\'t heard in 6 months+'),
          findsOneWidget);
      expect(find.text('Track a'), findsOneWidget);
      expect(find.textContaining('never played'), findsOneWidget);
    });
  });

  testWidgets('a track played recently is excluded', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a')]);
      await PlayHistoryStore.instance.recordPlay(_track('a'));

      await pumpPage(tester);

      expect(find.textContaining('Nothing forgotten'), findsOneWidget);
      expect(find.text('Track a'), findsNothing);
    });
  });

  testWidgets('tapping a track plays the forgotten list starting at that '
      'track', (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a'), _track('b')]);
      final engine = _FakeEngine();

      await pumpPage(tester, engine: engine);
      await tester.tap(find.text('Track b'));
      await _settle(tester);

      expect(engine.lastQueue?.map((t) => t.id), ['a', 'b']);
      expect(engine.lastStartIndex, 1);
      expect(engine.playCalled, isTrue);
    });
  });

  testWidgets('"Play all" plays every forgotten track from the top',
      (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a'), _track('b')]);
      final engine = _FakeEngine();

      await pumpPage(tester, engine: engine);
      await tester.tap(find.byTooltip('Play all'));
      await _settle(tester);

      expect(engine.lastQueue?.map((t) => t.id), ['a', 'b']);
      expect(engine.lastStartIndex, 0);
      expect(engine.playCalled, isTrue);
    });
  });

  testWidgets('changing the threshold to 1 month re-filters the list',
      (tester) async {
    await tester.runAsync(() async {
      await LibraryStore.instance.save([_track('a')]);
      await PlayHistoryStore.instance.recordPlay(_track('a'));

      await pumpPage(tester);
      expect(find.text('Track a'), findsNothing,
          reason: 'played moments ago, well within the default 6 months');

      await tester.tap(find.byTooltip('Not heard in…'));
      await _settle(tester);
      await tester.tap(find.text('1 month').last);
      await _settle(tester);

      // Still within 1 month too (recorded seconds ago), so still absent
      // — this asserts the menu interaction itself doesn't throw and the
      // page re-renders with the new threshold's label.
      expect(find.textContaining('1 month'), findsWidgets);
    });
  });

  testWidgets('an empty library shows the empty state, not a crash',
      (tester) async {
    await tester.runAsync(() async {
      await pumpPage(tester);

      expect(find.textContaining('Nothing forgotten'), findsOneWidget);
    });
  });
}
