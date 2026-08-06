import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark }

enum AppThemePreset { classic, midnight, aurora, sunset }

enum ButtonLayout { standard, compact, minimal }

enum LibrarySource { wholePhone, dedicatedFolder, none }

enum GestureMode { swipe, taps, none }

enum RepeatMode { off, all, one }

enum LibraryDisplayMode { list, grid }

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
  static const _volumeKey = 'app_playback_volume';
  static const _speedKey = 'app_playback_speed';
  static const _pitchKey = 'app_playback_pitch';
  static const _skipSilenceEnabledKey = 'app_skip_silence_enabled';
  static const _crossfadeSecondsKey = 'app_crossfade_seconds';
  static const _gaplessEnabledKey = 'app_gapless_enabled';
  static const _disabledPluginsKey = 'app_disabled_plugins';
  static const _eqVirtualBandsKey = 'app_eq_virtual_bands';
  static const _eqHardwareBandsKey = 'app_eq_hardware_bands';
  static const _lyricsKey = 'app_lyrics_by_track';
  static const _playHistoryKey = 'app_play_history';
  static const _playerLayoutIdKey = 'app_player_layout_id';
  static const _autoLandscapeLayoutKey = 'app_auto_landscape_layout';
  static const _carModeControlsOnRightKey = 'app_car_mode_controls_on_right';
  static const _autoTaggedTrackIdsKey = 'app_auto_tagged_track_ids';
  static const _favoriteTrackIdsKey = 'app_favorite_track_ids';
  static const _bottomNavAutoHideKey = 'app_bottom_nav_auto_hide';
  static const _songsViewModeKey = 'app_songs_view_mode';
  static const _songsGridColumnsKey = 'app_songs_grid_columns';
  static const _albumsViewModeKey = 'app_albums_view_mode';
  static const _albumsGridColumnsKey = 'app_albums_grid_columns';
  static const _genresViewModeKey = 'app_genres_view_mode';
  static const _genresGridColumnsKey = 'app_genres_grid_columns';
  static const _shortTrackThresholdSecondsKey =
      'app_short_track_threshold_seconds';

  SharedPreferences? _prefs;
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> initialize() async {
    // Assign rather than `??=`: re-initializing must pick up the current
    // SharedPreferences store. With `??=` the very first store was cached
    // forever, so a test that swapped in fresh mock values kept reading the
    // stale one and state leaked between tests.
    _prefs = await SharedPreferences.getInstance();
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
    _prefs!.setString(
        _themeModeKey,
        switch (mode) {
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
    _prefs!.setString(
        _themePresetKey,
        switch (preset) {
          AppThemePreset.midnight => 'midnight',
          AppThemePreset.aurora => 'aurora',
          AppThemePreset.sunset => 'sunset',
          AppThemePreset.classic => 'classic',
        });
    notifyListeners();
  }

  /// Packs a [Color] into a storable ARGB int.
  ///
  /// `Color.value` is deprecated and its replacement `Color.toARGB32()`
  /// only exists from Flutter 3.29 — this project builds on 3.27.4, so the
  /// packing is done from the component accessors the deprecation points
  /// at. One helper keeps that version detail in a single place.
  static int _packArgb(Color color) =>
      ((color.a * 255).round() & 0xff) << 24 |
      ((color.r * 255).round() & 0xff) << 16 |
      ((color.g * 255).round() & 0xff) << 8 |
      ((color.b * 255).round() & 0xff);

  Color get accentColor {
    final value =
        _prefs?.getInt(_accentColorKey) ?? _packArgb(Colors.deepPurple);
    return Color(value);
  }

  set accentColor(Color color) {
    _ensurePrefs();
    _prefs!.setInt(_accentColorKey, _packArgb(color));
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

  /// Defaults to `true`. The lyrics panel is also where the "edit lyrics"
  /// button lives (`PlayerLyricsPanel`) — when this defaulted to `false`,
  /// a new user had no way to ever discover the lyrics feature exists at
  /// all, since the one control that reveals it was itself hidden behind
  /// it. The empty state ("No lyrics added for this track yet.") is a
  /// harmless, self-explanatory default to show instead.
  bool get showLyrics {
    return _prefs?.getBool(_showLyricsKey) ?? true;
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
    _prefs!.setString(
        _buttonLayoutKey,
        switch (layout) {
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
    _prefs!.setString(
        _gestureModeKey,
        switch (mode) {
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

  /// The id of the selected Now Playing layout (see
  /// `lib/ui/player_layouts/`). Defaults to `'standard'`. An unrecognised
  /// stored id (e.g. from a layout that was since removed) falls back to
  /// standard at the call site, not here — this getter just returns
  /// whatever string is stored.
  String get playerLayoutId =>
      _prefs?.getString(_playerLayoutIdKey) ?? 'standard';

  set playerLayoutId(String value) {
    _ensurePrefs();
    _prefs!.setString(_playerLayoutIdKey, value);
    notifyListeners();
  }

  /// Whether button-based layouts (Standard, Top Controls) should switch to
  /// the Landscape layout while the device is rotated, without changing
  /// the persisted [playerLayoutId] the user actually chose.
  bool get autoLandscapeLayout =>
      _prefs?.getBool(_autoLandscapeLayoutKey) ?? true;

  set autoLandscapeLayout(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_autoLandscapeLayoutKey, value);
    notifyListeners();
  }

  /// Which edge Car Mode's control rail sits on.
  bool get carModeControlsOnRight =>
      _prefs?.getBool(_carModeControlsOnRightKey) ?? true;

  set carModeControlsOnRight(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_carModeControlsOnRightKey, value);
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
    _prefs!.setString(
        _librarySourceKey,
        switch (source) {
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

  /// Master volume (0..1). Previously this only lived as an ephemeral
  /// `State` field in `settings_page.dart` and reset to 1.0 on every app
  /// restart regardless of what the user last set.
  double get volume => _prefs?.getDouble(_volumeKey) ?? 1.0;

  set volume(double value) {
    _ensurePrefs();
    _prefs!.setDouble(_volumeKey, value.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Playback speed multiplier. Same persistence gap as [volume].
  double get playbackSpeed => _prefs?.getDouble(_speedKey) ?? 1.0;

  set playbackSpeed(double value) {
    _ensurePrefs();
    _prefs!.setDouble(_speedKey, value.clamp(0.25, 2.0));
    notifyListeners();
  }

  /// Crossfade duration in seconds (0 = off). Same persistence gap.
  double get crossfadeSeconds => _prefs?.getDouble(_crossfadeSecondsKey) ?? 0.0;

  set crossfadeSeconds(double value) {
    _ensurePrefs();
    _prefs!.setDouble(_crossfadeSecondsKey, value < 0 ? 0.0 : value);
    notifyListeners();
  }

  /// Pitch multiplier, independent of [playbackSpeed] (1.0 = unshifted) —
  /// Poweramp-style separate tempo/pitch controls.
  double get pitch => _prefs?.getDouble(_pitchKey) ?? 1.0;

  set pitch(double value) {
    _ensurePrefs();
    _prefs!.setDouble(_pitchKey, value.clamp(0.5, 2.0));
    notifyListeners();
  }

  /// Skip-silence toggle — shortens silent gaps instead of playing
  /// through them, same feature name/behavior as most podcast players
  /// and Poweramp.
  bool get skipSilenceEnabled =>
      _prefs?.getBool(_skipSilenceEnabledKey) ?? false;

  set skipSilenceEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_skipSilenceEnabledKey, value);
    notifyListeners();
  }

  /// Gapless playback toggle. Same persistence gap.
  bool get gaplessEnabled => _prefs?.getBool(_gaplessEnabledKey) ?? true;

  set gaplessEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_gaplessEnabledKey, value);
    notifyListeners();
  }

  Map<String, double> _decodeBandMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
      );
    } catch (_) {
      // Corrupt preference value — treat as "nothing saved" rather than
      // crashing plugin initialization over a bad string.
      return {};
    }
  }

  Future<void> _persistBandMap(String key, Map<String, double> bands) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(key, jsonEncode(bands));
    notifyListeners();
  }

  /// Persisted virtual (bass/mid/treble) equalizer band gains.
  ///
  /// The equalizer used to reset to flat on every restart — nothing ever
  /// wrote its bands anywhere.
  Map<String, double> get equalizerVirtualBands =>
      _decodeBandMap(_prefs?.getString(_eqVirtualBandsKey));

  Future<void> setEqualizerVirtualBands(Map<String, double> bands) =>
      _persistBandMap(_eqVirtualBandsKey, bands);

  /// Persisted native equalizer band gains, keyed by band index (as a
  /// string, since band layout is device-reported and not fixed).
  Map<String, double> get equalizerHardwareBands =>
      _decodeBandMap(_prefs?.getString(_eqHardwareBandsKey));

  Future<void> setEqualizerHardwareBands(Map<String, double> bands) =>
      _persistBandMap(_eqHardwareBandsKey, bands);

  /// Persisted plain-text lyrics, keyed by track id.
  ///
  /// Previously `LyricsPlugin` only ever held lyrics in memory, so
  /// anything a user typed vanished on the next restart.
  Map<String, String> get storedLyrics {
    final raw = _prefs?.getString(_lyricsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setStoredLyrics(Map<String, String> lyrics) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_lyricsKey, jsonEncode(lyrics));
    notifyListeners();
  }

  /// Persisted play history — a JSON-encoded list of per-play maps
  /// (`trackId`, `title`, `artist`, `playedAtMs`). `ScrobblePlugin` owns
  /// the shape and the cap on how many entries are kept; this is just
  /// storage, the same split every other persisted-collection setting
  /// here uses.
  List<Map<String, dynamic>> get playHistory {
    final raw = _prefs?.getString(_playHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setPlayHistory(List<Map<String, dynamic>> history) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_playHistoryKey, jsonEncode(history));
    notifyListeners();
  }

  /// Ids of tracks the automatic tagger has already processed, so a
  /// repeat "tag whole library" pass skips them instead of re-doing (and
  /// potentially re-fetching/re-guessing) the same work every time.
  /// `TagEditorPlugin.clearAutoTagged` is the "redo this one anyway"
  /// escape hatch.
  Set<String> get autoTaggedTrackIds {
    final raw = _prefs?.getStringList(_autoTaggedTrackIdsKey);
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> setAutoTaggedTrackIds(Set<String> ids) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setStringList(_autoTaggedTrackIdsKey, ids.toList());
    notifyListeners();
  }

  /// Ids of tracks the user has marked a favorite ("Like" in Spotify,
  /// "Top rated" in Musicolet). A plain persisted set — [FavoritesPlugin]
  /// is the thin API surface over this, the same split
  /// `TagEditorPlugin`/`autoTaggedTrackIds` already uses.
  Set<String> get favoriteTrackIds {
    final raw = _prefs?.getStringList(_favoriteTrackIdsKey);
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> setFavoriteTrackIds(Set<String> ids) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setStringList(_favoriteTrackIdsKey, ids.toList());
    notifyListeners();
  }

  /// Whether the bottom navigation bar auto-hides in Car Mode / landscape
  /// (revealed by a swipe-up or the edge handle) rather than always
  /// staying visible and covering more of the screen in those layouts.
  bool get bottomNavAutoHide =>
      _prefs?.getBool(_bottomNavAutoHideKey) ?? true;

  set bottomNavAutoHide(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_bottomNavAutoHideKey, value);
    notifyListeners();
  }

  LibraryDisplayMode _displayMode(String key) {
    return (_prefs?.getString(key) ?? 'list') == 'grid'
        ? LibraryDisplayMode.grid
        : LibraryDisplayMode.list;
  }

  Future<void> _setDisplayMode(String key, LibraryDisplayMode mode) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
        key, mode == LibraryDisplayMode.grid ? 'grid' : 'list');
    notifyListeners();
  }

  int _gridColumns(String key) => (_prefs?.getInt(key) ?? 3).clamp(2, 5);

  Future<void> _setGridColumns(String key, int columns) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setInt(key, columns.clamp(2, 5));
    notifyListeners();
  }

  LibraryDisplayMode get songsViewMode => _displayMode(_songsViewModeKey);
  Future<void> setSongsViewMode(LibraryDisplayMode mode) =>
      _setDisplayMode(_songsViewModeKey, mode);
  int get songsGridColumns => _gridColumns(_songsGridColumnsKey);
  Future<void> setSongsGridColumns(int columns) =>
      _setGridColumns(_songsGridColumnsKey, columns);

  LibraryDisplayMode get albumsViewMode => _displayMode(_albumsViewModeKey);
  Future<void> setAlbumsViewMode(LibraryDisplayMode mode) =>
      _setDisplayMode(_albumsViewModeKey, mode);
  int get albumsGridColumns => _gridColumns(_albumsGridColumnsKey);
  Future<void> setAlbumsGridColumns(int columns) =>
      _setGridColumns(_albumsGridColumnsKey, columns);

  LibraryDisplayMode get genresViewMode => _displayMode(_genresViewModeKey);
  Future<void> setGenresViewMode(LibraryDisplayMode mode) =>
      _setDisplayMode(_genresViewModeKey, mode);
  int get genresGridColumns => _gridColumns(_genresGridColumnsKey);
  Future<void> setGenresGridColumns(int columns) =>
      _setGridColumns(_genresGridColumnsKey, columns);

  /// Tracks at or under this length are flagged by the "short files"
  /// library-cleanup tool as likely not real songs (ad stingers, bumpers,
  /// silence). Adjustable — some libraries genuinely have short
  /// interludes that are real tracks.
  int get shortTrackThresholdSeconds =>
      _prefs?.getInt(_shortTrackThresholdSecondsKey) ?? 30;

  set shortTrackThresholdSeconds(int seconds) {
    _ensurePrefs();
    _prefs!.setInt(_shortTrackThresholdSecondsKey, seconds < 0 ? 0 : seconds);
    notifyListeners();
  }

  /// Ids of plugins the user has switched off.
  ///
  /// Plugin enable/disable used to live only in memory, so every restart
  /// silently switched every plugin back on.
  Set<String> get disabledPlugins =>
      (_prefs?.getStringList(_disabledPluginsKey) ?? const <String>[]).toSet();

  /// Whether [pluginId] was switched off by the user.
  bool isPluginDisabled(String pluginId) =>
      disabledPlugins.contains(pluginId);

  /// Persist a plugin's enabled state.
  ///
  /// Deliberately a no-op when preferences are not loaded (unit tests
  /// construct a bare [PluginManager]) rather than throwing like the
  /// `_ensurePrefs()` setters — losing a preference must never take down
  /// plugin management.
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final disabled = disabledPlugins;
    final changed =
        enabled ? disabled.remove(pluginId) : disabled.add(pluginId);
    if (!changed) return;
    await prefs.setStringList(_disabledPluginsKey, disabled.toList());
    notifyListeners();
  }

  /// Drop any stored state for a plugin that no longer exists.
  Future<void> forgetPluginState(String pluginId) =>
      setPluginEnabled(pluginId, true);

  ThemeData themeData(Brightness brightness) {
    final base =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final isDark = brightness == Brightness.dark;

    final surfaceColor =
        isDark ? const Color(0xFF101218) : const Color(0xFFF7F7FB);
    final elevatedColor = isDark ? const Color(0xFF171A22) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF2A3040) : const Color(0xFFE7EAF5);

    final presetColors = switch (themePreset) {
      AppThemePreset.midnight => (
          primary: const Color(0xFF7C93FF),
          secondary: const Color(0xFF5DE2FF)
        ),
      AppThemePreset.aurora => (
          primary: const Color(0xFF26C281),
          secondary: const Color(0xFF6D8CFF)
        ),
      AppThemePreset.sunset => (
          primary: const Color(0xFFFF8A4C),
          secondary: const Color(0xFFFF5F7D)
        ),
      AppThemePreset.classic => (
          primary: accentColor,
          secondary: accentColor.withValues(alpha: 0.7)
        ),
    };

    final themedScheme = ColorScheme.fromSeed(
      seedColor: presetColors.primary,
      brightness: brightness,
      secondary: presetColors.secondary,
    );

    return base.copyWith(
        colorScheme: themedScheme,
        scaffoldBackgroundColor: surfaceColor,
        cardColor: elevatedColor,
        cardTheme: CardTheme(
          color: elevatedColor,
          elevation: 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: surfaceColor,
          foregroundColor: themedScheme.onSurface,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: elevatedColor,
          indicatorColor: themedScheme.secondaryContainer,
          labelTextStyle:
              WidgetStatePropertyAll(TextStyle(color: themedScheme.onSurface)),
          iconTheme: WidgetStatePropertyAll(
              IconThemeData(color: themedScheme.onSurface)),
        ),
        dividerColor: borderColor,
        textTheme: base.textTheme.apply(
            bodyColor: themedScheme.onSurface,
            displayColor: themedScheme.onSurface),
        inputDecorationTheme: InputDecorationTheme(
            border:
                OutlineInputBorder(borderSide: BorderSide(color: borderColor))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                backgroundColor: themedScheme.primary,
                foregroundColor: themedScheme.onPrimary)),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: themedScheme.primary.withValues(alpha: 0.3)))));
  }

  void _ensurePrefs() {
    if (_prefs == null) {
      throw StateError('AppSettings has not been initialized yet.');
    }
  }
}
