# Community Plugins

A list of downloadable plugins built by the community — install by
copying the **Repository URL** column, pasting it into the Plugins tab,
and reviewing the permission dialog before confirming.

This list is curation-by-listing, not a security review. Being listed
here means a maintainer checked that the repo has a valid
`omnis_plugin.yaml` and that its declared permissions match what the
code does at the time it was listed — it is **not** an ongoing
guarantee, an audit, or an endorsement of the code's quality. Read
[docs/PLUGIN_SECURITY.md](PLUGIN_SECURITY.md) before installing
anything, bundled or downloaded. An author can push different code to
the same URL after being listed; reinstalling always pulls whatever is
at that URL right now.

## Bundled plugins (ship with Omnis, fully trusted)

These aren't installed separately — they're compiled into the app from
[Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) and enabled
from the Plugins tab. See that repo's README for the current list
(equalizer, lyrics, scrobbling, smart playlists, tag editing, Spotify/
YouTube integration, and more).

## Downloadable community plugins

| Name | Repository | What it does | Declared permissions |
|------|------------|---------------|----------------------|
| _(none listed yet — be the first)_ | | | |

## Getting your plugin listed

1. Make sure your repo has a working `omnis_plugin.yaml` at its root —
   see [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md) if you haven't built a plugin
   before.
2. Open an issue using the **Submit a plugin to the community list**
   template (in the Omnis repo's issue tracker) — it walks through what's
   needed.
3. A maintainer checks the manifest and declared permissions against
   the code, then adds a row to the table above via PR.

## Removal

A listing is removed if the repository disappears, stops working
against a current Omnis build, or its declared permissions stop
matching its actual behavior. Report a stale or misbehaving listing the
same way you'd report a bug — open an issue.
