import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real, writable directory paths for every method `MainCore.initialize()`'s
/// full call graph reaches through `path_provider` — `PluginInstaller`
/// (`getApplicationSupportPath`), every JSON-backed store (`LibraryStore`,
/// `PlaylistStore`, `PlayHistoryStore`, `RecoveryJournal`, ..., via
/// `getApplicationDocumentsPath`), and `audio_service`'s own
/// `flutter_cache_manager` (`getTemporaryPath`/`getApplicationCachePath`).
/// Without this, every one of those calls throws `MissingPluginException`
/// on a platform with no real `path_provider` implementation wired into
/// `flutter test`'s binding — true locally on some desktop targets (a real
/// native implementation happens to answer), but never true on CI's Linux
/// runner, which is what turned this into a real, environment-dependent
/// build failure rather than the intentional "no platform channel" fallback
/// path the tests below are actually about testing.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir;
  @override
  Future<String?> getApplicationCachePath() async => tempDir;
}

/// bootstrap.dart's own doc comment: "A single entry point means there is
/// one answer to 'is the core up?' no matter who asks" — these tests
/// exercise exactly that idempotency contract, plus the "a half-initialised
/// core still plays audio" resilience the try/catch around
/// core.initialize() documents. Several platform channels (SMTC,
/// home_widget, and — without the fake below — path_provider) have no real
/// implementation registered in a plain `flutter test` environment, so each
/// of those subsystems genuinely degrades here; `MainCore` is expected to
/// swallow every one of them and still boot. `path_provider` itself is
/// faked (see [_FakePathProvider]) precisely so it is *not* one of the
/// things degrading — every store gets a real, writable directory, so the
/// only channels genuinely exercising the degrade path are the ones this
/// suite actually intends to test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('omnis_bootstrap_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await disposeCore();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ensureCoreReady registers MainCore and AudioEngine singletons',
      () async {
    final core = await ensureCoreReady();

    expect(locator.isRegistered<MainCore>(), isTrue);
    expect(locator.isRegistered<AudioEngine>(), isTrue);
    expect(locator<MainCore>(), same(core));
    expect(locator<AudioEngine>(), same(core.audioEngine));
  });

  test('a second call returns the same instance instead of re-initializing',
      () async {
    final first = await ensureCoreReady();
    final second = await ensureCoreReady();

    expect(second, same(first));
  });

  test(
      'core.initialize() with several unavailable platform channels in this '
      'test environment (SMTC, home_widget) still results in a registered, '
      'usable core rather than ensureCoreReady() throwing', () async {
    // The real regression this guards: a half-initialised core must still
    // play audio, not refuse to start the app.
    await expectLater(ensureCoreReady(), completes);
    expect(locator.isRegistered<MainCore>(), isTrue);
  });

  test('disposeCore tears down and unregisters both singletons', () async {
    await ensureCoreReady();
    expect(locator.isRegistered<MainCore>(), isTrue);

    await disposeCore();

    expect(locator.isRegistered<MainCore>(), isFalse);
    expect(locator.isRegistered<AudioEngine>(), isFalse);
  });

  test('disposeCore with nothing registered is a harmless no-op', () async {
    expect(locator.isRegistered<MainCore>(), isFalse);
    await expectLater(disposeCore(), completes);
  });

  test('disposeCore is safe to call twice in a row', () async {
    await ensureCoreReady();
    await disposeCore();
    await expectLater(disposeCore(), completes);
  });
}
