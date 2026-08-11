import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform({});
  });

  test('reads default to null before initialize() has run', () {
    final storage = PluginStorage('sample');
    expect(storage.getString('token'), isNull);
  });

  test('round-trips every supported value type once initialized', () async {
    final storage = PluginStorage('sample');
    await storage.initialize();

    await storage.setString('name', 'Alice');
    await storage.setBool('enabled', true);
    await storage.setInt('count', 7);
    await storage.setDouble('gain', 1.5);
    await storage.setStringList('tags', ['a', 'b']);

    expect(storage.getString('name'), 'Alice');
    expect(storage.getBool('enabled'), isTrue);
    expect(storage.getInt('count'), 7);
    expect(storage.getDouble('gain'), 1.5);
    expect(storage.getStringList('tags'), ['a', 'b']);
  });

  test('writes self-initialize even when initialize() was never called', () async {
    final storage = PluginStorage('sample');
    await storage.setString('token', 'abc');
    expect(storage.getString('token'), 'abc');
  });

  test('two plugins can use the same key without colliding', () async {
    final a = PluginStorage('plugin_a');
    final b = PluginStorage('plugin_b');
    await a.setString('token', 'a-token');
    await b.setString('token', 'b-token');

    expect(a.getString('token'), 'a-token');
    expect(b.getString('token'), 'b-token');
  });

  test('remove deletes a single key', () async {
    final storage = PluginStorage('sample');
    await storage.setString('token', 'abc');
    await storage.remove('token');
    expect(storage.getString('token'), isNull);
  });

  test('clear wipes only this plugin\'s own keys', () async {
    final a = PluginStorage('plugin_a');
    final b = PluginStorage('plugin_b');
    await a.setString('token', 'a-token');
    await a.setString('other', 'a-other');
    await b.setString('token', 'b-token');

    await a.clear();

    expect(a.getString('token'), isNull);
    expect(a.getString('other'), isNull);
    expect(b.getString('token'), 'b-token');
  });

  group('secure tier', () {
    test('setSecureString/getSecureString round-trip', () async {
      final storage = PluginStorage('sample');
      await storage.setSecureString('access_token', 'super-secret');
      expect(await storage.getSecureString('access_token'), 'super-secret');
    });

    test('getSecureString returns null for a key that was never set',
        () async {
      final storage = PluginStorage('sample');
      expect(await storage.getSecureString('nope'), isNull);
    });

    test(
        'a token written via setSecureString is genuinely absent from the '
        'plain SharedPreferences-backed store — not just duplicated there',
        () async {
      final storage = PluginStorage('sample');
      await storage.setSecureString('access_token', 'super-secret');

      // The plain getter for the same key must see nothing...
      expect(storage.getString('access_token'), isNull);
      // ...and neither must the raw SharedPreferences instance underneath
      // it, checked directly by the exact namespaced key PluginStorage
      // would have used had it (wrongly) gone through the plain tier.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('plugin_sample_access_token'), isNull);
      expect(
        prefs.getKeys().where((k) => k.contains('access_token')),
        isEmpty,
        reason: 'no key derived from "access_token" should exist in plain '
            'SharedPreferences at all',
      );
    });

    test('removeSecure deletes a single secure key without touching the '
        'plain tier', () async {
      final storage = PluginStorage('sample');
      await storage.setSecureString('access_token', 'super-secret');
      await storage.setString('display_name', 'Alice');

      await storage.removeSecure('access_token');

      expect(await storage.getSecureString('access_token'), isNull);
      expect(storage.getString('display_name'), 'Alice');
    });

    test('two plugins can use the same secure key without colliding',
        () async {
      final a = PluginStorage('plugin_a');
      final b = PluginStorage('plugin_b');
      await a.setSecureString('token', 'a-token');
      await b.setSecureString('token', 'b-token');

      expect(await a.getSecureString('token'), 'a-token');
      expect(await b.getSecureString('token'), 'b-token');
    });

    test('clear() wipes both plain and secure keys for this plugin only',
        () async {
      final a = PluginStorage('plugin_a');
      final b = PluginStorage('plugin_b');
      await a.setString('display_name', 'Alice');
      await a.setSecureString('token', 'a-token');
      await b.setSecureString('token', 'b-token');

      await a.clear();

      expect(a.getString('display_name'), isNull);
      expect(await a.getSecureString('token'), isNull);
      expect(await b.getSecureString('token'), 'b-token',
          reason: 'clearing plugin_a must not touch plugin_b\'s secure keys');
    });
  });
}
