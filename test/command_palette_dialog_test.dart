import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/ui/command_palette_dialog.dart';

void main() {
  testWidgets('every default command renders when the query is empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);

    // The dialog's own ListView is height-constrained, so the last item
    // isn't necessarily built until scrolled into view — same
    // `dragUntilVisible` pattern this codebase already uses for the same
    // underlying cause elsewhere (e.g. plugins_page_test.dart).
    await tester.dragUntilVisible(
      find.text('Scan library'),
      find.byType(ListView),
      const Offset(0, -100),
    );
    expect(find.text('Scan library'), findsOneWidget);
  });

  testWidgets('typing a query filters the list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'shuffle');
    await tester.pumpAndSettle();

    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a query matching nothing shows an explicit message',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyzzy');
    await tester.pumpAndSettle();

    expect(find.text('No commands match "xyzzy".'), findsOneWidget);
  });

  testWidgets('tapping a command runs its action and closes the dialog',
      (tester) async {
    var played = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: {
            'play': () => played = true,
          }),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(played, isTrue);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a command with no matching action in the map is a harmless '
      'no-op, not a crash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: const {}),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
  });

  testWidgets('pressing Enter runs the first matching command',
      (tester) async {
    var scanned = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showCommandPalette(context, actions: {
            'scan_library': () => scanned = true,
          }),
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'scan');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(scanned, isTrue);
  });
}
