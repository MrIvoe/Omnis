import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
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
    expect(find.text('Plugins'), findsOneWidget);
  });

  testWidgets(
      'tapping Plugins actually navigates to the Plugins page — this was '
      'previously unreachable from anywhere in the running app', (tester) async {
    await pumpSettings(tester);

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
}
