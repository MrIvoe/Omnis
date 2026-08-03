import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }
enum AppThemePreset { classic, midnight, aurora, sunset }
enum ButtonLayout { standard, compact, minimal }
enum LibrarySource { wholePhone, dedicatedFolder, none }
enum GestureMode { swipe, taps, none }

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _themeModeKey = 'app_theme_mode';
  static const _themePresetKey = 'app_theme_preset';
  static const _accentColorKey = 'app_accent_color';
  static const _albumArtScaleKey = 'app_album_art_scale';
  static const _showAlbumArtKey = 'app_show_album_art';
  static const _showLyricsKey = 'app_show_lyrics';
  static const _karaokeModeKey = 'app_karaoke_mode';
  static const _buttonLayoutKey = 'app_button_layout';
  static const _gestureModeKey = 'app_gesture_mode';
  static const _swipeGesturesKey = 'app_swipe_gestures';
  static const _librarySourceKey = 'app_library_source';
  static const _selectedFolderPathKey = 'app_selected_folder_path';
  static const _useWholePhoneKey = 'app_use_whole_phone';

  SharedPreferences? _prefs;
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    _initialized = true;
    notifyListeners();
  }

  ThemeMode get themeMode {
    final value = _prefs?.getString(_themeModeKey) ?? 'system';
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  set themeMode(ThemeMode mode) {
    _ensurePrefs();
    _prefs!.setString(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    notifyListeners();
  }

  AppThemePreset get themePreset {
    final value = _prefs?.getString(_themePresetKey) ?? 'classic';
    return switch (value) {
      'midnight' => AppThemePreset.midnight,
      'aurora' => AppThemePreset.aurora,
      'sunset' => AppThemePreset.sunset,
      _ => AppThemePreset.classic,
    };
  }

  set themePreset(AppThemePreset preset) {
    _ensurePrefs();
    _prefs!.setString(_themePresetKey, switch (preset) {
      AppThemePreset.midnight => 'midnight',
      AppThemePreset.aurora => 'aurora',
      AppThemePreset.sunset => 'sunset',
      AppThemePreset.classic => 'classic',
    });
    notifyListeners();
  }

  Color get accentColor {
    final value = _prefs?.getInt(_accentColorKey) ?? Colors.deepPurple.value;
    return Color(value);
  }

  set accentColor(Color color) {
    _ensurePrefs();
    _prefs!.setInt(_accentColorKey, color.value);
    notifyListeners();
  }

  double get albumArtScale {
    return _prefs?.getDouble(_albumArtScaleKey) ?? 1.0;
  }

  set albumArtScale(double scale) {
    _ensurePrefs();
    _prefs!.setDouble(_albumArtScaleKey, scale.clamp(0.7, 1.4));
    notifyListeners();
  }

  bool get showAlbumArt {
    return _prefs?.getBool(_showAlbumArtKey) ?? true;
  }

  set showAlbumArt(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_showAlbumArtKey, value);
    notifyListeners();
  }

  bool get showLyrics {
    return _prefs?.getBool(_showLyricsKey) ?? false;
  }

  set showLyrics(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_showLyricsKey, value);
    notifyListeners();
  }

  bool get karaokeMode {
    return _prefs?.getBool(_karaokeModeKey) ?? false;
  }

  set karaokeMode(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_karaokeModeKey, value);
    notifyListeners();
  }

  ButtonLayout get buttonLayout {
    final value = _prefs?.getString(_buttonLayoutKey) ?? 'standard';
    return switch (value) {
      'compact' => ButtonLayout.compact,
      'minimal' => ButtonLayout.minimal,
      _ => ButtonLayout.standard,
    };
  }

  set buttonLayout(ButtonLayout layout) {
    _ensurePrefs();
    _prefs!.setString(_buttonLayoutKey, switch (layout) {
      ButtonLayout.compact => 'compact',
      ButtonLayout.minimal => 'minimal',
      ButtonLayout.standard => 'standard',
    });
    notifyListeners();
  }

  GestureMode get gestureMode {
    final value = _prefs?.getString(_gestureModeKey) ?? 'swipe';
    return switch (value) {
      'taps' => GestureMode.taps,
      'none' => GestureMode.none,
      _ => GestureMode.swipe,
    };
  }

  set gestureMode(GestureMode mode) {
    _ensurePrefs();
    _prefs!.setString(_gestureModeKey, switch (mode) {
      GestureMode.taps => 'taps',
      GestureMode.none => 'none',
      GestureMode.swipe => 'swipe',
    });
    notifyListeners();
  }

  bool get allowSwipeGestures => _prefs?.getBool(_swipeGesturesKey) ?? true;

  set allowSwipeGestures(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_swipeGesturesKey, value);
    notifyListeners();
  }

  LibrarySource get librarySource {
    final value = _prefs?.getString(_librarySourceKey) ?? 'dedicatedFolder';
    return switch (value) {
      'wholePhone' => LibrarySource.wholePhone,
      'none' => LibrarySource.none,
      _ => LibrarySource.dedicatedFolder,
    };
  }

  set librarySource(LibrarySource source) {
    _ensurePrefs();
    _prefs!.setString(_librarySourceKey, switch (source) {
      LibrarySource.wholePhone => 'wholePhone',
      LibrarySource.none => 'none',
      LibrarySource.dedicatedFolder => 'dedicatedFolder',
    });
    notifyListeners();
  }

  String? get selectedFolderPath => _prefs?.getString(_selectedFolderPathKey);

  set selectedFolderPath(String? path) {
    _ensurePrefs();
    if (path == null) {
      _prefs!.remove(_selectedFolderPathKey);
    } else {
      _prefs!.setString(_selectedFolderPathKey, path);
    }
    notifyListeners();
  }

  bool get useWholePhone => _prefs?.getBool(_useWholePhoneKey) ?? false;

  set useWholePhone(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_useWholePhoneKey, value);
    notifyListeners();
  }

  ThemeData themeData(Brightness brightness) {
    final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final colorScheme = ColorScheme.fromSeed(seedColor: accentColor, brightness: brightness);
    final isDark = brightness == Brightness.dark;

    final surfaceColor = isDark ? const Color(0xFF101218) : const Color(0xFFF7F7FB);
    final elevatedColor = isDark ? const Color(0xFF171A22) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A3040) : const Color(0xFFE7EAF5);

    final presetColors = switch (themePreset) {
      AppThemePreset.midnight => (primary: const Color(0xFF7C93FF), secondary: const Color(0xFF5DE2FF)),
      AppThemePreset.aurora => (primary: const Color(0xFF26C281), secondary: const Color(0xFF6D8CFF)),
      AppThemePreset.sunset => (primary: const Color(0xFFFF8A4C), secondary: const Color(0xFFFF5F7D)),
      AppThemePreset.classic => (primary: accentColor, secondary: accentColor.withOpacity(0.7)),
    };

    final themedScheme = ColorScheme.fromSeed(
      seedColor: presetColors.primary,
      brightness: brightness,
      secondary: presetColors.secondary,
    );

    return base.copyWith(
      colorScheme: themedScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: surfaceColor,
      cardColor: elevatedColor,
      cardTheme: CardTheme(
        color: elevatedColor,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderColor)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: themedScheme.onSurface,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: elevatedColor,
        indicatorColor: themedScheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: themedScheme.onSurface)),
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: themedScheme.onSurface)),
      ),
      dividerColor: borderColor,
      textTheme: base.textTheme.apply(bodyColor: themedScheme.onSurface, displayColor: themedScheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderSide: BorderSide(color: borderColor))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: themedScheme.primary, foregroundColor: themedScheme.onPrimary)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(side: BorderSide(color: themedScheme.primary.withOpacity(0.3))))
    );
  }

  void _ensurePrefs() {
    if (_prefs == null) {
      throw StateError('AppSettings has not been initialized yet.');
    }
  }
}
