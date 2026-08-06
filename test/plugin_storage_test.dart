import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/plugin_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
