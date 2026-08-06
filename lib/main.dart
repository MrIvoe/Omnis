import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/home_page.dart';

export 'package:omnis/core/bootstrap.dart' show ensureCoreReady, locator;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only AppSettings is awaited before the first frame — it's a single
  // SharedPreferences read, fast enough that skipping it would just
  // trade one flicker (default theme, then a jump to the real one) for
  // another. The heavy part of startup — the audio engine, plugin
  // manager, and installed-plugin/layout disk I/O inside ensureCoreReady
  // and ensureLayoutManagerReady — used to run here too, which meant the
  // OS saw nothing but a blank window until all of it finished. Neither
  // is needed to paint the first frame: HomePage already gates on
  // _coreReady (a plain spinner, not a branded splash) and calls both
  // itself in initState, so they now run *after* something is on screen
  // instead of *before*.
  await AppSettings.instance.initialize();
  runApp(const OmnisApp());
}

/// Main Omnis application.
class OmnisApp extends StatefulWidget {
  const OmnisApp({super.key});

  @override
  State<OmnisApp> createState() => _OmnisAppState();
}

class _OmnisAppState extends State<OmnisApp> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return MaterialApp(
      title: 'Omnis Music Engine',
      theme: settings.themeData(Brightness.light),
      darkTheme: settings.themeData(Brightness.dark),
      themeMode: settings.themeMode,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
