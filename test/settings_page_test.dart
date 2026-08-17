import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/about_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/settings/accessibility_settings_page.dart';
import 'package:omnis/ui/settings/backup_settings_page.dart';
import 'package:omnis/ui/settings/keyboard_settings_page.dart';
import 'package:omnis/ui/settings/playback_settings_page.dart';
import 'package:omnis/ui/settings_page.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No-op stand-in — the Settings home page never touches playback
/// directly, only the sub-pages it navigates to do.
class _FakeEngine implements AudioEngine {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(
        engine: _FakeEngine(),
        pluginManager: PluginManager(),
        sandbox: PluginSandbox(),
        layoutManager: LayoutManager(),
        themeManager: ThemeManager(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows one category card per settings area', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Appearance & Layout'), findsOneWidget);
    expect(find.text('Playback & Audio'), findsOneWidget);
    expect(find.text('Controls & Gestures'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);
    // Plugins/Backup sit below the default test viewport's sliver cache
    // extent — same reasoning as the "tapping Plugins" test's own
    // dragUntilVisible below: a plain ListView(children:) is still
    // sliver-backed, so an off-screen child isn't mounted (and thus not
    // findable) until actually scrolled into view.
    await tester.dragUntilVisible(
      find.text('Backup'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Backup'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('About'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('tapping Accessibility opens AccessibilitySettingsPage',
      (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.text('Accessibility'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accessibility'));
    await tester.pumpAndSettle();

    expect(find.byType(AccessibilitySettingsPage), findsOneWidget);
    expect(find.text('Reduce motion'), findsOneWidget);
    expect(find.text('Reduce transparency'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
  });

  testWidgets('tapping Keyboard opens KeyboardSettingsPage', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.text('Keyboard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();

    expect(find.byType(KeyboardSettingsPage), findsOneWidget);
    expect(find.text('Enable keyboard shortcuts'), findsOneWidget);
    expect(find.text('Shortcuts'), findsOneWidget);
  });

  testWidgets('tapping Backup opens BackupSettingsPage', (tester) async {
    await pumpSettings(tester);

    // Below the fold at the default test viewport, past the ListView's
    // sliver cache extent — not mounted at all until scrolled into view
    // (ensureVisible can't help here: it requires the target to already
    // be found/mounted, which is exactly what's not true yet).
    // dragUntilVisible scrolls incrementally until it is, then
    // ensureVisible finishes centering it so the tap offset lands inside
    // the viewport, not just barely intersecting its edge.
    await tester.dragUntilVisible(
      find.text('Backup'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.ensureVisible(find.text('Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();

    expect(find.byType(BackupSettingsPage), findsOneWidget);
    expect(find.text('Backup Omnis'), findsOneWidget);
    expect(find.text('Restore Omnis'), findsOneWidget);
  });

  testWidgets('tapping About opens AboutPage — the bottom-most category, '
      'per its own placement', (tester) async {
    await pumpSettings(tester);

    await tester.dragUntilVisible(
      find.text('About'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.ensureVisible(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
  });

  testWidgets(
      'tapping Plugins actually navigates to the Plugins page — this was '
      'previously unreachable from anywhere in the running app', (tester) async {
    await pumpSettings(tester);

    // Below the fold at the default test viewport now that Accessibility
    // sits above it in the list — same sliver-cache-extent reasoning as
    // "Plugin Health" below, just for the category card itself.
    // dragUntilVisible only guarantees partial intersection (which can
    // still land a tap offset just past the viewport edge — see the
    // "tapping Backup" test above), so ensureVisible finishes centering
    // it before the actual tap.
    await tester.dragUntilVisible(
      find.text('Plugins'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.ensureVisible(find.text('Plugins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plugins'));
    await tester.pumpAndSettle();

    // PluginsPage's own AppBar title, plus content only it renders.
    expect(find.text('Install a plugin'), findsOneWidget);
    // "Plugin Health" now sits below the catalog + installer cards, past
    // the default test viewport's sliver cache extent — a real
    // Scrollable (not `.builder`, but still sliver-backed) only mounts
    // elements near the visible region, so it must be scrolled into view
    // before `find` can see it, the same as it would need a real scroll
    // gesture on a small phone screen. `dragUntilVisible` (drag directly
    // on the `ListView`) rather than `scrollUntilVisible` (find *the*
    // `Scrollable`) — the URL `TextField` above it has its own nested
    // `Scrollable` too (`EditableText` always has one), so "the
    // `Scrollable` descendant of this `ListView`" isn't unique; dragging
    // on the `ListView`'s own render box hits its scroll view directly.
    await tester.dragUntilVisible(
      find.text('Plugin Health'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Plugin Health'), findsOneWidget);
  });

  testWidgets('tapping Playback & Audio opens PlaybackSettingsPage',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Playback & Audio'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackSettingsPage), findsOneWidget);
    expect(find.text('Crossfade'), findsOneWidget);
  });

  group('search deep-links to the exact control', () {
    testWidgets(
        'searching "Volume" and tapping the result opens Playback & Audio '
        'with that row as the highlight target, scrolled into view',
        (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'Volume');
      await tester.pumpAndSettle();
      // The search result card, not the eventual destination row (which
      // doesn't exist until after navigating).
      expect(find.widgetWithText(ListTile, 'Volume'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Volume'));
      await tester.pumpAndSettle();

      final page =
          tester.widget<PlaybackSettingsPage>(find.byType(PlaybackSettingsPage));
      expect(page.highlightField, 'volume');
      // scrollToAndFlashSetting's Scrollable.ensureVisible has resolved by
      // now (pumpAndSettle waited out the post-frame callback + scroll +
      // flash animation), so the row is actually on screen, not just
      // theoretically present in the widget tree.
      expect(find.widgetWithText(ListTile, 'Volume'), findsOneWidget);
    });

    testWidgets(
        'searching "Crossfade" and tapping the result targets the '
        'crossfade row specifically, not just the Playback page in general',
        (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'Crossfade');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Crossfade'));
      await tester.pumpAndSettle();

      final page =
          tester.widget<PlaybackSettingsPage>(find.byType(PlaybackSettingsPage));
      expect(page.highlightField, 'crossfade');
    });

    testWidgets(
        'searching "Reduce motion" and tapping the result opens '
        'AccessibilitySettingsPage with that row as the highlight target — '
        'proves the search index followed the move out of Appearance & '
        'Layout, not just the settings toggle itself', (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'Reduce motion');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Reduce motion'));
      await tester.pumpAndSettle();

      final page = tester.widget<AccessibilitySettingsPage>(
          find.byType(AccessibilitySettingsPage));
      expect(page.highlightField, 'reduce_motion');
      expect(find.widgetWithText(ListTile, 'Reduce motion'), findsOneWidget);
    });

    testWidgets(
        'a search result with no fixed row to highlight (Plugins entries) '
        'still navigates without a highlightField and without crashing',
        (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'Plugin catalog');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Plugin catalog'));
      await tester.pumpAndSettle();

      expect(find.text('Install a plugin'), findsOneWidget);
    });

    testWidgets(
        'searching "Restore Omnis" navigates to BackupSettingsPage, same '
        'no-fixed-row shape as the Plugins entries', (tester) async {
      await pumpSettings(tester);

      await tester.enterText(find.byType(TextField), 'Restore Omnis');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Restore Omnis'));
      await tester.pumpAndSettle();

      expect(find.byType(BackupSettingsPage), findsOneWidget);
    });

    testWidgets(
        'searching "Enable keyboard shortcuts" opens KeyboardSettingsPage '
        'with that row as the highlight target', (tester) async {
      await pumpSettings(tester);

      await tester.enterText(
          find.byType(TextField), 'Enable keyboard shortcuts');
      await tester.pumpAndSettle();
      await tester.tap(
          find.widgetWithText(ListTile, 'Enable keyboard shortcuts'));
      await tester.pumpAndSettle();

      final page = tester
          .widget<KeyboardSettingsPage>(find.byType(KeyboardSettingsPage));
      expect(page.highlightField, 'keyboard_shortcuts_enabled');
      expect(
          find.widgetWithText(ListTile, 'Enable keyboard shortcuts'),
          findsOneWidget);
    });
  });
}
