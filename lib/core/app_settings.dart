import 'package:flutter/material.dart';
import 'package:omnis/core/text_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `RepeatMode` moved to `omnis_plugin_api` (see that package's
// `repeat_mode.dart`) so `PluginContext`/plugins can name it without
// depending on this file. Re-exported so every existing
// `import 'package:omnis/core/app_settings.dart' show RepeatMode` in
// this app keeps working unchanged.
export 'package:omnis_plugin_api/repeat_mode.dart' show RepeatMode;

enum AppThemeMode { system, light, dark }

/// Item 44/spec §22-27's six named theme presets. Only [classic] is
/// accent-color-driven (see `OmnisTheme.build`); the other five each
/// have a fixed palette (`OmnisPalette`) — replaces the earlier
/// invented `midnight`/`aurora`/`sunset` trio, which named nothing the
/// spec actually asks for.
enum AppThemePreset { classic, pure, drive, karaoke, future, audiophile }

enum ButtonLayout { standard, compact, minimal }

enum LibrarySource { wholePhone, dedicatedFolder, none }

enum GestureMode { swipe, taps, none }

enum LibraryDisplayMode { list, grid }

/// What renders behind the controls on the Now Playing screen.
enum NowPlayingBackgroundStyle { solid, blurredArt, gradient }

/// Row/tile spacing in library list and grid views.
enum LibraryDensity { comfortable, compact }

/// How large lyric text renders in [PlayerLyricsPanel] (the small lyric
/// box available inside Standard/Top Controls/Landscape layouts).
/// Deliberately mapped to existing `Theme.textTheme` styles rather than a
/// raw font-size multiplier, so lyrics stay visually consistent with the
/// rest of the screen at every step — [extraLarge] intentionally lands on
/// the same `headlineSmall` style the dedicated Karaoke Gestures layout
/// already uses for its full-screen lyrics, giving a taste of that
/// treatment without switching layouts.
enum LyricsTextSize { small, medium, large, extraLarge }

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const _hasCompletedOnboardingKey = 'app_has_completed_onboarding';
  static const _themeModeKey = 'app_theme_mode';
  static const _themePresetKey = 'app_theme_preset';
  static const _accentColorKey = 'app_accent_color';
  static const _albumArtScaleKey = 'app_album_art_scale';
  static const _textScaleFactorKey = 'app_text_scale_factor';
  static const _showAlbumArtKey = 'app_show_album_art';
  static const _showLyricsKey = 'app_show_lyrics';
  static const _karaokeModeKey = 'app_karaoke_mode';
  static const _lyricsTextSizeKey = 'app_lyrics_text_size';
  static const _buttonLayoutKey = 'app_button_layout';
  static const _gestureModeKey = 'app_gesture_mode';
  static const _swipeGesturesKey = 'app_swipe_gestures';
  static const _librarySourceKey = 'app_library_source';
  static const _selectedFolderPathKey = 'app_selected_folder_path';
  static const _libraryWatcherEnabledKey = 'app_library_watcher_enabled';
  static const _volumeKey = 'app_playback_volume';
  static const _speedKey = 'app_playback_speed';
  static const _pitchKey = 'app_playback_pitch';
  static const _skipSilenceEnabledKey = 'app_skip_silence_enabled';
  static const _crossfadeSecondsKey = 'app_crossfade_seconds';
  static const _seekIncrementSecondsKey = 'app_seek_increment_seconds';
  static const _gaplessEnabledKey = 'app_gapless_enabled';
  static const _disabledPluginsKey = 'app_disabled_plugins';
  static const _playerLayoutIdKey = 'app_player_layout_id';
  static const _autoLandscapeLayoutKey = 'app_auto_landscape_layout';
  static const _carModeControlsOnRightKey = 'app_car_mode_controls_on_right';
  static const _bottomNavAutoHideKey = 'app_bottom_nav_auto_hide';
  static const _keyboardShortcutsEnabledKey = 'app_keyboard_shortcuts_enabled';
  static const _songsViewModeKey = 'app_songs_view_mode';
  static const _songsGridColumnsKey = 'app_songs_grid_columns';
  static const _albumsViewModeKey = 'app_albums_view_mode';
  static const _albumsGridColumnsKey = 'app_albums_grid_columns';
  static const _genresViewModeKey = 'app_genres_view_mode';
  static const _genresGridColumnsKey = 'app_genres_grid_columns';
  static const _shortTrackThresholdSecondsKey =
      'app_short_track_threshold_seconds';
  static const _groupArtistsByAlbumArtistKey =
      'app_group_artists_by_album_artist';
  static const _reduceMotionEnabledKey = 'app_reduce_motion_enabled';
  static const _reduceTransparencyEnabledKey =
      'app_reduce_transparency_enabled';
  static const _highContrastEnabledKey = 'app_high_contrast_enabled';
  static const _hapticFeedbackEnabledKey = 'app_haptic_feedback_enabled';
  static const _dynamicColorFromArtEnabledKey =
      'app_dynamic_color_from_art_enabled';
  static const _nowPlayingBackgroundStyleKey =
      'app_now_playing_background_style';
  static const _autoBackupEnabledKey = 'app_auto_backup_enabled';
  static const _autoBackupIntervalDaysKey = 'app_auto_backup_interval_days';
  static const _lastAutoBackupAtKey = 'app_last_auto_backup_at';
  static const _libraryDensityKey = 'app_library_density';
  static const _customThemeIdKey = 'app_custom_theme_id';

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

  /// Whether the first-run onboarding flow (`lib/ui/onboarding/`) has been
  /// completed. Gates `MaterialApp.home` in `main.dart` — `false` shows
  /// `OnboardingPage` instead of `HomePage` on the very next launch after
  /// a fresh install, and never again once the user finishes (or skips)
  /// it.
  bool get hasCompletedOnboarding {
    return _prefs?.getBool(_hasCompletedOnboardingKey) ?? false;
  }

  set hasCompletedOnboarding(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_hasCompletedOnboardingKey, value);
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
      'pure' => AppThemePreset.pure,
      'drive' => AppThemePreset.drive,
      'karaoke' => AppThemePreset.karaoke,
      'future' => AppThemePreset.future,
      'audiophile' => AppThemePreset.audiophile,
      _ => AppThemePreset.classic,
    };
  }

  set themePreset(AppThemePreset preset) {
    _ensurePrefs();
    _prefs!.setString(
        _themePresetKey,
        switch (preset) {
          AppThemePreset.pure => 'pure',
          AppThemePreset.drive => 'drive',
          AppThemePreset.karaoke => 'karaoke',
          AppThemePreset.future => 'future',
          AppThemePreset.audiophile => 'audiophile',
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

  /// App-wide UI text scale — spec §58's "app-wide text scaling" gap
  /// (item 48): distinct from [lyricsTextSize] (scoped to just the
  /// lyrics view) and a declarative theme's own fixed
  /// `ThemeManifest.textScale` (an imported theme *author*'s choice,
  /// not a user preference). Defaults to `1.0` — no change from
  /// whatever the platform would otherwise render. Applied via
  /// `MaterialApp.builder` in `main.dart` using [clampTextScale] to
  /// keep the persisted value itself in the same safe range even if
  /// something else wrote to this key directly.
  double get textScaleFactor =>
      _prefs?.getDouble(_textScaleFactorKey) ?? 1.0;

  set textScaleFactor(double value) {
    _ensurePrefs();
    _prefs!.setDouble(_textScaleFactorKey, clampTextScale(value));
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

  LyricsTextSize get lyricsTextSize {
    final value = _prefs?.getString(_lyricsTextSizeKey) ?? 'medium';
    return switch (value) {
      'small' => LyricsTextSize.small,
      'large' => LyricsTextSize.large,
      'extraLarge' => LyricsTextSize.extraLarge,
      _ => LyricsTextSize.medium,
    };
  }

  set lyricsTextSize(LyricsTextSize size) {
    _ensurePrefs();
    _prefs!.setString(_lyricsTextSizeKey, size.name);
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

  /// Item 5/spec §8's "filesystem watchers" gap — automatically rescans
  /// [selectedFolderPath] shortly after files change there, instead of
  /// requiring a manual rescan every time. Defaults to `false`, the
  /// same opt-in stance `autoBackupEnabled` already takes for unattended
  /// background work nobody asked for until they turn it on. Desktop-
  /// only in practice (`MainCore` only starts the watcher off-Android) —
  /// this flag exists regardless of platform so the setting itself
  /// behaves consistently, it's just a no-op where it doesn't apply.
  bool get libraryWatcherEnabled =>
      _prefs?.getBool(_libraryWatcherEnabledKey) ?? false;

  set libraryWatcherEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_libraryWatcherEnabledKey, value);
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

  /// How far a skip-forward/skip-backward tap moves playback, in seconds.
  /// One of 10/15/30, matching the common presets other players offer —
  /// not free-form, so the UI can be a segmented choice rather than a
  /// slider for a value that only makes sense as a few round numbers.
  int get seekIncrementSeconds =>
      _prefs?.getInt(_seekIncrementSecondsKey) ?? 10;

  set seekIncrementSeconds(int value) {
    _ensurePrefs();
    const allowed = {10, 15, 30};
    _prefs!
        .setInt(_seekIncrementSecondsKey, allowed.contains(value) ? value : 10);
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

  /// Whether the bottom navigation bar auto-hides in Car Mode / landscape
  /// (revealed by a swipe-up or the edge handle) rather than always
  /// staying visible and covering more of the screen in those layouts.
  bool get bottomNavAutoHide => _prefs?.getBool(_bottomNavAutoHideKey) ?? true;

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

  /// When true, the Artists view groups by [BaseTrack.albumArtist]
  /// instead of each track's own first listed performer — the
  /// difference that matters is a various-artists compilation, whose
  /// tracks would otherwise scatter across many different per-track
  /// artist sections instead of grouping under one album artist.
  /// Defaults off: `albumArtist` is only populated where a real source
  /// (embedded tags, MusicBrainz) actually reports it, so most libraries
  /// see no difference until it is.
  bool get groupArtistsByAlbumArtist =>
      _prefs?.getBool(_groupArtistsByAlbumArtistKey) ?? false;

  set groupArtistsByAlbumArtist(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_groupArtistsByAlbumArtistKey, value);
    notifyListeners();
  }

  /// Ids of plugins the user has switched off.
  ///
  /// Plugin enable/disable used to live only in memory, so every restart
  /// silently switched every plugin back on.
  Set<String> get disabledPlugins =>
      (_prefs?.getStringList(_disabledPluginsKey) ?? const <String>[]).toSet();

  /// Whether [pluginId] was switched off by the user.
  bool isPluginDisabled(String pluginId) => disabledPlugins.contains(pluginId);

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

  /// Shortens or skips new motion added under `lib/ui/theme/` (see
  /// `OmnisMotion.durationFor`) — accessibility-motivated, separate from
  /// [reduceTransparencyEnabled] since a user can be sensitive to one
  /// without the other. Defaults to `false`: this is opt-in, not a
  /// silent behavior change for people who already like the app moving.
  bool get reduceMotionEnabled =>
      _prefs?.getBool(_reduceMotionEnabledKey) ?? false;

  set reduceMotionEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_reduceMotionEnabledKey, value);
    notifyListeners();
  }

  /// Gates blur/backdrop effects (Now Playing's blurred-art background)
  /// separately from [reduceMotionEnabled] — for lower-end hardware where
  /// `BackdropFilter` is expensive, or vestibular/visual sensitivity to
  /// blur specifically rather than motion.
  bool get reduceTransparencyEnabled =>
      _prefs?.getBool(_reduceTransparencyEnabledKey) ?? false;

  set reduceTransparencyEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_reduceTransparencyEnabledKey, value);
    notifyListeners();
  }

  /// §58's "high contrast" accessibility requirement — flows into
  /// [OmnisTheme.build]'s `highContrast` param, which both raises
  /// `ColorScheme.fromSeed`'s `contrastLevel` (a real Material 3
  /// mechanism for this, not a hand-rolled palette) and swaps the
  /// low-alpha borders/dividers/outlined-button strokes every preset
  /// otherwise uses for fully-opaque, near-black/near-white ones.
  /// Defaults to `false`, the same opt-in stance [reduceMotionEnabled]
  /// takes — a visible palette change shouldn't happen to someone who
  /// never asked for it.
  bool get highContrastEnabled =>
      _prefs?.getBool(_highContrastEnabledKey) ?? false;

  set highContrastEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_highContrastEnabledKey, value);
    notifyListeners();
  }

  /// Item 4/50's "automatic scheduled backups" gap — `BackupService`
  /// previously only ever ran from the two manual buttons on
  /// `BackupSettingsPage`, with no timer or interval anywhere. Defaults
  /// to `false`: writing a zip to disk unattended is a real, if small,
  /// storage/behavior change nobody asked for until they opt in.
  bool get autoBackupEnabled =>
      _prefs?.getBool(_autoBackupEnabledKey) ?? false;

  set autoBackupEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_autoBackupEnabledKey, value);
    notifyListeners();
  }

  /// How often an automatic backup should run, in days. Defaults to 7
  /// (weekly) — frequent enough to matter, infrequent enough not to pile
  /// up disk usage between prunes.
  int get autoBackupIntervalDays =>
      _prefs?.getInt(_autoBackupIntervalDaysKey) ?? 7;

  set autoBackupIntervalDays(int value) {
    _ensurePrefs();
    _prefs!.setInt(_autoBackupIntervalDaysKey, value < 1 ? 1 : value);
    notifyListeners();
  }

  /// When the last automatic backup actually ran, or `null` if one never
  /// has — `BackupScheduler.isDue` treats `null` as due immediately, so
  /// a fresh install/first-ever enable doesn't wait a full interval for
  /// its first backup.
  DateTime? get lastAutoBackupAt {
    final ms = _prefs?.getInt(_lastAutoBackupAtKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastAutoBackupAt(DateTime? value) {
    _ensurePrefs();
    if (value == null) {
      _prefs!.remove(_lastAutoBackupAtKey);
    } else {
      _prefs!.setInt(_lastAutoBackupAtKey, value.millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  /// Whether `OmnisHaptics` calls actually vibrate. Defaults to `true` —
  /// unlike [reduceMotionEnabled], most players ship haptics on by
  /// default and this is the "turn it off" escape hatch, not an opt-in.
  bool get hapticFeedbackEnabled =>
      _prefs?.getBool(_hapticFeedbackEnabledKey) ?? true;

  set hapticFeedbackEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_hapticFeedbackEnabledKey, value);
    notifyListeners();
  }

  /// Global playback keyboard shortcuts (`GlobalKeyboardShortcuts` —
  /// Space to play/pause, arrows to seek/change volume, Ctrl+arrows for
  /// next/previous, plus hardware media keys). Defaults to `true`: these
  /// shortcuts only ever fire when nothing more specific already
  /// consumed the key event (see that widget's own doc comment), so
  /// there's no accidental-activation risk that would call for an
  /// opt-in default the way [reduceMotionEnabled] needs one.
  bool get keyboardShortcutsEnabled =>
      _prefs?.getBool(_keyboardShortcutsEnabledKey) ?? true;

  set keyboardShortcutsEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_keyboardShortcutsEnabledKey, value);
    notifyListeners();
  }

  /// Whether Now Playing tints itself from the current track's artwork
  /// (`DynamicColorExtractor`) instead of the static preset scheme.
  /// Defaults to `false`: extraction has a real cost and a preset-scheme
  /// upgrade must not silently start doing more work per track change
  /// than it did before.
  bool get dynamicColorFromArtEnabled =>
      _prefs?.getBool(_dynamicColorFromArtEnabledKey) ?? false;

  set dynamicColorFromArtEnabled(bool value) {
    _ensurePrefs();
    _prefs!.setBool(_dynamicColorFromArtEnabledKey, value);
    notifyListeners();
  }

  /// What renders behind Now Playing's controls. Defaults to `solid` —
  /// exactly what every layout already draws today, so upgrading never
  /// changes an existing user's screen until they opt into something else.
  NowPlayingBackgroundStyle get nowPlayingBackgroundStyle {
    final value = _prefs?.getString(_nowPlayingBackgroundStyleKey) ?? 'solid';
    return switch (value) {
      'blurredArt' => NowPlayingBackgroundStyle.blurredArt,
      'gradient' => NowPlayingBackgroundStyle.gradient,
      _ => NowPlayingBackgroundStyle.solid,
    };
  }

  set nowPlayingBackgroundStyle(NowPlayingBackgroundStyle style) {
    _ensurePrefs();
    _prefs!.setString(
        _nowPlayingBackgroundStyleKey,
        switch (style) {
          NowPlayingBackgroundStyle.blurredArt => 'blurredArt',
          NowPlayingBackgroundStyle.gradient => 'gradient',
          NowPlayingBackgroundStyle.solid => 'solid',
        });
    notifyListeners();
  }

  /// Row/tile spacing in library list and grid views. Defaults to
  /// `comfortable` — today's existing spacing, unchanged until a user
  /// opts into `compact`.
  LibraryDensity get libraryDensity {
    final value = _prefs?.getString(_libraryDensityKey) ?? 'comfortable';
    return value == 'compact'
        ? LibraryDensity.compact
        : LibraryDensity.comfortable;
  }

  set libraryDensity(LibraryDensity density) {
    _ensurePrefs();
    _prefs!.setString(_libraryDensityKey,
        density == LibraryDensity.compact ? 'compact' : 'comfortable');
    notifyListeners();
  }

  /// The id of a user-imported theme to use instead of [themePreset]/
  /// [accentColor], or `null` to use the built-in preset system as
  /// normal. `null` rather than an empty string for "not set" — an id an
  /// imported theme actually chose could theoretically be empty-ish after
  /// a bad import, so `null` unambiguously means "nothing selected"
  /// separately from "selected, but not found" (a since-uninstalled
  /// theme), which callers resolving this id distinguish themselves.
  String? get customThemeId => _prefs?.getString(_customThemeIdKey);

  set customThemeId(String? id) {
    _ensurePrefs();
    if (id == null) {
      _prefs!.remove(_customThemeIdKey);
    } else {
      _prefs!.setString(_customThemeIdKey, id);
    }
    notifyListeners();
  }

  void _ensurePrefs() {
    if (_prefs == null) {
      throw StateError('AppSettings has not been initialized yet.');
    }
  }
}
