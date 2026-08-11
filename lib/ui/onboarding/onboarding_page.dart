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
          onEnter: OmnisPermissions.ensureCorePermissions,
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: OmnisSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                      ],
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
