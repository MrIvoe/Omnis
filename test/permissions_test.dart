import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/permissions.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

/// OmnisPermissions is a thin wrapper around permission_handler's
/// platform-channel calls, whose entire documented contract is "best-effort,
/// never throws out to the caller — a denied or platform-unsupported
/// permission degrades the feature, it must never block the app or crash
/// it." No platform channel handler is registered in a plain `flutter test`
/// environment, so every call here genuinely exercises that catch path for
/// real, rather than needing to mock permission_handler's platform
/// interface just to prove the try/catch works.
///
/// The `ensureUpfrontPermissions` group below is the one exception: proving
/// it stays *scoped* to the ids actually passed in (not "everything,
/// always") needs to see exactly which `Permission`s were requested, which
/// the "just completes without throwing" style above can't distinguish from
/// a bug that requests every permission regardless of input — a
/// `PermissionHandlerPlatform` fake that records every call is what makes
/// that distinction observable.
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

  test('requestMicrophone never throws and fails closed', () async {
    final result = await OmnisPermissions.requestMicrophone();
    expect(result, isFalse);
  });

  test('an unrelated/unknown plugin id never throws and requests nothing '
      'beyond core (no platform channel present, same as every other test '
      'above)', () async {
    await expectLater(
        OmnisPermissions.ensureUpfrontPermissions({'not_a_real_plugin'}),
        completes);
  });

  group('ensureUpfrontPermissions scoping', () {
    // A recording `PermissionHandlerPlatform` fake, so each test below can
    // assert exactly which `Permission`s were requested — the only way to
    // actually distinguish "stayed scoped to the ids passed in" from a bug
    // that requests everything regardless of input, since both would
    // otherwise just "complete without throwing" against this test
    // environment's real default (no platform channel at all).
    late _RecordingPermissionHandler fakeHandler;
    late PermissionHandlerPlatform originalPlatform;

    setUp(() {
      originalPlatform = PermissionHandlerPlatform.instance;
      fakeHandler = _RecordingPermissionHandler();
      PermissionHandlerPlatform.instance = fakeHandler;
    });

    tearDown(() {
      PermissionHandlerPlatform.instance = originalPlatform;
    });

    test('an empty set requests only the always-on core permission',
        () async {
      await OmnisPermissions.ensureUpfrontPermissions(<String>{});
      expect(fakeHandler.requested, [Permission.notification]);
    });

    test('an unrelated/unknown plugin id requests only core — ids are '
        'matched exactly, not loosely', () async {
      await OmnisPermissions.ensureUpfrontPermissions({'not_a_real_plugin'});
      expect(fakeHandler.requested, [Permission.notification]);
    });

    test('{tag_editor} requests storage-write and nothing else', () async {
      await OmnisPermissions.ensureUpfrontPermissions({'tag_editor'});
      expect(fakeHandler.requested,
          [Permission.notification, Permission.manageExternalStorage]);
    });

    test('{bluetooth_playback} requests Bluetooth connect+scan and nothing '
        'else', () async {
      await OmnisPermissions.ensureUpfrontPermissions({'bluetooth_playback'});
      expect(fakeHandler.requested, [
        Permission.notification,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    });

    test('{driving_mode} requests foreground location only (never '
        'background) and nothing else', () async {
      await OmnisPermissions.ensureUpfrontPermissions({'driving_mode'});
      expect(fakeHandler.requested,
          [Permission.notification, Permission.locationWhenInUse]);
    });

    test('{visualizer} requests microphone and nothing else', () async {
      await OmnisPermissions.ensureUpfrontPermissions({'visualizer'});
      expect(fakeHandler.requested,
          [Permission.notification, Permission.microphone]);
    });

    test('every plugin id at once requests every corresponding permission, '
        'each exactly once, covering the full batch in a single call',
        () async {
      await OmnisPermissions.ensureUpfrontPermissions({
        'tag_editor',
        'bluetooth_playback',
        'driving_mode',
        'visualizer',
      });
      expect(fakeHandler.requested, [
        Permission.notification,
        Permission.manageExternalStorage,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.locationWhenInUse,
        Permission.microphone,
      ]);
    });
  });
}

/// Records every `Permission` handed to [requestPermissions], reporting
/// every one of them granted — real code under test only cares about the
/// resulting `PermissionStatus`, never about anything platform-specific
/// this fake would otherwise need to fake too.
class _RecordingPermissionHandler extends PermissionHandlerPlatform {
  final List<Permission> requested = [];

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
      List<Permission> permissions) async {
    requested.addAll(permissions);
    return {for (final p in permissions) p: PermissionStatus.granted};
  }

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async =>
      PermissionStatus.granted;

  @override
  Future<bool> shouldShowRequestPermissionRationale(
          Permission permission) async =>
      false;
}
