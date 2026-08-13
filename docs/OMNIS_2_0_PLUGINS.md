# Omnis 2.0 — Plugin Architecture & Developer Guide

> **Status:** Canonical reference for the Omnis 2.0 plugin platform.
> This document is the third and final reference for the Omnis 2.0 build — read it
> together with [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md) (the product
> specification) and [OMNIS_2_0_UI_SPEC.md](OMNIS_2_0_UI_SPEC.md) (the
> UI/UX specification). It defines how the plugin platform works, how
> plugins are discovered, installed, configured, and how developers can build
> and publish them.

## 0. The central concept — "The RuneLite of music"

The Omnis plugin platform is inspired by the success of the RuneLite client
and its plugin hub. Just as RuneLite transformed the Old School RuneScape
experience through a vast community-driven plugin ecosystem, Omnis uses the
same model for music.

The platform has two complementary halves:

1. **The Omnis Core** — the "boring" foundation. It provides the
   `PluginContext`, capability contracts, and a secure runtime (mirroring the
   `runelite-client`).
2. **The Omnis Plugin Repository** — a plugin hub (mirroring the
   `plugin-hub`) for community-created plugins. This document covers how that hub works,
   how the catalog is generated, and how developers can submit a plugin and see it in
   the in-app marketplace.

**The end-to-end journey for the user should be:**

> **Discover → Install → Configure → Use**

No manual downloads. No API keys unless a plugin fundamentally requires one. No developer
tools required. Omnis handles everything automatically.

---

# 1. The plugin manifest (`omnis_plugin.yaml`)

Every plugin — bundled or from the hub — declares its capabilities through a manifest.
This is the `CapabilityDescriptor` required by the product spec. It is the single source of
truth the Core uses to understand and safely load a plugin.

## 1.1 Example manifest

```yaml
# Unique identifier: reverse-DNS
id: com.mycompany.metadata-plus# Human-readable name
name: Metadata Plus
version: 1.2.0
description: Enriches tags via MusicBrainz and a local AI model.
author: MyName
website: https://mycompany.com# main entry class (must implement Plugin)
mainClass: com.mycompany.metadataplus.MetadataPlusPlugin

# Dependencies on other plugins or the Omnis API#
dependencies:
  omnis-api: ">=2.0.0 <3.0.0"
  plugins:
    - id: com.omnis.lyrics
      version: ">=1.0.0"

# Capabilities this plugin provides
provides:
  - IMetadataProvider
  - IArtworkProvider

permissions:
  - network:musicbrainz
  - library:read

# UI contribution points
ui-contributions:
  settings-page: true
  track-context-menu: true

# Privacy declaration, shown in the marketplace
privacy:
  data-collected:
    - "Track metadata (title, artist, album) for enrichment"
    - "No listening data or personal information is sent"
  network-hosts:
    - "api.musicbrainz.org"
```

---

# 2. Plugin lifecycle & reliability

This is non-negotiable for the "boring core" principle. Plugins must be isolated
from the core.

## 2.1 Lifecycle states

```text
[INSTALLED] -> [LOADING] -> [INITIALIZING] -> [ACTIVE]
                                          |
                                         [ERROR]
                                          |
                                        [DISABLED] -> [UNINSTALLED]
```

## 2.2 Isolation, health, and the watchdog

*   **Isolation:** Bundled plugins live in the same process, but all errors are caught by the runtime.
*   **Future isolates:** for untrusted community plugins, the Core may run them in a separate isolate to prevent UI freezes.
*   **`PluginHealthCenter`:** central monitoring service.
    *   **Heartbeat:** the Core periodically pings each active plugin. A failed ping triggers a restart/retry.
    *   **Error handling:** exceptions in plugin code are caught by the plugin runtime. The health center logs and attempts recovery.
    *   **Recovery strategy:** the `PluginWatchdog` implements the retry/recovery logic. No single plugin can take down the app.

**What the user sees — the plugin health center:**

```text
┌─────────────────────────────────────────────────────┐
│  PLUGIN HEALTH                                      │
│                                                     │
│  🟢  Metadata Plus        [ACTIVE]   [View Logs]   │
│      - MusicBrainz provider is operational.        │
│                                                     │
│  🟡  YouTube Import       [WARNING]   [Fix...]      │
│      - Authentication expired. Click to refresh.  │
│                                                     │
│  🔴  Visualizer FX        [ERROR]     [Disable]     │
│      - Failed to initialize audio capture.         │
│      - Retry? [Restart Plugin]                    │
└─────────────────────────────────────┘
```

---

# 3. Plugin settings — the "fine-tune" experience

Every plugin must be fully functional out of the box, but power users must be able
to fine-tune everything — your RuneLite Config equivalent.

## 3.1 Plugin-scoped settings namespace

Settings for a plugin live outside `AppSettings`. The Core provides a `PluginSettings`
object — a key-value store scoped to exactly that plugin.

```dart
// Conceptual example
class MyPlugin extends Plugin {
  void onEnable() {
    // Use a default if no value exists
    final apiKey = context.settings.getString('musicbrainz_api_key') ?? 'DEFAULT_KEY';
  }
}
```

## 3.2 Automatic settings UI generation

The core automatically generates a single settings page per plugin, based on the plugin's
declared settings. This supports the "plugins contribute capabilities, not navigation"
rule from the UI spec.

```dart
// Example settings schema
class MyPluginSettings {
  @SettingField(
    name: 'MusicBrainz API Key',
    description: 'Optional: provide your own key for higher rate limits',
    defaultValue: '',
    type: SettingType.STRING,
    secure: true,
  )
  late String musicbrainzApiKey;

  @SettingField(
    name: 'Auto-enrich on scan',
    description: 'Automatically enrich metadata for new music during a scan',
    defaultValue: true,
    type: SettingType.BOOLEAN,
  )
  late bool autoEnrich;
}
```

**Generated UI (`Settings → Plugins → Metadata Plus`):**

```text
┌─────────────────────────────────────────────────────┐
│  METADATA PLUS                                      │
│  [manifest description text]                    │
│                                                     │
│  ┌─────────────────────────────────────────────────┐│
│  │  🛠 Auto-enrich on scan                [✓]     ││
│  │  Automatically fetch metadata...              ││
│  └─────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────┐│
│  │  🔑 MusicBrainz API Key               [•••••••]││
│  │  Optional: provide your own key for...              ││
│  └─────────────────────────────────────────────────┘│
│                                                     │
│  [Reset to Defaults]                                   │
└─────────────────────────────────────────────────────┘
```

---

# 4. The Plugin Marketplace — the "Plugin Hub"

This is the consumer-facing catalog that makes discovery easy, mirroring the RuneLite plugin-hub.

## 4.1 In-app marketplace

When the user clicks "Browse plugins," Omnis fetches a catalog from a configurable
trusted endpoint (e.g. `https://plugins.omnis.app/catalog.json`). This catalog is generated
from the repository.

The catalog UI follows the spec's capability/permission philosophy:

```text
┌─────────────────────────────────────────────────────┐
│  PLUGIN MARKETPLACE                                     │
│  [Search Plugins...]                                     │
│                                                     │
│  CATEGORIES ─────────►│  FEATURED                                │
│  ⭐ Featured │  ┌──────────────────────────────────┐│
│  🎵 Audio    │  │  ✨ Visualizer FX                ││
│  📁 Metadata │  │  Stunning audio-reactive visualizations. ││
│  📦 Services │  │  ⚠ Requires: Microphone        ││
│  🎨 UI       │  │  [Install]     [4.5 ★]      ││
│  ⚙ Tools       │  └──────────────────────────────────┘│
│  🤖 AI         │  ┌──────────────────────────────────┐│
│  🚗 Hardware │  │  🤖 Smart Playlist AI           ││
│               │  │  Uses an LLM to create mood-playlists.││
│               │  │  [Install]     [3.8 ★]      ││
│               │  └──────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

**What the user sees after clicking Install:**

1.  The user is shown the manifest and a permission summary:
    "This plugin requires: network access to MusicBrainz, read access to your library."
2.  The user confirms.
3.  Omnis downloads the plugin package (`.dart` or `.snapshot`).
4.  Omnis loads and activates it.

## 4.2 Update flow & the catalog

The Core periodically checks both the catalog and installed plugins for updates.

```text
PLUGIN MARKETPLACE
                      [...]
📦 UPDATE AVAILABLE
┌────────────────────────────────────────────────┐
│  📦 Metadata Plus (v1.3.0)   [Update Now] │
│  - Improves genre detection.                    │
└────────────────────────────────────────────────┘
```

## 4.3 Developer installation

For developers, Omnis should also support the power-user workflow from the spec:
installing directly from a public repo URL or a local cloned repo. This is the
ideal "hidden, power-user" path; the consumer-flow remains the marketplace.

---

# 5. Plugin contribution points — UI integration

Following the UI spec's `ExperienceGraph` model, plugins integrate into the UI without the Core
needing to know them statically.

* **Navigation** — a plugin can add an item to the sidebar (e.g., "Stats").
* **Home widgets** — a plugin can add a widget to home (e.g. "Recently played from friends," or
  "AI daily recommendation").
* **Now-playing areas** — a plugin can add a panel or overlay (e.g. audio waveform, analysis panel).
* **Context menus** — actions on right-click, long-press track/album.
* **Settings pages** — the plugin's generated settings page is automatically added under `Settings → Plugins`.

---

# 6. Developer & contribution workflow — the RuneLite model

Building the platform means a clear contribution workflow.

## 6.1 A single plugin's repository shape

```text
my-plugin/
├── lib/
│   ├── my_plugin.dart              # main class
│   ├── my_plugin_settings.dart      # Settings schema
│   ├── providers/                  # implements a capability
│   └── ui/                            # UI contributions
├── test/
├── pubspec.yaml
└── omnis_plugin.yaml              # for manifest
```

## 6.2 The plugin-hub repository

A meta-repository — a "hub" — stores **references** to plugin repos, not code.

**Shape:**

```text
omnis-plugin-hub/
├── plugins/
│   ├── metadata-plus.yaml            # a repo URL + commit hash
│   └── visualizer-fx.yaml
└── plugin-catalog.json            # generated catalog for the store
```

**`plugins/metadata-plus.yaml`**

```yaml
repository: https://github.com/MyCompany/metadata-plus.git
commit: 9db374fc205cae5f99bd127266f076ec40f8
```

**Workflow to test a new plugin is added:**

1.  A developer creates a plugin repo (shaped as above).
2.  The developer tests against the current Omnis API.
3.  The dev adds an `omnis_plugin.yaml` at the repo root.
4.  The dev opens a PR to `omnis-plugin-hub`.
5.  A reviewer checks the plugin code, is permissions etc. (RuneLite-style).
6.  The PR merge.
7.  Omnis Core pulls the new `plugin.json` into the catalog; the plugin is available in the store.

---

# 7. The "zero-config" rule for plugin settings

You have configured plugins to require **no setup**. That is the most important plugin UX rule:

**"Automatic first; fine-tune second"**

*   **No API keys:** a plugin uses a public, open service (e.g., LRCLIB for lyrics, MusicBrainz for metadata) by default. The user can set their own key but that's a power-user *fine-tune*, not a requirement.
*   **Sensible defaults:** if a plugin is an EQ, default to flat. If it is a sleep timer, default to 30 minutes.
*   **Some guidance:** if a plugin really does need the user to point to a URL or fill a token, the plugin must provide a guided "fix connection" flow rather than a bare input.

---

# Final implementation contract for the AI agent

> **The plugin system is built as a complete, integrated platform.**
>
> 1. **Core API:** the `PluginContext`, `PluginSettings`, and the Capability interfaces
>     have to be the **only** contract between the Core and any plugin.
> 2. **Isolation:** plugin calls are `async` and every failure is caught by
>     `PluginHealthCenter`/`PluginWatchdog`. No plugin can crash the app.
> 3. **Marketplace:** build an in-app marketplace that shows the catalog and
>     handles the install, update, remove flows.
> 4. **Dev experience:** add `plugin-hub` + the build pipeline to generate the
>     `catalog.json` from the plugin.yaml files, so contributing is fun.
>
> **Remember the RuneLite principle:** for the user it's invisible; and for the
> developer, contributing a new thing takes minutes, not hours.