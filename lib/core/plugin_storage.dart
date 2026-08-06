import 'package:shared_preferences/shared_preferences.dart';

/// Scoped, namespaced persistence for a single plugin.
///
/// Before this existed, a plugin that needed to remember something had no
/// choice but to add a key plus a getter/setter pair to [AppSettings]
/// itself (`favoriteTrackIds`, `autoTaggedTrackIds`, the lyrics-by-track
/// map, the play history list are all exactly that) — the same
/// "adding a plugin means editing the Core" problem [PluginContext]
/// already solved for playback, just restated for storage. `PluginStorage`
/// closes the same gap: every plugin gets its own key-value store, backed
/// by the same [SharedPreferences] instance `AppSettings` uses, without
/// either of them knowing the other exists.
///
/// Every key is automatically namespaced as `plugin_<pluginId>_<key>`, so
/// two plugins can each call `storage.setString('token', ...)` without
/// colliding, and [clear] only ever wipes this plugin's own keys.
///
/// Reads are synchronous and return a default (`null`, mirroring
/// `SharedPreferences` itself) until the backing store is warm.
/// [PluginManager] calls [initialize] once, before a plugin's
/// `initialize()`/`enable()` hook runs, so a plugin can read its own
/// storage from the very first line of those hooks. Writes self-initialize
/// if that was skipped — e.g. a plugin constructed directly in a test —
/// so calling [initialize] explicitly is an optimization, never a
/// requirement.
class PluginStorage {
  PluginStorage(this.pluginId);

  /// The owning plugin's [MusicPlugin.id].
  final String pluginId;

  SharedPreferences? _prefs;

  String get _prefix => 'plugin_${pluginId}_';

  String _k(String key) => '$_prefix$key';

  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _ready() async =>
      _prefs ??= await SharedPreferences.getInstance();

  String? getString(String key) => _prefs?.getString(_k(key));
  Future<void> setString(String key, String value) async =>
      (await _ready()).setString(_k(key), value);

  bool? getBool(String key) => _prefs?.getBool(_k(key));
  Future<void> setBool(String key, bool value) async =>
      (await _ready()).setBool(_k(key), value);

  int? getInt(String key) => _prefs?.getInt(_k(key));
  Future<void> setInt(String key, int value) async =>
      (await _ready()).setInt(_k(key), value);

  double? getDouble(String key) => _prefs?.getDouble(_k(key));
  Future<void> setDouble(String key, double value) async =>
      (await _ready()).setDouble(_k(key), value);

  List<String>? getStringList(String key) => _prefs?.getStringList(_k(key));
  Future<void> setStringList(String key, List<String> value) async =>
      (await _ready()).setStringList(_k(key), value);

  /// Removes a single key.
  Future<void> remove(String key) async => (await _ready()).remove(_k(key));

  /// Removes every key this plugin has written, without touching any
  /// other plugin's keys or `AppSettings`' own — safe thanks to the
  /// `plugin_<id>_` prefix every key above is written under.
  Future<void> clear() async {
    final prefs = await _ready();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
