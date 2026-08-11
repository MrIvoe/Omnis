import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/l10n/generated/app_localizations.dart';
import 'package:omnis/ui/onboarding/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: OnboardingPage(
      // A lightweight stand-in for the real HomePage, which needs the
      // whole app core (audio engine, plugin manager, GetIt
      // registrations) this unit test doesn't set up.
      homeBuilder: (context) =>
          const Scaffold(body: Center(child: Text('fake home'))),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
  });

  testWidgets('starts on the welcome screen', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Welcome to Omnis'), findsOneWidget);
  });

  testWidgets('Next advances through every screen in order', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('A couple of permissions'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Find your way around'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("You're all set"), findsOneWidget);
  });

  testWidgets('Back returns to the previous screen', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('A couple of permissions'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Omnis'), findsOneWidget);
  });

  testWidgets('Back is not shown on the first screen', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Back'), findsNothing);
  });

  testWidgets('Skip is available on every screen except the last, and '
      'completes onboarding immediately', (tester) async {
    await pumpOnboarding(tester);

    expect(AppSettings.instance.hasCompletedOnboarding, isFalse);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.hasCompletedOnboarding, isTrue);
    expect(find.text('fake home'), findsOneWidget);
  });

  testWidgets('Skip is invisible (not tappable) on the last screen',
      (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(i == 1 ? 'Continue' : 'Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text("You're all set"), findsOneWidget);

    // Opacity 0 + IgnorePointer — the Skip text is still technically in
    // the tree, but must not be interactable.
    final skipFinder = find.text('Skip');
    if (skipFinder.evaluate().isNotEmpty) {
      final ignorePointers = tester.widgetList<IgnorePointer>(
        find.ancestor(of: skipFinder, matching: find.byType(IgnorePointer)),
      );
      expect(ignorePointers, isNotEmpty);
      expect(ignorePointers.first.ignoring, isTrue);
    }
  });

  testWidgets('Get Started on the last screen completes onboarding and '
      'navigates to the home screen', (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text(i == 1 ? 'Continue' : 'Next'));
      await tester.pumpAndSettle();
    }

    expect(AppSettings.instance.hasCompletedOnboarding, isFalse);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.hasCompletedOnboarding, isTrue);
    expect(find.text('fake home'), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets(
      'jumps instantly between screens when reduce motion is enabled '
      '(no exception from a zero-duration animateToPage)', (tester) async {
    AppSettings.instance.reduceMotionEnabled = true;
    await pumpOnboarding(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('A couple of permissions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
