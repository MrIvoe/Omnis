import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_editor_page.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same fake path_provider pattern as declarative_layout_test.dart, so
/// LayoutManager's real installFromText -> LayoutInstaller -> disk path
/// runs against a throwaway temp directory instead of the real one.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _FakePathProvider(this.tempDir);

  @override
  Future<String?> getApplicationSupportPath() async => tempDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String tempDir;
  late LayoutManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir = (await Directory.systemTemp.createTemp('omnis_layout_editor_test'))
        .path;
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    manager = LayoutManager();
    await manager.loadInstalled();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LayoutEditorPage(layoutManager: manager),
    ));
    await tester.pump();
  }

  testWidgets('tapping a palette chip places it on the canvas and removes '
      'it from the palette', (tester) async {
    await pumpEditor(tester);

    expect(find.byIcon(Icons.album), findsOneWidget,
        reason: 'only in the palette chip before placement');

    await tester.tap(find.widgetWithText(ActionChip, 'Album Art'));
    await tester.pump();

    expect(find.byKey(const ValueKey('placed_canvas_album_art')),
        findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Album Art'), findsNothing,
        reason: 'a placed component is no longer offered again in the palette');
    expect(find.byIcon(Icons.album), findsOneWidget,
        reason: 'still shown once, now as the placed chip itself');
  });

  testWidgets('tapping the × on a placed component removes it and it '
      'reappears in the palette', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Album Art'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.byKey(const ValueKey('placed_canvas_album_art')),
        findsNothing);
    expect(find.widgetWithText(ActionChip, 'Album Art'), findsOneWidget);
  });

  testWidgets(
      'dragging a placed component moves it, clamped within the canvas '
      'bounds even when dragged far past the edge', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Album Art'));
    await tester.pump();

    final canvasSize =
        tester.getSize(find.byKey(const ValueKey('layout_editor_canvas')));

    // Album Art's footprint is 180x180 (see _availableComponents) — drag
    // it far past every edge in both directions.
    final handle = find.ancestor(
      of: find.byIcon(Icons.album),
      matching: find.byType(GestureDetector),
    );
    final canvasPositioned =
        find.byKey(const ValueKey('placed_canvas_album_art'));

    await tester.drag(handle, const Offset(-5000, -5000));
    await tester.pump();
    var positioned = tester.widget<Positioned>(canvasPositioned);
    expect(positioned.left, 0);
    expect(positioned.top, 0);

    await tester.drag(handle, const Offset(5000, 5000));
    await tester.pump();
    positioned = tester.widget<Positioned>(canvasPositioned);
    expect(positioned.left, closeTo(canvasSize.width - 180, 0.5));
    expect(positioned.top, closeTo(canvasSize.height - 180, 0.5));
  });

  testWidgets('Save is refused with no components placed', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Add at least one component first.'), findsOneWidget);
    // Still on the editor page — a real Navigator.pop would have removed it.
    expect(find.byType(LayoutEditorPage), findsOneWidget);
  });

  testWidgets('Save is refused with an empty name', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Album Art'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '');

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Give your layout a name.'), findsOneWidget);
  });

  testWidgets(
      'Save with a name and at least one component installs the layout, '
      'selects it, and pops the page', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LayoutEditorPage(layoutManager: manager),
          )),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Album Art'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'My Cool Layout');
    await tester.pump();

    final before = manager.allLayouts.length;
    // Save triggers a real dart:io File write (LayoutInstaller ->
    // RemoteTextStore.persist, against the faked path_provider temp
    // dir). The tap (which synchronously starts _save() up to its
    // first await) and the real-I/O wait both have to happen *inside*
    // runAsync's real zone — _save()'s whole async chain is scoped to
    // wherever it was started, so a runAsync call placed only *after*
    // the tap does not retroactively let an already-pending await in
    // the fake-time test zone resolve.
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump();
    // Saving has genuinely finished by now (asserted below), so the
    // indeterminate spinner is gone — safe to let the pop's page
    // transition animation finish settling.
    await tester.pumpAndSettle();

    expect(manager.allLayouts.length, before + 1);
    expect(manager.allLayouts.any((l) => l.name == 'My Cool Layout'), isTrue);
    final saved =
        manager.allLayouts.firstWhere((l) => l.name == 'My Cool Layout');
    expect(AppSettings.instance.playerLayoutId, saved.id);
    // Popped back to the page that launched the editor.
    expect(find.byType(LayoutEditorPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
