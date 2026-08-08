import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/permissions.dart';

/// OmnisPermissions is a thin wrapper around permission_handler's
/// platform-channel calls, whose entire documented contract is "best-effort,
/// never throws out to the caller — a denied or platform-unsupported
/// permission degrades the feature, it must never block the app or crash
/// it." No platform channel handler is registered in a plain `flutter test`
/// environment, so every call here genuinely exercises that catch path for
/// real, rather than needing to mock permission_handler's platform
/// interface just to prove the try/catch works.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensureCorePermissions never throws with no platform channel present',
      () async {
    await expectLater(OmnisPermissions.ensureCorePermissions(), completes);
  });

  test(
      'requestStorageWrite never throws and reports success when the '
      'permission does not exist on this platform', () async {
    final result = await OmnisPermissions.requestStorageWrite();
    // Documented fallback: an exception (this permission not existing on
    // this platform, or — as here — no platform channel at all) reports
    // success rather than a false negative, since writes already work via
    // the plain filesystem there.
    expect(result, isTrue);
  });

  test('requestBluetooth never throws and fails closed', () async {
    final result = await OmnisPermissions.requestBluetooth();
    expect(result, isFalse);
  });

  test('requestLocation never throws and fails closed', () async {
    final result = await OmnisPermissions.requestLocation();
    expect(result, isFalse);
  });

  test('requestLocation(always: true) never throws and fails closed',
      () async {
    final result = await OmnisPermissions.requestLocation(always: true);
    expect(result, isFalse);
  });
}
