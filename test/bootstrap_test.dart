import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/bootstrap.dart';
import 'package:omnis/core/main_core.dart';

/// bootstrap.dart's own doc comment: "A single entry point means there is
/// one answer to 'is the core up?' no matter who asks" — these tests
/// exercise exactly that idempotency contract, plus the "a half-initialised
/// core still plays audio" resilience the try/catch around
/// core.initialize() documents. No platform channel is registered for
/// just_audio/audio_service in a plain `flutter test` environment, so
/// core.initialize() genuinely does fail here — this is testing the real
/// fallback path, not a simulated one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await disposeCore();
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
      'core.initialize() failing (no platform channel in this test '
      'environment) still results in a registered, usable core rather than '
      'ensureCoreReady() throwing', () async {
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
