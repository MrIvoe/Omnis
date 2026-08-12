# Plugin Security Model

What a plugin can and can't do, for anyone deciding whether to paste a
GitHub URL into the Plugins tab — and for anyone building a plugin who
wants to know what they're allowed to rely on.

## Two trust levels, matching the two kinds of plugin

### Bundled plugins (`lib/plugins/`) — fully trusted

Compiled into the app from this repository's own source. A bundled
plugin is exactly as trusted as any other file in the app — full Dart,
full Flutter, no sandbox, no permission system. If you're auditing what
Omnis itself can do, this is the code to read; it's reviewed the same way
any other change to the app is (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

### Downloaded plugins — sandboxed, permission-gated

Installed at runtime from a pasted GitHub URL (or `.zip`) and executed
via [`dart_eval`](https://pub.dev/packages/dart_eval), a real Dart
interpreter running against an **isolated `package:default`** — a
downloaded plugin's code:

- **Cannot import `package:omnis` or `dart:ui`.** It has no way to reach
  any Omnis class, the widget tree, or a real `BuildContext`. Every hook
  it implements receives and returns plain JSON-compatible values (Maps,
  Strings, numbers) — never a Flutter type, never an Omnis object.
- **Gets exactly the permissions its manifest declares, nothing more.**
  `omnis_plugin.yaml`'s `permissions:` list is the complete grant — today
  that's `storage`/`filesystem` (grants dart_eval's
  `FilesystemPermission.any`) and `network` (declarative only right now —
  see "Known gaps" below). A plugin that declares nothing gets neither.
- **Shows you what it's asking for before any of its code runs.** Pasting
  a URL downloads and parses the manifest first; a confirmation dialog
  (`PluginsPage._confirmPermissions`) lists every declared permission —
  explicitly, even "this plugin asks for nothing" — and only proceeds to
  compile and execute the entrypoint if you approve.
- **Can't take the app down.** Every hook call (`initialize`,
  `onTrackStart`, `onLibraryScan`, `uiSlot`, `enable`, `disable`,
  `dispose`) runs inside `PluginSandbox`, which catches any exception,
  logs it to the Plugin Health dashboard (Plugins tab), and moves on —
  music keeps playing.

## What "sandboxed" does *not* mean

Being realistic about the boundary matters more than the boundary itself
sounding impressive:

- **`FilesystemPermission.any` is all-or-nothing.** dart_eval has no
  per-directory scoping at this layer — a plugin that declares `storage`
  gets broad file access, not read-only-to-its-own-folder. Only grant it
  to a plugin you'd trust with your filesystem generally.
- **A time budget on a hook call, with a real limit to what it can catch.**
  `PluginSandbox.run` now wraps every hook call in `Future.timeout()` (8s
  default, configurable per call, see `PluginSandbox.defaultTimeout`) —
  a plugin with a stuck `await` (a hung network call, a Future that never
  completes) is abandoned and logged to Plugin Health instead of hanging
  the caller forever. This does **not** cover a plugin with a tight
  synchronous loop that never yields — `dart_eval` runs on the same
  thread as the call, so non-async CPU-bound guest code can still block
  that thread until it returns on its own. Closing that remaining gap
  would need the interpreter moved to its own isolate; worth doing before
  a security-sensitive deployment, and a reasonable thing to contribute.
- **`network` permission isn't currently enforced separately from
  everything else** — dart_eval's sandbox restricts imports, not
  outbound socket calls a plugin might reach through whatever's
  available in its restricted environment. Treat the permission list as
  disclosure (what the author says the plugin does), not as a hard
  technical guarantee for network access specifically, the way
  `storage`'s `FilesystemPermission.any` grant actually is enforced.
- **No plugin registry or curation today.** Installing means trusting
  whoever's GitHub URL you pasted, same as installing any other
  unreviewed code from the internet. There's no built-in "verified
  publisher" list, checksum pinning, or update-integrity check — a
  plugin's author can push different code to the same URL later, and
  reinstalling would silently pull the new version. If you're
  distributing Omnis more broadly, a curated index (even a simple
  community-maintained JSON list of known-good repos) is worth building
  before pointing non-technical users at "paste any URL."

## Practical guidance

- Only install a downloaded plugin from a source you'd trust with the
  permissions it declares — the dialog tells you what it's asking for;
  reading it is the actual security boundary, not just a formality to
  click past.
- Prefer a plugin that declares fewer permissions when you have a
  choice; `storage` in particular is a broad grant.
- If a plugin misbehaves, disable or uninstall it from the Plugins tab —
  this immediately calls its `disable()`/hooks stop firing, no restart
  required — and check the Plugin Health dashboard for what it was doing
  when it failed.
- Building a plugin yourself and want it to stay within a tighter
  boundary than "full filesystem access"? Don't declare `storage` unless
  you actually need file I/O — most plugins only need `PluginStorage`
  (bundled plugins) or their own hook-return values (downloaded plugins),
  neither of which requires the broad grant.

See [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md) for how to build a plugin and
[ARCHITECTURE.md](ARCHITECTURE.md) for how the sandbox fits into the rest
of the kernel.
