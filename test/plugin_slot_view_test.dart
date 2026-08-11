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
}) async {
  Widget? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        result = renderPluginSlotItem(context, item, onAction: onAction);
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
}
