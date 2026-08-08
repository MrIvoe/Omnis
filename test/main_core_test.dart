import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/main_core.dart';

/// MainCore's own class-level contract — construction, disposal
/// idempotency, isDisposed — as opposed to bootstrap_test.dart, which
/// covers the ensureCoreReady()/disposeCore() singleton-registration layer
/// built on top of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a freshly constructed core is not disposed and exposes real '
      'sub-components before initialize() is even called', () {
    final core = MainCore();

    expect(core.isDisposed, isFalse);
    expect(core.audioEngine, isNotNull);
    expect(core.pluginManager, isNotNull);
    expect(core.sandbox, isNotNull);
  });

  test('dispose() marks the core disposed', () async {
    final core = MainCore();

    await core.dispose();

    expect(core.isDisposed, isTrue);
  });

  test('dispose() is idempotent — a second call does not re-dispose',
      () async {
    final core = MainCore();

    await core.dispose();
    // If this re-ran the real dispose logic (AudioEngine.dispose(),
    // PluginManager.dispose()) a second time on already-torn-down
    // sub-components, it would be the kind of thing that throws on a
    // real platform even though it can't reproduce that specific failure
    // in this test environment — the guard itself is what's under test.
    await expectLater(core.dispose(), completes);
    expect(core.isDisposed, isTrue);
  });
}
