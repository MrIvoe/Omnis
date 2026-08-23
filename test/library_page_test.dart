import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/library_store.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/library_page.dart';
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

/// Spies on nothing this test needs beyond `trackStream` — matches the
/// `noSuchMethod` "stub only what's touched" pattern
/// home_dashboard_page_test.dart's/playlist_page_test.dart's own
/// `_FakeEngine`s already use.
class _FakeEngine implements AudioEngine {
  final _trackController = StreamController<BaseTrack?>.broadcast();

  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  @override
  BaseTrack? get currentTrack => null;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

BaseTrack _track(String id) => BaseTrack(
      id: id,
      title: 'Track $id',
      artists: const ['Artist'],
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

/// Same reasoning as playlist_page_test.dart's/home_dashboard_page_test
/// .dart's own `_settle`: `LibraryPage` reads a real (fake-path-provider-
/// backed) `LibraryRepository`/`LibraryStore` from `initState` onward —
/// real dart:io — so a plain `pumpAndSettle()` never gives that a chance
/// to actually finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final tempDir =
        (await Directory.systemTemp.createTemp('omnis_library_page_test'))
            .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    await LibraryStore.instance.clear();
    LibraryRepository.instance.resetForTesting();
  });

  tearDown(PlatformCapabilities.resetOverridesForTesting);

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home:
          LibraryPage(engine: _FakeEngine(), pluginManager: PluginManager()),
    ));
    await _settle(tester);
  }

  group('Right-click multi-select entry (Task 6, item task-6/§2)', () {
    testWidgets(
        'a track row (list view): onSecondaryTap enters selection mode on '
        'a desktop-primary platform, the same as long-press already does',
        (tester) async {
      await tester.runAsync(() async {
        PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
        await LibraryStore.instance.save([_track('a'), _track('b')]);
        await pumpPage(tester);

        expect(find.text('1 selected'), findsNothing);
        await tester.tap(
          find.text('Track a'),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await _settle(tester);

        expect(find.text('1 selected'), findsOneWidget);
      });
    });

    testWidgets(
        'a track row (list view): onSecondaryTap is a no-op on a '
        'non-desktop-primary platform, which has no right-click to parity '
        'with',
        (tester) async {
      await tester.runAsync(() async {
        PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
        await LibraryStore.instance.save([_track('a')]);
        await pumpPage(tester);

        await tester.tap(
          find.text('Track a'),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
          warnIfMissed: false,
        );
        await _settle(tester);

        expect(find.text('1 selected'), findsNothing);
      });
    });

    testWidgets(
        'a grid tile: onSecondaryTap enters selection mode on a '
        'desktop-primary platform, the same as long-press already does',
        (tester) async {
      await tester.runAsync(() async {
        PlatformCapabilities.debugIsDesktopPrimaryOverride = true;
        await LibraryStore.instance.save([_track('a'), _track('b')]);
        await AppSettings.instance.setSongsViewMode(LibraryDisplayMode.grid);
        await pumpPage(tester);

        expect(find.text('1 selected'), findsNothing);
        await tester.tap(
          find.text('Track a'),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await _settle(tester);

        expect(find.text('1 selected'), findsOneWidget);
      });
    });

    testWidgets(
        'a grid tile: onSecondaryTap is a no-op on a non-desktop-primary '
        'platform, which has no right-click to parity with', (tester) async {
      await tester.runAsync(() async {
        PlatformCapabilities.debugIsDesktopPrimaryOverride = false;
        await LibraryStore.instance.save([_track('a')]);
        await AppSettings.instance.setSongsViewMode(LibraryDisplayMode.grid);
        await pumpPage(tester);

        await tester.tap(
          find.text('Track a'),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
          warnIfMissed: false,
        );
        await _settle(tester);

        expect(find.text('1 selected'), findsNothing);
      });
    });
  });
}
