import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';

/// Item 48's per-shortcut remap capture flow. Listens for the next real
/// non-modifier key press, then either commits it straight away, or —
/// for the two cases `KeyboardSettingsPage`'s own doc comment named as
/// needing real handling, not just a blind overwrite — asks first:
///
///  - a **conflict** ([findConflict] finds another action already bound
///    to the captured key) offers to swap the two actions' bindings
///    rather than silently leaving the other action unbound;
///  - a **reserved activation key** ([isReservedActivationKey] — a bare
///    Space/Enter/Tab) shows a non-blocking warning but still lets the
///    user save it if that's genuinely what they want.
///
/// Returns `true` via [Navigator.pop] once a binding was actually
/// written, `false`/`null` if the dialog was cancelled without saving.
Future<bool?> showShortcutCaptureDialog(
  BuildContext context,
  ShortcutAction action,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _ShortcutCaptureDialog(action: action),
  );
}

enum _CaptureStage { listening, conflict, reserved }

class _ShortcutCaptureDialog extends StatefulWidget {
  final ShortcutAction action;

  const _ShortcutCaptureDialog({required this.action});

  @override
  State<_ShortcutCaptureDialog> createState() =>
      _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  final _focusNode = FocusNode();
  _CaptureStage _stage = _CaptureStage.listening;
  ShortcutBinding? _candidate;
  ShortcutAction? _conflictingAction;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _commit(ShortcutBinding binding) async {
    final settings = AppSettings.instance;
    if (_conflictingAction != null) {
      // Swap: the conflicting action inherits whatever binding
      // widget.action previously had, so it's never left unbound.
      final previous = settings.shortcutBindings[widget.action]!;
      await settings.setShortcutBinding(_conflictingAction!, previous);
    }
    await settings.setShortcutBinding(widget.action, binding);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_stage != _CaptureStage.listening) return;
    final key = event.logicalKey;
    if (!isValidTrigger(key)) return; // a bare modifier — keep waiting.

    final candidate = ShortcutBinding(
      keyId: key.keyId,
      control: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );

    final conflict = findConflict(
      widget.action,
      candidate,
      AppSettings.instance.shortcutBindings,
    );
    if (conflict != null) {
      setState(() {
        _candidate = candidate;
        _conflictingAction = conflict;
        _stage = _CaptureStage.conflict;
      });
      return;
    }
    if (isReservedActivationKey(candidate)) {
      setState(() {
        _candidate = candidate;
        _stage = _CaptureStage.reserved;
      });
      return;
    }
    // ignore: unawaited_futures
    _commit(candidate);
  }

  String _actionLabel(ShortcutAction action) => switch (action) {
        ShortcutAction.togglePlayPause => 'Play / pause',
        ShortcutAction.nextTrack => 'Next track',
        ShortcutAction.previousTrack => 'Previous track',
        ShortcutAction.seekForward => 'Seek forward',
        ShortcutAction.seekBackward => 'Seek backward',
        ShortcutAction.volumeUp => 'Volume up',
        ShortcutAction.volumeDown => 'Volume down',
        ShortcutAction.toggleMute => 'Mute / unmute',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Remap "${_actionLabel(widget.action)}"'),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: SizedBox(
          width: double.maxFinite,
          child: switch (_stage) {
            _CaptureStage.listening =>
              const Text('Press a key…'),
            _CaptureStage.conflict => Text(
                'Also used for "${_actionLabel(_conflictingAction!)}". '
                'Swap them?',
              ),
            _CaptureStage.reserved => const Text(
                'This key is normally used to activate a focused button '
                'or field. Using it as a shortcut may cause conflicts. '
                'Save anyway?',
              ),
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (_stage != _CaptureStage.listening)
          FilledButton(
            onPressed: () => _commit(_candidate!),
            child: Text(_stage == _CaptureStage.conflict ? 'Swap' : 'Save'),
          ),
      ],
    );
  }
}
