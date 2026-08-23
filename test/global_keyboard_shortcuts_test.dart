import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/ui/global_keyboard_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A controllable fake — real key events must reach real [AudioEngine]
/// calls, not just render a widget, matching
/// `test/player_layouts_test.dart`'s "real D-pad/keyboard navigation"
/// group's own bar for what counts as proof here.
class _FakeEngine implements AudioEngine {
  bool _isPlaying = false;
  Duration _position = const Duration(seconds: 30);
  double _volume = 0.5;

  bool playCalled = false;
  bool pauseCalled = false;
  bool nextCalled = false;
  bool previousCalled = false;
  Duration? seekedTo;
  double? volumeSetTo;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Duration get position => _position;

  @override
  double get volume => _volume;

  @override
  Future<void> play() async {
    playCalled = true;
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    _isPlaying = false;
  }

  @override
  Future<bool> next({bool wrap = false}) async {
    nextCalled = true;
    return true;
  }

  @override
  Future<bool> previous() async {
    previousCalled = true;
    return true;
  }

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    _position = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeSetTo = volume;
    _volume = volume;
  }

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

  Future<_FakeEngine> pumpHarness(WidgetTester tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalKeyboardShortcuts(
          engine: engine,
          child: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return engine;
  }

  testWidgets('Space toggles play when paused', (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playCalled, isTrue);
    expect(engine.pauseCalled, isFalse);
  });

  testWidgets('Space toggles pause when playing', (tester) async {
    final engine = await pumpHarness(tester);
    engine._isPlaying = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.pauseCalled, isTrue);
    expect(engine.playCalled, isFalse);
  });

  testWidgets(
      'media play/pause hardware key toggles play the same as '
      'Space', (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(engine.playCalled, isTrue);
  });

  testWidgets('plain Right arrow seeks forward 10s, not next track',
      (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.seekedTo, const Duration(seconds: 40));
    expect(engine.nextCalled, isFalse);
  });

  testWidgets('plain Left arrow seeks backward 10s, clamped at zero',
      (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.seekedTo, const Duration(seconds: 20));

    engine.seekedTo = null;
    engine._position = const Duration(seconds: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.seekedTo, Duration.zero);
  });

  testWidgets('Ctrl+Right skips to next track, not a seek', (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(engine.nextCalled, isTrue);
    expect(engine.seekedTo, isNull);
  });

  testWidgets('Ctrl+Left goes to the previous track, not a seek',
      (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(engine.previousCalled, isTrue);
    expect(engine.seekedTo, isNull);
  });

  testWidgets('Up arrow raises volume by 5%, clamped at 1.0', (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.volumeSetTo, closeTo(0.55, 0.0001));

    engine.volumeSetTo = null;
    engine._volume = 0.98;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(engine.volumeSetTo, 1.0);
  });

  testWidgets('Down arrow lowers volume by 5%, clamped at 0.0', (tester) async {
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumeSetTo, closeTo(0.45, 0.0001));

    engine.volumeSetTo = null;
    engine._volume = 0.02;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.volumeSetTo, 0.0);
  });

  testWidgets('M mutes when volume is non-zero', (tester) async {
    final engine = await pumpHarness(tester);
    engine._volume = 0.7;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumeSetTo, 0.0);
  });

  testWidgets('a second M press restores the exact volume the first one '
      'muted', (tester) async {
    final engine = await pumpHarness(tester);
    engine._volume = 0.35;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumeSetTo, 0.0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volumeSetTo, 0.35);
  });

  testWidgets(
      'disabling keyboard shortcuts via AppSettings makes every '
      'binding a no-op', (tester) async {
    AppSettings.instance.keyboardShortcutsEnabled = false;
    final engine = await pumpHarness(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playCalled, isFalse);
  });

  testWidgets(
      'a focused TextField never leaks Space through to the '
      'global play/pause shortcut', (tester) async {
    final engine = _FakeEngine();
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GlobalKeyboardShortcuts(
          engine: engine,
          child: TextField(controller: controller, autofocus: true),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // A real descendant autofocus (this TextField) must win the focus
    // race against GlobalKeyboardShortcuts' own fallback anchor — assert
    // that directly, not just the behavioral consequence below, so a
    // regression here fails with a clear cause.
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
      reason: 'the TextField, not the fallback anchor, should hold focus',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(engine.playCalled, isFalse);
  });

  group('touch-primary platforms (Task 5)', () {
    // `Platform.isX` reflects whatever host this suite actually runs on
    // (desktop on CI/dev machines) and can't be faked without a seam —
    // `PlatformCapabilities.debugIsTouchPrimaryOverride` is exactly that
    // seam (see its own doc comment), letting this group exercise the
    // touch-primary branch regardless of the real host platform.
    setUp(() => PlatformCapabilities.debugIsTouchPrimaryOverride = true);
    tearDown(PlatformCapabilities.resetOverridesForTesting);

    testWidgets(
        'a settings-driven binding (Space) does not fire on a '
        'touch-primary platform', (tester) async {
      final engine = await pumpHarness(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(engine.playCalled, isFalse);
    });

    testWidgets(
        'a remapped settings-driven binding still does not fire on a '
        'touch-primary platform', (tester) async {
      await AppSettings.instance.setShortcutBinding(
        ShortcutAction.toggleMute,
        ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
      );
      final engine = await pumpHarness(tester);
      engine._volume = 0.7;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(engine.volumeSetTo, isNull);
    });

    testWidgets(
        'hardware media play/pause still fires on a touch-primary platform '
        '— real Bluetooth/wired headset buttons route through this same '
        'path on Android', (tester) async {
      final engine = await pumpHarness(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(engine.playCalled, isTrue);
    });

    testWidgets('hardware media next/previous still fire on a '
        'touch-primary platform', (tester) async {
      final engine = await pumpHarness(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackNext);
      await tester.pump();
      expect(engine.nextCalled, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaTrackPrevious);
      await tester.pump();
      expect(engine.previousCalled, isTrue);
    });
  });

  group('item 48 remapping', () {
    testWidgets('a remapped key (set before the widget is pumped) triggers '
        'the action; the old default key no longer does', (tester) async {
      await AppSettings.instance.setShortcutBinding(
        ShortcutAction.toggleMute,
        ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
      );
      final engine = await pumpHarness(tester);
      engine._volume = 0.7;

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(engine.volumeSetTo, 0.0);

      engine.volumeSetTo = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(engine.volumeSetTo, isNull,
          reason: 'M was reassigned away from mute, so it must no longer '
              'trigger it');
    });

    testWidgets('a remap made *after* the widget is already live takes '
        'effect on the next keypress, no rebuild needed from the caller',
        (tester) async {
      final engine = await pumpHarness(tester);
      engine._volume = 0.7;

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(engine.volumeSetTo, 0.0);

      await AppSettings.instance.setShortcutBinding(
        ShortcutAction.toggleMute,
        ShortcutBinding(keyId: LogicalKeyboardKey.keyN.keyId),
      );
      await tester.pump();

      engine.volumeSetTo = null;
      engine._volume = 0.4;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(engine.volumeSetTo, 0.0,
          reason: 'the live remap to N should already be active');
    });
  });
}
