import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en')
  ];

  /// The application title shown in the OS task switcher / window title.
  ///
  /// In en, this message translates to:
  /// **'Omnis Music Engine'**
  String get appTitle;

  /// Button that dismisses the onboarding flow immediately, on any screen but the last.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Advances to the next onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Returns to the previous onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Final button on the last onboarding screen, which completes onboarding and opens the app.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// Title of the first onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Omnis'**
  String get onboardingWelcomeTitle;

  /// Body text explaining Omnis's plugin system on the first onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Most music players are one fixed app. Omnis is built around a plugin system instead — nearly everything beyond the core player (lyrics, equalizer, visualizer, importers, and more) is a swappable plugin. Turn off what you don\'t need, and add capabilities the app didn\'t originally ship with.'**
  String get onboardingWelcomeBody;

  /// Title of the permissions-context onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'A couple of permissions'**
  String get onboardingPermissionsTitle;

  /// Body text explaining why media access and notification permission are needed.
  ///
  /// In en, this message translates to:
  /// **'Omnis needs access to your device\'s media library to find and play your music — nothing leaves your device. It also asks for notification access so playback controls show up on your lock screen and notification shade. You\'ll see the real system prompts as you go; this is why they\'re there.'**
  String get onboardingPermissionsBody;

  /// Button on the permissions screen — advances and, along the way, triggers the real notification-permission request.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingPermissionsContinue;

  /// Introduces the conditional bullet list of plugin-specific permissions below the main permissions body text. Only shown when at least one applies.
  ///
  /// In en, this message translates to:
  /// **'Based on what\'s enabled by default, it\'ll also ask for:'**
  String get onboardingPermissionsPluginIntro;

  /// Bullet line shown when the tag editor plugin is enabled by default.
  ///
  /// In en, this message translates to:
  /// **'Broad file access, so the tag editor can save edits directly to your files.'**
  String get onboardingPermissionsStorageLine;

  /// Bullet line shown when the Bluetooth playback plugin is enabled by default.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth access, so Bluetooth playback can detect your connected audio device.'**
  String get onboardingPermissionsBluetoothLine;

  /// Bullet line shown when the driving mode plugin is enabled by default.
  ///
  /// In en, this message translates to:
  /// **'Location access, so driving mode can tell when you\'re in the car.'**
  String get onboardingPermissionsLocationLine;

  /// Bullet line shown when the visualizer plugin is enabled by default.
  ///
  /// In en, this message translates to:
  /// **'Microphone access, only to satisfy the OS API the visualizer reads audio levels through — nothing is recorded.'**
  String get onboardingPermissionsMicrophoneLine;

  /// Title of the app-tour onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Find your way around'**
  String get onboardingTourTitle;

  /// Body text pointing out the bottom navigation and Settings search.
  ///
  /// In en, this message translates to:
  /// **'Home, Library, Playlist, Moods, and Settings sit along the bottom. If you\'re ever hunting for a specific setting, open Settings and just start typing — search jumps straight to the exact control.'**
  String get onboardingTourBody;

  /// Title of the final onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get onboardingReadyTitle;

  /// Body text on the final onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'That\'s everything. Add your music and start listening.'**
  String get onboardingReadyBody;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
