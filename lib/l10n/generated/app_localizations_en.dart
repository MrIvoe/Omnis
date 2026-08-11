import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Omnis Music Engine';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingWelcomeTitle => 'Welcome to Omnis';

  @override
  String get onboardingWelcomeBody => 'Most music players are one fixed app. Omnis is built around a plugin system instead — nearly everything beyond the core player (lyrics, equalizer, visualizer, importers, and more) is a swappable plugin. Turn off what you don\'t need, and add capabilities the app didn\'t originally ship with.';

  @override
  String get onboardingPermissionsTitle => 'A couple of permissions';

  @override
  String get onboardingPermissionsBody => 'Omnis needs access to your device\'s media library to find and play your music — nothing leaves your device. It also asks for notification access so playback controls show up on your lock screen and notification shade. You\'ll see the real system prompts as you go; this is why they\'re there.';

  @override
  String get onboardingPermissionsContinue => 'Continue';

  @override
  String get onboardingTourTitle => 'Find your way around';

  @override
  String get onboardingTourBody => 'Home, Library, Playlist, Moods, and Settings sit along the bottom. If you\'re ever hunting for a specific setting, open Settings and just start typing — search jumps straight to the exact control.';

  @override
  String get onboardingReadyTitle => 'You\'re all set';

  @override
  String get onboardingReadyBody => 'That\'s everything. Add your music and start listening.';
}
