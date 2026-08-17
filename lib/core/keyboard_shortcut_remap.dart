import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Item 48's "per-shortcut remapping/conflict detection" gap —
/// `KeyboardSettingsPage`'s own doc comment previously named this as
/// deliberately deferred, since remapping needs its own conflict-
/// detection UI (reassigning Space risks colliding with a focused
/// control's own Space-to-activate binding), not just an on/off switch.
///
/// The 8 actions [GlobalKeyboardShortcuts] binds to a literal, plain
/// (non-hardware) key today. Deliberately excludes the three media-key
/// bindings (play/pause, next, previous) — those are OS/hardware
/// signals, not something a user would remap via a keyboard, and stay
/// hardcoded/always-on regardless of this feature.
enum ShortcutAction {
  togglePlayPause,
  nextTrack,
  previousTrack,
  seekForward,
  seekBackward,
  volumeUp,
  volumeDown,
  toggleMute,
}

/// A remappable key combination — the persisted, value-comparable
/// counterpart to Flutter's [SingleActivator]. Real `==`/`hashCode` (by
/// [keyId] + modifiers) matter here specifically because [findConflict]
/// depends on comparing bindings *by value*, not identity — the same
/// class of bug this codebase's own build log flags elsewhere as a
/// known pitfall (comparing a `List` field by reference instead of deep
/// equality).
@immutable
class ShortcutBinding {
  final int keyId;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  const ShortcutBinding({
    required this.keyId,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  factory ShortcutBinding.fromActivator(SingleActivator activator) =>
      ShortcutBinding(
        keyId: activator.trigger.keyId,
        control: activator.control,
        shift: activator.shift,
        alt: activator.alt,
        meta: activator.meta,
      );

  SingleActivator toActivator() => SingleActivator(
        LogicalKeyboardKey(keyId),
        control: control,
        shift: shift,
        alt: alt,
        meta: meta,
      );

  String toStorageString() => '$keyId:$control:$shift:$alt:$meta';

  /// Parses [ShortcutBinding.toStorageString]'s own format. Returns
  /// `null` for anything malformed — the caller degrades that one
  /// action back to its default rather than throwing, the same
  /// per-entry-defensive-decode stance `LibraryStore`/`PlaylistStore`
  /// already take for their own JSON stores.
  static ShortcutBinding? fromStorageString(String value) {
    final parts = value.split(':');
    if (parts.length != 5) return null;
    final keyId = int.tryParse(parts[0]);
    if (keyId == null) return null;
    bool? parseBool(String s) => s == 'true' ? true : (s == 'false' ? false : null);
    final control = parseBool(parts[1]);
    final shift = parseBool(parts[2]);
    final alt = parseBool(parts[3]);
    final meta = parseBool(parts[4]);
    if (control == null || shift == null || alt == null || meta == null) {
      return null;
    }
    return ShortcutBinding(
        keyId: keyId, control: control, shift: shift, alt: alt, meta: meta);
  }

  /// Human-readable label, e.g. `"Ctrl+Shift+K"` — built from the
  /// modifier flags plus [LogicalKeyboardKey.keyLabel] (a real,
  /// non-debug-only getter, unlike `debugName`, which is asserted-away
  /// in release builds and unsafe to show users). Falls back to a
  /// `Key 0x...` placeholder for an unlabeled key rather than showing
  /// nothing — an honest "can't name this key," not a silent gap.
  ///
  /// A handful of keys' own [LogicalKeyboardKey.keyLabel] is the literal
  /// (whitespace/control) character they produce, not a human-readable
  /// name — `space`'s `keyLabel` is a single space character, not the
  /// word "Space" — so those get an explicit friendly override rather
  /// than showing invisible or confusing text.
  static const _friendlyNames = {
    ' ': 'Space',
    '\t': 'Tab',
    '\n': 'Enter',
    '\r': 'Enter',
  };

  String get displayLabel {
    final parts = <String>[
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
    ];
    final key = LogicalKeyboardKey(keyId);
    final label = key.keyLabel;
    final friendly = _friendlyNames[label];
    parts.add(friendly ??
        (label.isNotEmpty ? label : 'Key 0x${keyId.toRadixString(16)}'));
    return parts.join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.keyId == keyId &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(keyId, control, shift, alt, meta);
}

/// The plugin's original hardcoded bindings, unchanged — a regression
/// guard so moving from "hardcoded in the widget" to "settings-driven"
/// can't silently change default behavior for anyone who never opens
/// the remap UI.
final Map<ShortcutAction, ShortcutBinding> defaultShortcutBindings = {
  ShortcutAction.togglePlayPause:
      ShortcutBinding(keyId: LogicalKeyboardKey.space.keyId),
  ShortcutAction.nextTrack: ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowRight.keyId, control: true),
  ShortcutAction.previousTrack: ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowLeft.keyId, control: true),
  ShortcutAction.seekForward:
      ShortcutBinding(keyId: LogicalKeyboardKey.arrowRight.keyId),
  ShortcutAction.seekBackward:
      ShortcutBinding(keyId: LogicalKeyboardKey.arrowLeft.keyId),
  ShortcutAction.volumeUp:
      ShortcutBinding(keyId: LogicalKeyboardKey.arrowUp.keyId),
  ShortcutAction.volumeDown:
      ShortcutBinding(keyId: LogicalKeyboardKey.arrowDown.keyId),
  ShortcutAction.toggleMute:
      ShortcutBinding(keyId: LogicalKeyboardKey.keyM.keyId),
};

/// The other action already bound to [proposed], if any, among
/// [current] — excluding [action] itself (reassigning an action to its
/// own current binding is never a conflict). `null` when there's no
/// clash. Pure — the actual "conflict detection" this gap names.
ShortcutAction? findConflict(
  ShortcutAction action,
  ShortcutBinding proposed,
  Map<ShortcutAction, ShortcutBinding> current,
) {
  for (final entry in current.entries) {
    if (entry.key == action) continue;
    if (entry.value == proposed) return entry.key;
  }
  return null;
}

/// True for an unmodified Space/Enter/Tab — the exact concern
/// `KeyboardSettingsPage`'s own doc comment named ("reassigning Space to
/// something else risks colliding with a focused control's own
/// Space-to-activate binding"). A non-blocking warning, not a hard
/// block — a user who genuinely wants this can still save it.
bool isReservedActivationKey(ShortcutBinding binding) {
  if (binding.control || binding.shift || binding.alt || binding.meta) {
    return false;
  }
  final key = LogicalKeyboardKey(binding.keyId);
  return key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.tab;
}

/// False for a bare modifier key (Control/Shift/Alt/Meta, sided or
/// unsided) used as the *trigger* itself — mirroring [SingleActivator]'s
/// own debug-only assert to the same effect, so a remap-capture flow
/// fails safe in a release build too, where that assert doesn't run.
bool isValidTrigger(LogicalKeyboardKey key) {
  final bareModifiers = {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };
  return !bareModifiers.contains(key);
}
