 # Omnis
 
+[![CI](https://github.com/MrIvoe/Omnis/actions/workflows/ci.yml/badge.svg)](https://github.com/MrIvoe/Omnis/actions/workflows/ci.yml)
+[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
+[![Site](https://img.shields.io/badge/site-mrivoe.github.io%2FOmnis-3DDCC4)](https://mrivoe.github.io/Omnis/)
+[![Wiki](https://img.shields.io/badge/docs-wiki-A78BFA)](https://github.com/MrIvoe/Omnis/wiki)
+
 A micro-kernel music player with a hot-swappable plugin ecosystem. The
 Core stays small and never crashes; every feature — equalizer, lyrics,
 scrobbling, smart playlists, tag editing, Spotify/YouTube integration —
@@ -58,6 +63,10 @@ lives in a plugin.
 
 ## Documentation
 
+- **[Wiki](https://github.com/MrIvoe/Omnis/wiki)** — the long-form guide:
+  architecture walkthrough, writing your first plugin end-to-end, the
+  theme/layout YAML reference, and an honestly-labeled roadmap. Start
+  here if you're new.
 - **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the micro-kernel
   is put together and why: the Core/plugin split, `ServiceRegistry`/
   `EventBus`, `PluginContext`/`PluginStorage`, player layouts, and an
