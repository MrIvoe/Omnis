import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/main_core.dart';

/// Global service locator (the Core does not know about concrete features).
final GetIt locator = GetIt.instance;

/// Build and register the [MainCore] exactly once.
///
/// `main.dart` and `HomePage` each used to carry their own copy of this
/// logic, with slightly different registration (one registered
/// `AudioEngine` explicitly, the other by inference). A single entry point
/// means there is one answer to "is the core up?" no matter who asks.
Future<MainCore> ensureCoreReady() async {
  if (locator.isRegistered<MainCore>()) {
    return locator<MainCore>();
  }

  final core = MainCore();
  try {
    await core.initialize();
  } catch (e, st) {
    // A half-initialised core still plays audio; surfacing the error beats
    // refusing to start.
    debugPrint('Omnis: core initialization failed: $e');
    debugPrint('$st');
  }

  if (!locator.isRegistered<MainCore>()) {
    locator.registerSingleton<MainCore>(core);
  }
  if (!locator.isRegistered<AudioEngine>()) {
    locator.registerSingleton<AudioEngine>(core.audioEngine);
  }
  return locator<MainCore>();
}

/// Tear the core down and unregister it.
///
/// Only the app lifecycle should call this — a page must not dispose a
/// singleton it did not create.
Future<void> disposeCore() async {
  if (!locator.isRegistered<MainCore>()) return;
  final core = locator<MainCore>();
  await core.dispose();
  if (locator.isRegistered<AudioEngine>()) {
    await locator.unregister<AudioEngine>();
  }
  await locator.unregister<MainCore>();
}
