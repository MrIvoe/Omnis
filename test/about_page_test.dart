import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/omnis_version.dart';
import 'package:omnis/ui/about_page.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records every URL a tap tried to open, instead of launching a real
/// browser — same "fake the platform interface" pattern this test
/// suite already uses for path_provider/flutter_secure_storage.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUrlLauncher fakeLauncher;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    fakeLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  testWidgets('shows the current app version', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    expect(find.text('Version $omnisCoreVersion'), findsOneWidget);
  });

  testWidgets('the auto-update toggle defaults off and persists when '
      'flipped', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    final tile = tester.widget<SwitchListTile>(find.widgetWithText(
        SwitchListTile, 'Automatically check for updates'));
    expect(tile.value, isFalse);

    await tester.tap(find.text('Automatically check for updates'));
    await tester.pump();

    expect(AppSettings.instance.autoAppUpdateCheckEnabled, isTrue);
  });

  testWidgets('no update-available banner shows when nothing is cached',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    expect(find.textContaining('Update available'), findsNothing);
  });

  testWidgets('a genuinely newer cached version shows the update banner, '
      'and tapping it opens the GitHub releases page', (tester) async {
    AppSettings.instance.lastKnownAppUpdateVersion = '999.0.0';

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    expect(find.text('Update available: v999.0.0'), findsOneWidget);

    await tester.tap(find.text('Update available: v999.0.0'));
    await tester.pump();

    expect(fakeLauncher.launchedUrls,
        contains('https://github.com/MrIvoe/Omnis/releases'));
  });

  testWidgets('a cached version that is not actually newer than the '
      'current one never shows the banner — re-validated on read, not '
      'trusted blindly', (tester) async {
    AppSettings.instance.lastKnownAppUpdateVersion = omnisCoreVersion;

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    expect(find.textContaining('Update available'), findsNothing);
  });

  testWidgets('tapping GitHub/Discord/Support each open the right URL',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    await tester.tap(find.text('GitHub'));
    await tester.pump();
    await tester.tap(find.text('Discord'));
    await tester.pump();
    await tester.tap(find.text('Support Omnis'));
    await tester.pump();

    expect(fakeLauncher.launchedUrls, [
      'https://github.com/MrIvoe/Omnis',
      'https://discord.gg/jQRyckRVup',
      'https://buy.stripe.com/9B6aEZ86Jf3q86ugbI8Zq00',
    ]);
  });
}
