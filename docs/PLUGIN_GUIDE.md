# Building an Omnis Plugin

Omnis is a micro-kernel: `lib/core/` is a small, stable playback engine
that never imports a concrete plugin, and everything else — lyrics,
equalizer, scrobbling, smart playlists, tag editing, and more — is a
plugin under `lib/plugins/`. This guide is everything you need to build
your own, whether it ships compiled into the app or gets installed later
from a GitHub URL.

For the *why* behind this design (interfaces, the service registry, the
event bus, the layering between `lib/core/` and `lib/plugin_api/`), see
[ARCHITECTURE.md](ARCHITECTURE.md). This guide is deliberately
task-focused — how do I actually write the thing — and stays
self-contained so you don't have to read the architecture doc first.

## Two kinds of plugin

| | Bundled | Downloaded |
|---|---|---|
| Lives in | `lib/plugins/`, compiled into the app | a GitHub repo, installed at runtime |
| Language | full Dart + Flutter | a restricted Dart subset, interpreted by `dart_eval` |
| Base | extends `MusicPlugin` | a top-level `createPlugin()` function + hook functions |
| Can render real widgets | yes | no — returns a small declarative `Map` instead |
| Reaches playback via | `context` (`PluginContext`) | hook return values only |
| Distribution | part of the Omnis source tree | anyone with a GitHub repo |

Use **bundled** for anything you want shipped with the app, or that needs
a real widget, `ServiceRegistry`/`EventBus` participation, or
`PluginStorage`. Use **downloaded** for something you want to distribute
independently without a PR against this repo, and that only needs to
react to hooks or show a simple badge.

Most of this guide covers bundled plugins, since that's where the real
capability surface lives. Downloaded plugins get their own section near
the bottom.

## Quick start: a bundled plugin

The fastest way to see everything below in one place is
[`example/example_plugin.dart`](../example/example_plugin.dart) — a
small, complete, real plugin that compiles and is checked by
`flutter analyze` (it's just not registered, so it doesn't run in the
app). It demonstrates every piece this guide walks through: the
lifecycle, `PluginContext`, `PluginStorage`, a Now Playing badge, and a
settings page. Skim it once, then come back here for the details.

### 1. Create the file

Add `lib/plugins/my_plugin.dart`:

```dart
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

class MyPlugin extends MusicPlugin {
  @override
  String get id => 'my_plugin';
  @override
  String get name => 'My Plugin';
  @override
  String get description => 'Does something cool';
  @override
  String get version => '1.0.0';
  @override
  String get author => 'You';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {}

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}
```

### 2. Register it

Add one line to `lib/plugins/bundled_plugins.dart`:

```dart
List<MusicPlugin> createBundledPlugins() => <MusicPlugin>[
      // ...existing plugins...
      MyPlugin(),
    ];
```

That's it — no other file changes. `MainCore` calls `createBundledPlugins()`,
hands every plugin a `PluginContext`, and registers it. `lib/core/` never
learns your plugin's name.

Order in this list matters in two ways: it's the order hooks are
dispatched in, and it's the registration order for any `ServiceRegistry`
interface more than one plugin registers under (see
[`IQueueBuilder`](ARCHITECTURE.md#why-interfaces-live-in-libplugin_api-not-libcore)
for a real example of why that can matter).

## The `MusicPlugin` lifecycle

```dart
abstract class MusicPlugin {
  PluginContext? get context;   // null until attached — see below
  PluginStorage get storage;    // never null, safe from a bare constructor

  void attach(PluginContext context);   // called by PluginManager

  String get id;           // unique, stable — used as a storage/UI key
  String get name;
  String get description;
  String get version;
  String get author;

  Future<void> initialize();               // once, when first registered+enabled
  Future<void> onTrackStart(BaseTrack track);
  Future<void> onLibraryScan(String file);  // once per file during a scan
  dynamic uiSlot(String locationID);        // see "Injecting UI" below
  Future<void> dispose();                   // app shutdown

  Future<void> enable() async {}   // re-enabled after being disabled
  Future<void> disable() async {}  // user switched it off — release effects here
}
```

Every hook call — `initialize`, `onTrackStart`, `onLibraryScan`, `uiSlot`,
`enable`, `disable`, `dispose` — runs inside `PluginSandbox`. If your code
throws, the error is caught, logged to the Plugin Health dashboard (the
Plugins tab), and the rest of the app keeps running. **You don't need
your own try/catch for "don't crash the player"** — the sandbox already
gives you that. Do still handle expected failure cases (a failed HTTP
request, a missing file) explicitly, the way `MetadataEnrichmentPlugin`
treats a non-200 response as "no match" rather than letting it throw.

`disable()` is where you undo anything with an ongoing effect on
playback — most commonly, clearing a gain contribution (see below) so a
disabled plugin leaves no trace. `enable()` is the mirror: re-apply
whatever `disable()` released. A plugin that's re-enabled after being
switched off gets `enable()`, not a second `initialize()` call.

## `PluginContext`: reaching playback

`context` (`null` until `attach()` runs — always use `context?.`, never
assume it's non-null, since a plugin constructed directly in a test
never gets one) forwards essentially all of `AudioEngine`'s public
surface:

```dart
// Read-only state
context?.currentTrack;      // BaseTrack?
context?.queue;             // List<BaseTrack>
context?.currentIndex;      // int
context?.isPlaying;         // bool
context?.shuffleEnabled;    // bool
context?.repeatMode;        // RepeatMode
context?.volume; context?.speed; context?.pitch;
context?.crossfadeDuration; context?.gaplessEnabled;

// Streams
context?.trackStream;       // Stream<BaseTrack?>
context?.queueStream;       // Stream<List<BaseTrack>>
context?.positionStream;    // Stream<Duration>
context?.durationStream;    // Stream<Duration?>
context?.playerStateStream; // Stream<PlayerState>

// Transport
await context?.play();
await context?.pause();
await context?.stop();
await context?.next();
await context?.previous();
await context?.seek(position);
await context?.playAt(index);
await context?.setQueue(tracks, startIndex: 0);
await context?.addTrack(track);
await context?.removeTrack(index);

// Toggles
await context?.setVolume(0.8);
await context?.setSpeed(1.0);
await context?.setPitch(1.0);
await context?.setShuffleEnabled(true);
await context?.setRepeatMode(RepeatMode.all);
context?.setCrossfadeDuration(Duration(seconds: 5));
context?.setGaplessEnabled(true);
await context?.setSkipSilenceEnabled(false);

// A-B repeat
context?.markLoopA(); context?.markLoopB(); context?.clearLoop();
context?.abRepeatRange; context?.loopAMarker;

// Composable gain — see below
await context?.setGain('my_plugin', 1.1);
await context?.clearGain('my_plugin');
```

If something you need genuinely isn't here, it's a gap worth filing —
the design intent is that a plugin never has to wait on a Core change to
reach playback.

### Composable gain

Volume shaping (ReplayGain, an equalizer trim, your own effect) is
additive, not exclusive: every plugin contributes under **its own key**,
and the engine multiplies them all together.

```dart
await context?.setGain('my_plugin', 1.1);   // +10%
await context?.clearGain('my_plugin');       // back to no contribution
```

Always clear your contribution in `disable()` — otherwise a disabled
plugin keeps shaping audio nobody can see it's responsible for.

## `PluginStorage`: your own persisted settings

Every plugin gets a namespaced key-value store — `storage`, never `null`,
safe to use even from a plugin built directly in a unit test:

```dart
storage.getString('token');          String?
await storage.setString('token', value);

storage.getBool('enabled');          bool?
await storage.setBool('enabled', value);

storage.getInt('count');             int?
await storage.setInt('count', value);

storage.getDouble('gain');           double?
await storage.setDouble('gain', value);

storage.getStringList('tags');       List<String>?
await storage.setStringList('tags', value);

await storage.remove('token');
await storage.clear();               // wipes only this plugin's own keys
```

Every key is transparently namespaced as `plugin_<your id>_<key>`, backed
by the same `SharedPreferences` store the rest of the app uses — so two
plugins can both call `storage.setString('token', ...)` without
colliding. Reads are synchronous and default to `null`/absent until the
store is warm; `PluginManager` warms it *before* your `initialize()`
runs, so a synchronous read on the first line of `initialize()` already
sees whatever a previous session persisted. Writes self-initialize even
if you never call anything first — the common case in a unit test that
builds a plugin directly, without going through `PluginManager`.

**You should never need to touch `AppSettings` from a plugin.** If you
find yourself wanting to add a key there, it almost always belongs in
your plugin's own `storage` instead — that's the whole point of this
type existing. (`shuffleEnabled`/`repeatMode`,
Last.fm/Discogs/MusicBrainz credentials, the Essentia service URL, and
the artist-separator list all used to live in `AppSettings` and were
migrated out for exactly this reason — see
[ARCHITECTURE.md](ARCHITECTURE.md) for the full history.)

## Injecting UI: `uiSlot(locationID)`

```dart
@override
dynamic uiSlot(String locationID) => switch (locationID) {
      'now_playing_overlay' => MyBadge(),
      _ => null,
    };
```

Return `null` for any location you have nothing for — that's the common
case, not an error.

| `locationID` | Where it renders | Dispatch |
|---|---|---|
| `now_playing_overlay` | Floating over the Now Playing screen | aggregate |
| `now_playing_bottom` | Bottom of the Now Playing screen | aggregate |
| `library_header` | Top of the Library page | aggregate |
| `settings_page` | Inside the shared Settings page | aggregate |
| `sidebar_item` | App navigation sidebar | aggregate |
| `plugin_settings` | This plugin's own settings page | **singular** |

**Aggregate** locations ask *every enabled plugin* and render whatever
comes back, side by side (`PluginSlotView`). **`plugin_settings`** is
different: it's asked of *exactly one plugin* — whichever the user
tapped in the Plugins list — via `PluginManager.uiSlotForPlugin`, not the
aggregate `uiSlot`. It's also the one location still reachable while a
plugin is disabled, so a disabled plugin can still be reconfigured or
re-enabled from its own settings page.

A bundled plugin can return a real `Widget`:

```dart
'plugin_settings' => MySettingsView(plugin: this),
```

Build `MySettingsView` however you like — a `StatefulWidget` reading and
writing `plugin.storage` directly is the pattern every bundled plugin in
this repo uses (see `MetadataEnrichmentPlugin`, `AudioAnalysisPlugin`, or
`TagEditorPlugin` for real, working examples with text fields, chips, and
toggles).

## Talking to other plugins: `ServiceRegistry` and `EventBus`

Most plugins never need this section — skip it unless you're building
something another plugin (or a page) should be able to discover without
hardcoding your plugin's name.

**`ServiceRegistry`** is a lookup keyed by *interface*, not concrete
class. Define an interface in `lib/plugin_api/service_interfaces.dart`
(only if one that fits doesn't already exist — see the six real ones
there for the shape), implement it, and register/unregister across your
lifecycle:

```dart
class MyPlugin extends MusicPlugin implements ISomeCapability {
  @override
  Future<void> initialize() async {
    context?.services.register(ISomeCapability, this);
  }

  @override
  Future<void> enable() async {
    context?.services.register(ISomeCapability, this);
  }

  @override
  Future<void> disable() async {
    context?.services.unregister(ISomeCapability, this);
  }

  @override
  Future<void> dispose() async {
    context?.services.unregister(ISomeCapability, this);
  }
}
```

A caller asks for the interface, never the concrete plugin:
`pluginManager.services.get<ISomeCapability>()` (first/primary
registration) or `getAll<ISomeCapability>()` (every one — used when more
than one plugin can reasonably implement the same capability, like
`IQueueBuilder`).

Before adding an interface, ask the same question this project's own
design rule asks: *could someone reasonably want to replace this with a
different implementation?* If there's genuinely only one sensible way to
implement something, a plain concrete plugin (`PluginManager.bundled<T>()`)
is the right call, not an interface for its own sake.

**`EventBus`** is typed publish/subscribe, for announcing something
happened without knowing who — if anyone — is listening:

```dart
context?.events.emit(MyEvent(someValue));
```

```dart
final sub = pluginManager.events.on<MyEvent>().listen((event) { ... });
```

Matched by exact runtime type. `FavoritesPlugin`'s `FavoriteChangedEvent`
(`lib/plugin_api/events.dart`) is the real, working example — it's what
lets the Playlists page's "Favorites" smart list update immediately when
a favorite changes elsewhere in the app, without polling.

## Testing your plugin

Construct it directly — no `PluginManager` needed for most tests:

```dart
test('does the thing', () {
  final plugin = MyPlugin();
  expect(plugin.someBehavior(), isTrue);
});
```

For anything touching `storage`, seed a mock `SharedPreferences` store
first (every test file in `test/` does this in `setUp`):

```dart
setUp(() {
  SharedPreferences.setMockInitialValues({});
});
```

Skipping this is a real, easy-to-hit mistake: `PluginStorage` falls back
to a real platform channel when nothing mocks `SharedPreferences`, which
hangs a widget test for its full default timeout instead of failing
fast — always add the line above before anything touches storage.

For anything touching `context`, build a real `PluginContext` with a
fake `AudioEngine` (`implements AudioEngine` + `noSuchMethod` that throws
`UnsupportedError` for anything unstubbed is the pattern used throughout
`test/`):

```dart
class _FakeEngine implements AudioEngine {
  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not stubbed');
}

final plugin = MyPlugin();
plugin.attach(PluginContext(
  audioEngine: _FakeEngine(),
  services: ServiceRegistry(),
  events: EventBus(),
));
```

For a full end-to-end test (registration order, hook dispatch, disable
releasing a gain contribution), build a real `PluginManager` — see
`test/plugin_architecture_test.dart` for several worked examples.

Run everything before opening a PR:

```bash
flutter analyze
flutter test
```

## Downloaded plugins

A downloaded plugin is two files: `plugin.dart` (the entrypoint) and
`omnis_plugin.yaml` (the manifest), hosted in any public GitHub repo.
Installed by pasting the repo URL into the Plugins tab.

### `omnis_plugin.yaml`

```yaml
id: my_plugin
name: My Plugin
description: Does something cool
version: 1.0.0
author: Your Name
entrypoint: plugin.dart
hooks:
  - onTrackStart
  - onLibraryScan
permissions:
  - network
```

Only `id` and `name` are required — everything else has a sensible
default (`entrypoint` defaults to `plugin.dart`, `version` to `0.0.1`,
etc.). `permissions` is shown to the user in a confirmation dialog
*before* any of your code executes — declare only what you actually use.
`storage`/`filesystem` grants dart_eval's `FilesystemPermission.any`;
there's no finer-grained scoping available at that layer, so ask for it
only if you genuinely need file access.

### `plugin.dart`

```dart
dynamic createPlugin(dynamic api) {
  return {
    'id': 'my_plugin',
    'name': 'My Plugin',
    'description': 'Does something cool',
    'version': '1.0.0',
    'author': 'Your Name',
    'hooks': ['onTrackStart', 'onLibraryScan'],
  };
}

dynamic onTrackStart(dynamic track) {
  // track is a JSON Map: {id, title, artists, album, duration, ...}
  return null;
}

dynamic onLibraryScan(dynamic file) {
  // file is a String path
  return null;
}

dynamic uiSlot(dynamic locationID) {
  if (locationID != 'now_playing_overlay') return null;
  // No package:flutter here — dart_eval can't construct a real Widget.
  // Return a small declarative Map instead; the host renders it.
  return {'type': 'badge', 'text': 'Hello from my plugin', 'icon': 'info'};
}
```

Your code runs through `dart_eval`, a real Dart interpreter — but it
compiles against an isolated `package:default`, so it **cannot import
`package:omnis` or `dart:ui`**. Every hook receives and returns plain
JSON-compatible values (Maps, Strings, numbers, lists), never a Flutter
type or an Omnis class. This is what makes a downloaded plugin safe to
run without recompiling the app: it has no way to reach the widget tree,
the file system beyond what it declared, or any Core internals.

The declarative `uiSlot` payload supports two shapes today:
`{'type': 'text', 'text': '...'}` and
`{'type': 'badge', 'text': '...', 'icon': '...'}` (`icon` is one of
`info`, `music`, `history`, `star`, or anything else falls back to a
generic icon). `PluginSlotView` on the host side renders these
generically — there's currently no `plugin_settings` support for
declarative payloads beyond a read-only text/badge summary, since real
form fields need a real `Widget`.

See [`sample_logger`](https://github.com/MrIvoe/Omnis-Plugins/tree/main/sample_logger)
in the [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) catalog
repo for a complete, working example — it's exercised by
`test/plugin_system_test.dart` through the actual `dart_eval`
interpreter, not just written and assumed to work. Downloadable plugins
used to live in a `plugins/` folder in this repo; they've since moved to
that dedicated repo so they can be versioned and published independently
of the app (see "Plugin catalog" in [BUILDING.md](BUILDING.md)).

### Publishing one

1. Push `plugin.dart` + `omnis_plugin.yaml` to a public GitHub repo. Two
   layouts both work:
   - **Its own repo**, manifest at the root — share
     `https://github.com/user/repo` and the installer downloads that
     whole repo as the plugin.
   - **A subfolder of a catalog repo** (how `Omnis-Plugins` itself is
     laid out — one folder per plugin) — share
     `https://github.com/user/repo/tree/branch/your-plugin-folder` and
     the installer downloads the repo zip but only extracts and
     validates that one folder, so it installs as just your plugin, not
     the whole catalog.
2. Share the URL. Anyone installs it via Plugins → paste the URL →
   confirm the permission dialog → Install — or, for something merged
   into `Omnis-Plugins` itself, add a `CatalogPluginEntry` to
   `officialPluginCatalog` in `lib/ui/plugins_page.dart` so it shows up
   as a one-tap install instead of requiring a pasted URL.
3. New versions: bump `version` in the manifest, push, and users
   reinstall from the URL — there's no auto-update mechanism today.

## Checklist before shipping

- [ ] `flutter analyze` is clean (bundled plugins only — n/a for downloaded)
- [ ] `flutter test` passes, including any tests you added
- [ ] `disable()` releases anything `initialize()`/`enable()` set up
      (gain contributions especially)
- [ ] Nothing touches `AppSettings` — persisted state goes through your
      own `storage`
- [ ] Every external call (HTTP, file I/O) fails soft — a bad response
      or missing file returns an empty/default result, not a throw the
      user sees as a crash
- [ ] `description` is honest about what's configured vs. not (see
      `MetadataEnrichmentPlugin.description` for the pattern: different
      text depending on whether a credential is set)
