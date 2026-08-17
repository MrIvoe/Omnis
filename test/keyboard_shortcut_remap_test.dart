import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';

void main() {
  group('ShortcutBinding storage round-trip', () {
    test('encodes and decodes back to an equal binding', () {
      const binding = ShortcutBinding(
        keyId: 65,
        control: true,
        shift: false,
        alt: true,
        meta: false,
      );
      final decoded = ShortcutBinding.fromStorageString(binding.toStorageString());
      expect(decoded, binding);
    });

    test('malformed input returns null rather than throwing', () {
      expect(ShortcutBinding.fromStorageString(''), isNull);
      expect(ShortcutBinding.fromStorageString('not-a-binding'), isNull);
      expect(ShortcutBinding.fromStorageString('abc:true:false:false:false'),
          isNull);
      expect(ShortcutBinding.fromStorageString('1:maybe:false:false:false'),
          isNull);
      expect(ShortcutBinding.fromStorageString('1:true:false:false'), isNull);
    });
  });

  group('ShortcutBinding equality', () {
    test('two bindings with the same key and modifiers are equal', () {
      const a = ShortcutBinding(keyId: 1, control: true);
      const b = ShortcutBinding(keyId: 1, control: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different modifier breaks equality', () {
      const a = ShortcutBinding(keyId: 1, control: true);
      const b = ShortcutBinding(keyId: 1, control: false);
      expect(a, isNot(b));
    });

    test('a different key breaks equality', () {
      const a = ShortcutBinding(keyId: 1);
      const b = ShortcutBinding(keyId: 2);
      expect(a, isNot(b));
    });
  });

  group('ShortcutBinding.displayLabel', () {
    test('a plain key with no modifiers', () {
      final binding = ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId);
      expect(binding.displayLabel, 'M');
    });

    test('modifiers are prefixed in a fixed order', () {
      final binding = ShortcutBinding(
        keyId: LogicalKeyboardKey.keyK.keyId,
        control: true,
        shift: true,
      );
      expect(binding.displayLabel, 'Ctrl+Shift+K');
    });
  });

  group('defaultShortcutBindings', () {
    test('has exactly the 8 remappable actions', () {
      expect(defaultShortcutBindings.keys.toSet(),
          ShortcutAction.values.toSet());
    });

    test('matches GlobalKeyboardShortcuts\' original hardcoded bindings —'
        ' a regression guard for the hardcoded-to-settings-driven move',
        () {
      expect(defaultShortcutBindings[ShortcutAction.togglePlayPause],
          ShortcutBinding(keyId: LogicalKeyboardKey.space.keyId));
      expect(
          defaultShortcutBindings[ShortcutAction.nextTrack],
          ShortcutBinding(
              keyId: LogicalKeyboardKey.arrowRight.keyId, control: true));
      expect(
          defaultShortcutBindings[ShortcutAction.previousTrack],
          ShortcutBinding(
              keyId: LogicalKeyboardKey.arrowLeft.keyId, control: true));
      expect(defaultShortcutBindings[ShortcutAction.seekForward],
          ShortcutBinding(keyId: LogicalKeyboardKey.arrowRight.keyId));
      expect(defaultShortcutBindings[ShortcutAction.seekBackward],
          ShortcutBinding(keyId: LogicalKeyboardKey.arrowLeft.keyId));
      expect(defaultShortcutBindings[ShortcutAction.volumeUp],
          ShortcutBinding(keyId: LogicalKeyboardKey.arrowUp.keyId));
      expect(defaultShortcutBindings[ShortcutAction.volumeDown],
          ShortcutBinding(keyId: LogicalKeyboardKey.arrowDown.keyId));
      expect(defaultShortcutBindings[ShortcutAction.toggleMute],
          ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId));
    });
  });

  group('findConflict', () {
    test('returns null when nothing else uses the proposed binding', () {
      final proposed = ShortcutBinding(keyId: LogicalKeyboardKey.keyZ.keyId);
      expect(
        findConflict(
            ShortcutAction.toggleMute, proposed, defaultShortcutBindings),
        isNull,
      );
    });

    test('finds the other action already bound to the proposed key', () {
      final proposed = ShortcutBinding(keyId: LogicalKeyboardKey.space.keyId);
      expect(
        findConflict(
            ShortcutAction.toggleMute, proposed, defaultShortcutBindings),
        ShortcutAction.togglePlayPause,
      );
    });

    test('reassigning an action to its own current binding is not a '
        'conflict', () {
      final own = defaultShortcutBindings[ShortcutAction.toggleMute]!;
      expect(
        findConflict(ShortcutAction.toggleMute, own, defaultShortcutBindings),
        isNull,
      );
    });
  });

  group('isReservedActivationKey', () {
    test('true for a bare Space/Enter/Tab', () {
      expect(
          isReservedActivationKey(
              ShortcutBinding(keyId: LogicalKeyboardKey.space.keyId)),
          isTrue);
      expect(
          isReservedActivationKey(
              ShortcutBinding(keyId: LogicalKeyboardKey.enter.keyId)),
          isTrue);
      expect(
          isReservedActivationKey(
              ShortcutBinding(keyId: LogicalKeyboardKey.tab.keyId)),
          isTrue);
    });

    test('false when a modifier is held, even for Space', () {
      expect(
        isReservedActivationKey(ShortcutBinding(
            keyId: LogicalKeyboardKey.space.keyId, control: true)),
        isFalse,
      );
    });

    test('false for an ordinary letter/arrow key', () {
      expect(
          isReservedActivationKey(
              ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId)),
          isFalse);
      expect(
          isReservedActivationKey(
              ShortcutBinding(keyId: LogicalKeyboardKey.arrowUp.keyId)),
          isFalse);
    });
  });

  group('isValidTrigger', () {
    test('false for bare modifier keys, sided or unsided', () {
      expect(isValidTrigger(LogicalKeyboardKey.control), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.controlLeft), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.controlRight), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.shift), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.shiftLeft), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.alt), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.altRight), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.meta), isFalse);
      expect(isValidTrigger(LogicalKeyboardKey.metaLeft), isFalse);
    });

    test('true for an ordinary key', () {
      expect(isValidTrigger(LogicalKeyboardKey.keyK), isTrue);
      expect(isValidTrigger(LogicalKeyboardKey.arrowUp), isTrue);
      expect(isValidTrigger(LogicalKeyboardKey.space), isTrue);
    });
  });

  group('ShortcutBinding.fromActivator/toActivator round-trip', () {
    test('round-trips through a real SingleActivator', () {
      const activator =
          SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true);
      final binding = ShortcutBinding.fromActivator(activator);
      final rebuilt = binding.toActivator();
      expect(rebuilt.trigger, activator.trigger);
      expect(rebuilt.control, activator.control);
      expect(rebuilt.shift, activator.shift);
    });
  });
}
