import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  test('the default map before any override equals defaultShortcutBindings',
      () {
    expect(AppSettings.instance.shortcutBindings, defaultShortcutBindings);
  });

  test('setShortcutBinding persists and is read back by a fresh '
      'AppSettings instance sharing the same SharedPreferences backing',
      () async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );

    // AppSettings.instance is a singleton, so this doesn't construct a
    // literal second object — but the real persistence path (write to
    // SharedPreferences, read back via getStringList) is exercised the
    // same way it would be across a real app restart.
    final fresh = AppSettings.instance;
    expect(
      fresh.shortcutBindings[ShortcutAction.toggleMute],
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
  });

  test('setting one action\'s binding leaves every other action at its '
      'default', () async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );

    final bindings = AppSettings.instance.shortcutBindings;
    for (final action in ShortcutAction.values) {
      if (action == ShortcutAction.toggleMute) continue;
      expect(bindings[action], defaultShortcutBindings[action]);
    }
  });

  test('resetShortcutBinding clears just one override', () async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.volumeUp,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyP.keyId),
    );

    await AppSettings.instance.resetShortcutBinding(ShortcutAction.toggleMute);

    expect(AppSettings.instance.shortcutBindings[ShortcutAction.toggleMute],
        defaultShortcutBindings[ShortcutAction.toggleMute]);
    expect(
      AppSettings.instance.shortcutBindings[ShortcutAction.volumeUp],
      ShortcutBinding(keyId: LogicalKeyboardKey.keyP.keyId),
      reason: 'resetting one action must not touch another\'s override',
    );
  });

  test('resetAllShortcutBindings clears every override', () async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.volumeUp,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyP.keyId),
    );

    await AppSettings.instance.resetAllShortcutBindings();

    expect(AppSettings.instance.shortcutBindings, defaultShortcutBindings);
  });

  test('a manually-corrupted stored entry degrades only that one action '
      'to default, not the whole map', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('app_shortcut_binding_overrides', [
      'toggleMute=garbage',
      'volumeUp=${LogicalKeyboardKey.keyP.keyId}:false:false:false:false',
    ]);

    final bindings = AppSettings.instance.shortcutBindings;
    expect(bindings[ShortcutAction.toggleMute],
        defaultShortcutBindings[ShortcutAction.toggleMute],
        reason: 'the corrupted entry degrades to its default');
    expect(
      bindings[ShortcutAction.volumeUp],
      ShortcutBinding(keyId: LogicalKeyboardKey.keyP.keyId),
      reason: 'a sibling valid entry is unaffected by the corrupted one',
    );
  });

  test('an unrecognized action name in storage is silently skipped',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('app_shortcut_binding_overrides', [
      'someRemovedAction=${LogicalKeyboardKey.keyP.keyId}:false:false:false:false',
    ]);

    expect(AppSettings.instance.shortcutBindings, defaultShortcutBindings);
  });
}
