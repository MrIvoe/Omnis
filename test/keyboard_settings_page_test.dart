import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';
import 'package:omnis/ui/settings/keyboard_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: KeyboardSettingsPage()));
    await tester.pump();
  }

  testWidgets('rows render the current display label for each action',
      (tester) async {
    await pump(tester);

    expect(find.text('M'), findsOneWidget); // toggleMute default
    expect(find.text('Space'), findsOneWidget); // togglePlayPause default
  });

  testWidgets('hardware key rows are present but not tappable',
      (tester) async {
    await pump(tester);

    expect(find.text('Media play/pause key'), findsOneWidget);
    final tile = tester.widget<ListTile>(find.ancestor(
      of: find.text('Media play/pause key'),
      matching: find.byType(ListTile),
    ));
    expect(tile.onTap, isNull);
  });

  testWidgets('tapping a remappable row opens the capture dialog',
      (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    await tester.tap(find.text('Mute / unmute'));
    await tester.pumpAndSettle();

    expect(find.text('Remap "Mute / unmute"'), findsOneWidget);
    expect(find.text('Press a key…'), findsOneWidget);
  });

  testWidgets('a non-conflicting key press commits immediately and '
      'updates the row', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    await tester.tap(find.text('Mute / unmute'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();

    expect(find.text('Remap "Mute / unmute"'), findsNothing);
    expect(
      AppSettings.instance.shortcutBindings[ShortcutAction.toggleMute],
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
    expect(find.text('N'), findsOneWidget);
  });

  testWidgets('a conflicting key shows the swap-confirmation copy, and '
      'confirming swaps both actions\' bindings', (tester) async {
    await pump(tester);

    // Space is already bound to togglePlayPause — proposing it for
    // toggleMute is a real conflict.
    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    await tester.tap(find.text('Mute / unmute'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(find.textContaining('Also used for "Play / pause"'),
        findsOneWidget);

    await tester.tap(find.text('Swap'));
    await tester.pumpAndSettle();

    final bindings = AppSettings.instance.shortcutBindings;
    expect(bindings[ShortcutAction.toggleMute],
        ShortcutBinding(keyId: LogicalKeyboardKey.space.keyId));
    expect(bindings[ShortcutAction.togglePlayPause],
        ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId),
        reason: 'the swap gives togglePlayPause what toggleMute used to '
            'have, so it is never left unbound');
  });

  testWidgets('a reserved activation key (Space) on an unbound-conflict '
      'action shows a warning but still allows saving', (tester) async {
    await pump(tester);

    // volumeUp's default is Arrow Up — Space is reserved but not a
    // conflict for it.
    await tester.tap(find.text('Volume up'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.textContaining('Save anyway?'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      AppSettings.instance.shortcutBindings[ShortcutAction.volumeUp],
      ShortcutBinding(keyId: LogicalKeyboardKey.enter.keyId),
    );
  });

  testWidgets('Cancel closes the dialog without saving', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    await tester.tap(find.text('Mute / unmute'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    // Commits immediately for a non-conflicting key, so re-open and
    // cancel from the listening stage instead.
    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    await tester.tap(find.text('Mute / unmute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      AppSettings.instance.shortcutBindings[ShortcutAction.toggleMute],
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
      reason: 'cancelling must not change the still-current N binding',
    );
  });

  testWidgets('a per-row reset restores just that action\'s default, and '
      'the reset icon disappears once at default', (tester) async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
    await pump(tester);

    await tester.ensureVisible(find.text('Mute / unmute'));
    await tester.pump();
    expect(find.byIcon(Icons.restore), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();

    expect(
      AppSettings.instance.shortcutBindings[ShortcutAction.toggleMute],
      defaultShortcutBindings[ShortcutAction.toggleMute],
    );
    expect(find.byIcon(Icons.restore), findsNothing);
  });

  testWidgets('"Reset all" restores every action to its default',
      (tester) async {
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.toggleMute,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
    );
    await AppSettings.instance.setShortcutBinding(
      ShortcutAction.volumeUp,
      ShortcutBinding(keyId: LogicalKeyboardKey.keyP.keyId),
    );
    await pump(tester);

    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.shortcutBindings, defaultShortcutBindings);
    expect(find.byIcon(Icons.restore), findsNothing);
  });
}
