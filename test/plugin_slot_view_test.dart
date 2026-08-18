import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// Pumps a real widget tree and hands back whatever `build` returns from a
/// real `BuildContext` — `_renderDeclarative` calls `Theme.of(context)`,
/// so every case here needs a genuine context, not a stub.
Future<Widget?> renderInTree(
  WidgetTester tester,
  dynamic item, {
  PluginSlotAction? onAction,
  PluginSlotPanelFetcher? onFetchPanel,
}) async {
  Widget? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        result = renderPluginSlotItem(context, item,
            onAction: onAction, onFetchPanel: onFetchPanel);
        return result ?? const SizedBox.shrink();
      }),
    ),
  ));
  await tester.pump();
  return result;
}

void main() {
  group('renderPluginSlotItem — toggle', () {
    testWidgets('renders a Switch reflecting the declared value',
        (tester) async {
      final rendered = await renderInTree(tester,
          {'type': 'toggle', 'text': 'Enabled', 'value': true, 'hook': 'h'});

      expect(rendered, isNotNull);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('tapping calls onAction with the hook and the flipped value',
        (tester) async {
      String? calledHook;
      List<dynamic>? calledArgs;
      await renderInTree(
        tester,
        {'type': 'toggle', 'text': 'Enabled', 'value': false, 'hook': 'onFlip'},
        onAction: (hook, args) {
          calledHook = hook;
          calledArgs = args;
        },
      );

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(calledHook, 'onFlip');
      expect(calledArgs, [true]);
    });

    testWidgets('the Switch is disabled when no onAction is supplied',
        (tester) async {
      await renderInTree(tester,
          {'type': 'toggle', 'text': 'Enabled', 'value': true, 'hook': 'h'});

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);
    });

    testWidgets('missing "hook" renders nothing', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'toggle', 'text': 'Enabled', 'value': true});
      expect(rendered, isNull);
    });

    testWidgets('missing/non-bool "value" renders nothing', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'toggle', 'text': 'Enabled', 'hook': 'h'});
      expect(rendered, isNull);
    });
  });

  group('renderPluginSlotItem — button', () {
    testWidgets('renders an OutlinedButton with the declared text',
        (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'button', 'text': 'Do it', 'hook': 'h'});

      expect(rendered, isNotNull);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);
    });

    testWidgets('tapping calls onAction with the hook and no args',
        (tester) async {
      String? calledHook;
      List<dynamic>? calledArgs;
      await renderInTree(
        tester,
        {'type': 'button', 'text': 'Do it', 'hook': 'onPress'},
        onAction: (hook, args) {
          calledHook = hook;
          calledArgs = args;
        },
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      expect(calledHook, 'onPress');
      expect(calledArgs, isEmpty);
    });

    testWidgets('the button is disabled when no onAction is supplied',
        (tester) async {
      await renderInTree(
          tester, {'type': 'button', 'text': 'Do it', 'hook': 'h'});

      final button =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('missing "hook" renders nothing', (tester) async {
      final rendered =
          await renderInTree(tester, {'type': 'button', 'text': 'Do it'});
      expect(rendered, isNull);
    });
  });

  group('renderPluginSlotItem — existing types unaffected', () {
    testWidgets('text still renders as plain Text', (tester) async {
      final rendered =
          await renderInTree(tester, {'type': 'text', 'text': 'Hi'});
      expect(rendered, isA<Text>());
      expect(find.text('Hi'), findsOneWidget);
    });

    testWidgets('badge still renders with its icon', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'badge', 'text': 'Active', 'icon': 'info'});
      expect(rendered, isNotNull);
      expect(find.text('Active'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });

  group('renderPluginSlotItem — nav_item', () {
    testWidgets('renders an icon-above-label tile', (tester) async {
      final rendered = await renderInTree(tester, {
        'type': 'nav_item',
        'text': 'Stats',
        'icon': 'history',
        'hook': 'openStats',
      });
      expect(rendered, isNotNull);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets(
        'tapping a String-hook nav_item calls onFetchPanel with the '
        'right hook name, not onAction', (tester) async {
      String? fetchedHook;
      List<dynamic>? fetchedArgs;
      var actionCalled = false;
      await renderInTree(
        tester,
        {
          'type': 'nav_item',
          'text': 'Stats',
          'icon': 'history',
          'hook': 'openStats',
        },
        onAction: (hook, args) => actionCalled = true,
        onFetchPanel: (hook, args) async {
          fetchedHook = hook;
          fetchedArgs = args;
          return null; // no panel items -> no sheet, still proves the call
        },
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(fetchedHook, 'openStats');
      // A single `null`, not an empty list — see _handleTap's own doc
      // comment: a genuinely empty args list hits a real dart_eval bug
      // when the guest hook's return value is a string-valued Map/List
      // literal.
      expect(fetchedArgs, const [null]);
      expect(actionCalled, isFalse);
    });

    testWidgets(
        'a panel returned by the hook opens in a bottom sheet, built from '
        'the same declarative vocabulary', (tester) async {
      await renderInTree(
        tester,
        {
          'type': 'nav_item',
          'text': 'Stats',
          'icon': 'history',
          'hook': 'openStats',
        },
        onFetchPanel: (hook, args) async => [
          {'type': 'text', 'text': 'Plays this week: 42'},
        ],
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Plays this week: 42'), findsOneWidget);
    });

    testWidgets(
        'a WidgetBuilder-hook nav_item (bundled plugin) pushes a real page '
        'via Navigator.push, never onFetchPanel', (tester) async {
      var fetchPanelCalled = false;
      Widget buildPage(BuildContext context) =>
          const Scaffold(body: Text('Bundled plugin page'));

      await renderInTree(
        tester,
        {
          'type': 'nav_item',
          'text': 'Open',
          'icon': 'music',
          'hook': buildPage,
        },
        onFetchPanel: (hook, args) async {
          fetchPanelCalled = true;
          return null;
        },
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(find.text('Bundled plugin page'), findsOneWidget);
      expect(fetchPanelCalled, isFalse);
    });

    testWidgets('missing "hook" renders nothing', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'nav_item', 'text': 'Stats', 'icon': 'history'});
      expect(rendered, isNull);
    });

    testWidgets('a non-String, non-WidgetBuilder "hook" renders nothing',
        (tester) async {
      final rendered = await renderInTree(tester, {
        'type': 'nav_item',
        'text': 'Stats',
        'icon': 'history',
        'hook': 42,
      });
      expect(rendered, isNull);
    });

    testWidgets('missing "text" renders nothing', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'nav_item', 'icon': 'history', 'hook': 'h'});
      expect(rendered, isNull);
    });
  });

  group('renderPluginSlotItem — malformed values never crash', () {
    testWidgets('an unrecognized type renders nothing', (tester) async {
      final rendered = await renderInTree(
          tester, {'type': 'not_a_real_type', 'text': 'x', 'hook': 'h'});
      expect(rendered, isNull);
    });

    testWidgets('a bare non-Map, non-Widget, non-String item renders nothing',
        (tester) async {
      final rendered = await renderInTree(tester, 12345);
      expect(rendered, isNull);
    });

    testWidgets('null item renders nothing', (tester) async {
      final rendered = await renderInTree(tester, null);
      expect(rendered, isNull);
    });
  });
}
