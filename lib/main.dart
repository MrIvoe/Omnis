import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/main_core.dart';
import 'package:omnis/ui/home_page.dart';

/// Global service locator (Core does not know about concrete features).
final GetIt locator = GetIt.instance;

Future<MainCore> ensureCoreReady() async {
  if (locator.isRegistered<MainCore>()) {
    return locator<MainCore>();
  }

  final core = MainCore();
  try {
    await core.initialize();
  } catch (e, st) {
    debugPrint('Omnis: core initialization failed: $e');
    debugPrint('$st');
  }

  locator.registerSingleton<MainCore>(core);
  if (!locator.isRegistered<AudioEngine>()) {
    locator.registerSingleton<AudioEngine>(core.audioEngine);
  }
  return core;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.initialize();
  await ensureCoreReady();
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
