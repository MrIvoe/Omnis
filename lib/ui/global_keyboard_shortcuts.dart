import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';
import 'package:omnis/core/mute_toggle.dart';
import 'package:omnis/core/platform_capabilities.dart';

/// App-wide playback keyboard shortcuts (§45 UI spec's "Keyboard"
/// settings category — previously a genuine 0%, "no `Shortcuts`/
/// `FocusTraversalGroup`/`CallbackShortcuts` usage found anywhere").
///
/// Wraps `HomePage`'s `Scaffold` (all six tabs share one `IndexedStack`
/// under it, so this covers every tab without per-page wiring), not
/// `MaterialApp` itself — the real [AudioEngine] instance doesn't exist
/// until `MainCore` finishes initializing, and `HomePage` is exactly
/// where that instance first becomes available (`core.audioEngine`),
/// unlike `main.dart`'s `OmnisApp`, which renders before the core is
/// necessarily ready.
///
/// Three real Flutter key-handling subtleties this implementation had to
/// account for, found by actually running key-event tests rather than
/// assumed from the API surface:
///
///  1. `CallbackShortcuts` (and `Shortcuts`) deliberately never requests
///     focus itself (`canRequestFocus: false`) — it only ever fires as
///     part of the ancestor chain walked from whatever node currently
///     holds keyboard focus. With nothing else in a tab ever requesting
///     focus, `primaryFocus` settles on the current route's own generic
///     `FocusScopeNode` by default, but that scope sits *above* this
///     widget in the tree, not below it — key-event dispatch only walks
///     outward from the focused node through its ancestors, so a focus
///     holder that isn't a descendant of `CallbackShortcuts` never
///     reaches it at all, and these bindings would silently never fire.
///  2. Fixed with a fallback anchor `FocusNode` this widget claims in a
///     post-frame callback deferred one extra frame past its own first
///     one — necessary because a real descendant `autofocus: true`
///     widget (a dialog's `TextField`) resolves its own claim the exact
///     same way, via a post-frame callback registered during its own
///     `initState`; since an ancestor's `initState` always runs before a
///     descendant's, claiming in the *first* post-frame callback would
///     make this anchor win a race it should lose. Only claims when
///     `primaryFocus` is still `null` or a bare `FocusScopeNode` once its
///     deferred callback runs — i.e. nothing more specific claimed it —
///     the same "never land with nothing focused at all" concern
///     `TvModeLayout` already documents for D-pad users, solved here for
///     keyboard users without stealing a legitimate claim (verified via
///     a real nested-autofocus race test, not assumed from the API).
///  3. Ordinary character input — including Space — is **not** reliably
///     marked "handled" by a focused `TextField`'s own key handling the
///     way arrow-key cursor movement or Enter-to-submit are; text
///     composition on most platforms goes through a separate IME/text-
///     input channel the `Shortcuts`/`Actions` handled/ignored bubbling
///     model doesn't see. Left unguarded, typing a space while searching
///     the Library would insert the character *and* toggle play/pause.
///     Fixed with an explicit `_typingInTextField` check ahead of every
///     binding, rather than relying on propagation to stop it.
class GlobalKeyboardShortcuts extends StatefulWidget {
  final AudioEngine engine;
  final Widget child;

  const GlobalKeyboardShortcuts({
    super.key,
    required this.engine,
    required this.child,
  });

  @override
  State<GlobalKeyboardShortcuts> createState() =>
      _GlobalKeyboardShortcutsState();
}

class _GlobalKeyboardShortcutsState extends State<GlobalKeyboardShortcuts> {
  static const Duration _seekStep = Duration(seconds: 10);
  static const double _volumeStep = 0.05;

  final _anchorFocusNode =
      FocusNode(debugLabel: 'GlobalKeyboardShortcutsAnchor');

  /// Remembered by [toggleMute] across presses — see that function's own
  /// doc for why this is nullable state rather than a plain boolean.
  double? _volumeBeforeMute;

  @override
  void initState() {
    super.initState();
    // A real descendant `autofocus: true` widget (e.g. a dialog's
    // `TextField`) resolves its own claim the same way this anchor
    // does — via a post-frame callback, not synchronously during build.
    // Registering ours during `initState` means it would otherwise be
    // *first* in that callback queue (an ancestor's `initState` always
    // runs before a descendant's), winning a race it should lose.
    // Deferring one additional frame lets any such claim from this
    // widget's own first frame resolve and settle before this one ever
    // checks — verified empirically, not assumed, via a real
    // nested-autofocus test.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _claimIfUnclaimed());
    });
  }

  /// Only ever claims focus when nothing more specific already has —
  /// see this class's doc comment, point 2.
  void _claimIfUnclaimed() {
    if (!mounted) return;
    final current = FocusManager.instance.primaryFocus;
    if (current == null || current is FocusScopeNode) {
      _anchorFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _anchorFocusNode.dispose();
    super.dispose();
  }

  bool get _enabled => AppSettings.instance.keyboardShortcutsEnabled;

  /// Whether the currently focused widget is a text-editing field —
  /// checked fresh on every key press (not cached), since focus can move
  /// between one shortcut press and the next.
  bool get _typingInTextField {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    // The focused `FocusNode` belongs to a `Focus` widget `EditableText`
    // builds internally, below itself in the tree — so `EditableText` is
    // an ancestor of the focused context, not the focused widget itself.
    return focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _togglePlayPause() {
    if (!_enabled || _typingInTextField) return;
    if (widget.engine.isPlaying) {
      widget.engine.pause();
    } else {
      widget.engine.play();
    }
  }

  void _next() {
    if (!_enabled || _typingInTextField) return;
    widget.engine.next();
  }

  void _previous() {
    if (!_enabled || _typingInTextField) return;
    widget.engine.previous();
  }

  void _seekBy(Duration delta) {
    if (!_enabled || _typingInTextField) return;
    final target = widget.engine.position + delta;
    widget.engine.seek(target < Duration.zero ? Duration.zero : target);
  }

  void _adjustVolume(double delta) {
    if (!_enabled || _typingInTextField) return;
    final target = (widget.engine.volume + delta).clamp(0.0, 1.0);
    widget.engine.setVolume(target);
  }

  void _toggleMute() {
    if (!_enabled || _typingInTextField) return;
    final result = toggleMute(widget.engine.volume, _volumeBeforeMute);
    _volumeBeforeMute = result.volumeToRemember;
    widget.engine.setVolume(result.newVolume);
  }

  /// Hardware media-key play/pause — dispatched from the bindings map's
  /// unconditional `mediaPlayPause` entry, **not** [_togglePlayPause]
  /// above, deliberately. [_togglePlayPause] guards on [_enabled], which
  /// tracks `AppSettings.instance.keyboardShortcutsEnabled` — the exact
  /// setting whose only UI control (`keyboard_settings_page.dart`'s
  /// switch) is hidden on touch-primary platforms as of the same change
  /// that made this binding unconditional (see `settings_page.dart`).
  /// Reusing [_togglePlayPause] here would have made the map entry
  /// "unconditional" in name only: any user who had already flipped that
  /// switch off *before* it was hidden — a real, already-persisted case,
  /// since the Keyboard category was reachable on every platform,
  /// including Android/iOS, before this task — would permanently lose
  /// real Bluetooth/wired-headset button handling with no way back in,
  /// since there's no settings-reset feature and clearing app data would
  /// also wipe their library. A hardware media-key press is an OS/device
  /// signal a user can't "remap" or type accidentally, so it isn't
  /// gated by the same setting a keyboard letter/arrow shortcut is.
  ///
  /// Deliberately **does not** check [_typingInTextField] either, unlike
  /// every settings-driven handler above: that guard exists (see this
  /// class's own doc comment, point 3) because ordinary character input —
  /// Space included — isn't reliably marked "handled" by a focused
  /// `TextField`, so an unguarded keyboard shortcut would both insert a
  /// character *and* trigger playback. A hardware media key carries no
  /// character payload and was never going to insert anything into
  /// whatever's focused; suppressing it while a text field happens to be
  /// focused would just make a real headset button silently stop working
  /// the moment the user taps a search box, with no typing conflict to
  /// justify it.
  void _mediaPlayPause() {
    if (widget.engine.isPlaying) {
      widget.engine.pause();
    } else {
      widget.engine.play();
    }
  }

  /// Hardware media-key next-track — see [_mediaPlayPause]'s doc comment
  /// for why this bypasses both [_enabled] and [_typingInTextField]
  /// rather than reusing [_next].
  void _mediaNext() => widget.engine.next();

  /// Hardware media-key previous-track — see [_mediaPlayPause]'s doc
  /// comment for why this bypasses both [_enabled] and
  /// [_typingInTextField] rather than reusing [_previous].
  void _mediaPrevious() => widget.engine.previous();

  /// Dispatches to this class's own private handlers — item 48's
  /// per-shortcut remapping only changes *which key* triggers an
  /// action, never what the action itself does.
  VoidCallback _callbackFor(ShortcutAction action) => switch (action) {
        ShortcutAction.togglePlayPause => _togglePlayPause,
        ShortcutAction.nextTrack => _next,
        ShortcutAction.previousTrack => _previous,
        ShortcutAction.seekForward => () => _seekBy(_seekStep),
        ShortcutAction.seekBackward => () => _seekBy(-_seekStep),
        ShortcutAction.volumeUp => () => _adjustVolume(_volumeStep),
        ShortcutAction.volumeDown => () => _adjustVolume(-_volumeStep),
        ShortcutAction.toggleMute => _toggleMute,
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // A remap made while this widget is already live (the Keyboard
      // settings page can be reached without leaving HomePage's own
      // widget subtree) must take effect on the very next keypress, not
      // require an app restart — AppSettings is already a
      // ChangeNotifier, so this is the same "listen and rebuild" shape
      // every other live-settings-driven widget in this app already
      // uses.
      listenable: AppSettings.instance,
      builder: (context, _) {
        final bindings = <ShortcutActivator, VoidCallback>{
          // Settings-driven keyboard bindings assume a hardware keyboard is
          // normally attached — not true on touch-primary platforms, where
          // the Keyboard settings page itself is hidden (see
          // `settings_page.dart`). Registering these there anyway would let
          // a Bluetooth keyboard someone happens to pair trigger bindings
          // no visible setting exposes or explains.
          if (!PlatformCapabilities.isTouchPrimary)
            for (final entry in AppSettings.instance.shortcutBindings.entries)
              entry.value.toActivator(): _callbackFor(entry.key),
          // Hardware media-key signals (a paired Bluetooth headset's or a
          // wired headset's buttons — real on Android) dispatch to
          // dedicated `_mediaXxx` handlers, not the settings-driven
          // `_togglePlayPause`/`_next`/`_previous` used above: those gate
          // on `_enabled`, the same `keyboardShortcutsEnabled` setting
          // whose only UI control is hidden on touch-primary platforms.
          // Routing media keys through the settings-gated handlers would
          // have made this "unconditional" in the map only — a user who'd
          // already disabled that setting before it was hidden would have
          // no way back in to restore hardware media-key handling at all.
          // See `_mediaPlayPause`'s own doc comment for the full reasoning
          // (including why it also skips the `_typingInTextField` guard).
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
              _mediaPlayPause,
          const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
              _mediaNext,
          const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
              _mediaPrevious,
        };
        return CallbackShortcuts(
          bindings: bindings,
          child: Focus(
            focusNode: _anchorFocusNode,
            skipTraversal: true,
            child: widget.child,
          ),
        );
      },
    );
  }
}
