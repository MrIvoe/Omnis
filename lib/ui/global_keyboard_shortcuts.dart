import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';

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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            _togglePlayPause,
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): _next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): _previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            _previous,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekBy(_seekStep),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekBy(-_seekStep),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _adjustVolume(_volumeStep),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _adjustVolume(-_volumeStep),
      },
      child: Focus(
        focusNode: _anchorFocusNode,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}
