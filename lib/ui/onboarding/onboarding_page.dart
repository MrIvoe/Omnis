import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/permissions.dart';
import 'package:omnis/l10n/generated/app_localizations.dart';
import 'package:omnis/ui/home_page.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';
import 'package:omnis/ui/theme/omnis_spacing.dart';

/// One onboarding screen's content — an icon, a title, and a body, with
/// [onEnter] as an optional side effect to run the moment the screen
/// becomes active (used by the permissions screen to fire the real
/// notification-permission request right after explaining it, not
/// before).
class _OnboardingScreen {
  final IconData icon;
  final String title;
  final String body;
  final Future<void> Function()? onEnter;

  const _OnboardingScreen({
    required this.icon,
    required this.title,
    required this.body,
    this.onEnter,
  });
}

/// First-run flow, shown once (gated by [AppSettings.hasCompletedOnboarding])
/// before [HomePage]. Covers what makes Omnis different (the plugin
/// system — not obvious from a first glance the way "here's an
/// equalizer" is), gives real context for the permission prompts the
/// user is about to see rather than letting the bare OS dialogs speak
/// for themselves, and points at Settings search as the answer to
/// "where do I find X" now that it exists.
class OnboardingPage extends StatefulWidget {
  /// Builds the screen navigated to once onboarding finishes. Defaults to
  /// the real [HomePage]; overridable so a test can substitute a
  /// lightweight placeholder instead of standing up the entire app core
  /// (audio engine, plugin manager, etc.) [HomePage] needs.
  final WidgetBuilder homeBuilder;

  const OnboardingPage({super.key, this.homeBuilder = _defaultHomeBuilder});

  static Widget _defaultHomeBuilder(BuildContext context) => const HomePage();

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  int _index = 0;
  final Set<int> _entered = {};

  /// The plugin ids [_enabledUpfrontPluginIds] reports as enabled, once
  /// [_requestUpfrontPermissions] has run — `null` until then (nothing
  /// plugin-specific to show yet). Drives which conditional lines the
  /// permissions screen renders below its main body text; see
  /// [_pluginPermissionLines].
  Set<String>? _enabledPluginIds;

  List<_OnboardingScreen> _screens(AppLocalizations l10n) => [
        _OnboardingScreen(
          icon: Icons.extension_outlined,
          title: l10n.onboardingWelcomeTitle,
          body: l10n.onboardingWelcomeBody,
        ),
        _OnboardingScreen(
          icon: Icons.shield_outlined,
          title: l10n.onboardingPermissionsTitle,
          body: l10n.onboardingPermissionsBody,
          onEnter: _requestUpfrontPermissions,
        ),
        _OnboardingScreen(
          icon: Icons.explore_outlined,
          title: l10n.onboardingTourTitle,
          body: l10n.onboardingTourBody,
        ),
        _OnboardingScreen(
          icon: Icons.check_circle_outline,
          title: l10n.onboardingReadyTitle,
          body: l10n.onboardingReadyBody,
        ),
      ];

  /// Which of [OmnisPermissions.ensureUpfrontPermissions]'s bundled-plugin
  /// ids are enabled, without needing a live `PluginManager`.
  ///
  /// This screen is built and shown before `HomePage`/`MainCore` in the
  /// normal cold-start flow (see `main.dart`'s `home:` chooser), so there
  /// is no live `PluginManager` to read `.enabled` off of yet. The obvious
  /// fix — call `ensureCoreReady()` here first, since it's idempotent and
  /// `HomePage` calls it moments later anyway — turns out not to work:
  /// confirmed directly while building this (instrumented with debug
  /// prints), the awaited `ensureCoreReady()` call never resolves inside a
  /// `flutter test` `testWidgets()` pump cycle on this Windows setup. It's
  /// the same failure mode `declarative_layout_test.dart`'s own doc
  /// comment describes for a bare `dart:io` read awaited directly inside a
  /// `testWidgets()` callback: something about `TestWidgetsFlutterBinding`'s
  /// zone/scheduler and `dart:io`'s event loop dispatch on Windows, not
  /// specific to this file. `MainCore.initialize()` (which
  /// `ensureCoreReady()` awaits) reaches for several `dart:io`-backed
  /// stores, so it trips the same thing.
  ///
  /// Reading `AppSettings` directly instead sidesteps that entirely, and
  /// is *not* a hardcoded guess at which plugins ship enabled by default:
  /// `PluginManager.register()`'s own `ManagedPlugin.enabled` is computed
  /// as exactly `!AppSettings.instance.isPluginDisabled(plugin.id)` (see
  /// `plugin_manager.dart`), with nothing else factored in at registration
  /// time — so checking the same four ids
  /// [OmnisPermissions.ensureUpfrontPermissions] itself checks against
  /// `AppSettings.instance.isPluginDisabled` directly reproduces exactly
  /// what a live `PluginManager` would report, from the same underlying
  /// persisted state, without the detour through one.
  Set<String> _enabledUpfrontPluginIds() {
    const relevantIds = [
      'tag_editor',
      'bluetooth_playback',
      'driving_mode',
      'visualizer',
    ];
    return {
      for (final id in relevantIds)
        if (!AppSettings.instance.isPluginDisabled(id)) id,
    };
  }

  /// The permissions screen's [_OnboardingScreen.onEnter]. Replaces the
  /// old bare `OmnisPermissions.ensureCorePermissions` call with the
  /// batched entry point: core permissions always, plus whatever
  /// already-enabled plugins need, all in one pass.
  Future<void> _requestUpfrontPermissions() async {
    final enabledPluginIds = _enabledUpfrontPluginIds();
    if (mounted) setState(() => _enabledPluginIds = enabledPluginIds);
    await OmnisPermissions.ensureUpfrontPermissions(enabledPluginIds);
  }

  /// One line per applicable plugin permission, built in Dart directly
  /// rather than forced into the `.arb` string-resource format — this
  /// app's l10n system (`app_en.arb`) has no existing placeholder-based
  /// or dynamically-sized-list precedent, and which lines apply isn't
  /// known until [_requestUpfrontPermissions] resolves. Each individual
  /// line's *text* is still a normal localizable string; only the
  /// decision of *which* lines to show is dynamic.
  List<Widget> _pluginPermissionLines(AppLocalizations l10n) {
    final enabled = _enabledPluginIds;
    if (enabled == null) return const [];
    final lines = <MapEntry<IconData, String>>[
      if (enabled.contains('tag_editor'))
        MapEntry(Icons.folder_open, l10n.onboardingPermissionsStorageLine),
      if (enabled.contains('bluetooth_playback'))
        MapEntry(
            Icons.bluetooth, l10n.onboardingPermissionsBluetoothLine),
      if (enabled.contains('driving_mode'))
        MapEntry(
            Icons.location_on_outlined, l10n.onboardingPermissionsLocationLine),
      if (enabled.contains('visualizer'))
        MapEntry(Icons.mic_none, l10n.onboardingPermissionsMicrophoneLine),
    ];
    if (lines.isEmpty) return const [];
    return [
      OmnisSpacing.gapMd,
      Text(
        l10n.onboardingPermissionsPluginIntro,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      OmnisSpacing.gapSm,
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: OmnisSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(line.key,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              OmnisSpacing.gapSm,
              Flexible(
                child: Text(line.value, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Runs a screen's [_OnboardingScreen.onEnter] side effect exactly
  /// once, the first time it's actually shown — not on every rebuild,
  /// and not for a screen the user never reaches (e.g. by finishing
  /// early some other way in a future revision of this flow).
  void _maybeEnter(int index, List<_OnboardingScreen> screens) {
    if (_entered.contains(index)) return;
    _entered.add(index);
    final onEnter = screens[index].onEnter;
    if (onEnter != null) onEnter();
  }

  Future<void> _goToPage(int page) async {
    final duration = OmnisMotion.durationFor(OmnisMotion.medium);
    if (duration == Duration.zero) {
      _pageController.jumpToPage(page);
    } else {
      await _pageController.animateToPage(page,
          duration: duration, curve: OmnisMotion.standardCurve);
    }
  }

  void _finish() {
    AppSettings.instance.hasCompletedOnboarding = true;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: widget.homeBuilder));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final screens = _screens(l10n);
    final lastPage = screens.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(
                    right: OmnisSpacing.sm, top: OmnisSpacing.xs),
                // Opacity/IgnorePointer rather than swapping the widget
                // out entirely, so the header keeps the same height on
                // every screen — no content jump when Skip disappears on
                // the last one.
                child: Opacity(
                  opacity: _index == lastPage ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: _index == lastPage,
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(l10n.onboardingSkip),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: screens.length,
                onPageChanged: (index) {
                  setState(() => _index = index);
                  _maybeEnter(index, screens);
                },
                itemBuilder: (context, index) {
                  if (index == 0) _maybeEnter(0, screens);
                  final screen = screens[index];
                  // LayoutBuilder + a min-height ConstrainedBox rather than
                  // a bare centered Column: the permissions screen's
                  // conditional plugin lines (_pluginPermissionLines) make
                  // its content taller than the other three screens', and
                  // tall enough on a short viewport to overflow a fixed,
                  // non-scrolling Column. Every screen still centers
                  // vertically when its content fits (the common case);
                  // only a screen whose content doesn't fit scrolls instead
                  // of overflowing.
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: OmnisSpacing.xl),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(screen.icon,
                                  size: 96, color: theme.colorScheme.primary),
                              OmnisSpacing.gapXl,
                              Text(
                                screen.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              OmnisSpacing.gapMd,
                              Text(
                                screen.body,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge,
                              ),
                              if (index == 1) ..._pluginPermissionLines(l10n),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: OmnisSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < screens.length; i++)
                    Container(
                      margin:
                          const EdgeInsets.symmetric(horizontal: OmnisSpacing.xs),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  OmnisSpacing.lg, 0, OmnisSpacing.lg, OmnisSpacing.lg),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: () => _goToPage(_index - 1),
                      child: Text(l10n.onboardingBack),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _index == lastPage
                        ? _finish
                        : () => _goToPage(_index + 1),
                    child: Text(_index == lastPage
                        ? l10n.onboardingGetStarted
                        : (_index == 1
                            ? l10n.onboardingPermissionsContinue
                            : l10n.onboardingNext)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
