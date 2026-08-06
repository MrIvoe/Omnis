# Contributing to Omnis

Thanks for considering contributing. This document is the short version;
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) is the long version of *why*
the codebase is shaped the way it is, and
[docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md) is the how-to for the most
common kind of contribution — a new plugin.

## The one rule that shapes everything else

**`lib/core/` never imports a concrete plugin.** Every feature —
equalizer, lyrics, scrobbling, smart playlists, tag editing, streaming
integrations — lives in `lib/plugins/`. If you're adding a feature and
find yourself editing `lib/core/`, stop and ask: does this genuinely need
to be core, or does it belong behind the capabilities the Core already
exposes (`PluginContext`, `PluginStorage`, `ServiceRegistry`, `EventBus`)?

The design rule behind that: **could someone reasonably want to replace
this with a different implementation?** If yes, it belongs behind a
plugin (or an interface, for something other code needs to discover
generically). If there's genuinely only one sensible way to implement
something, a plain concrete plugin with no interface is the right call —
don't add abstraction that provides no practical value.

## Before you start

- **Small fix or obvious bug?** Just open a PR.
- **New plugin?** Read [docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md) —
  it covers the full `MusicPlugin` lifecycle, `PluginContext`,
  `PluginStorage`, `uiSlot`, and testing patterns, with a real working
  example at [`example/example_plugin.dart`](example/example_plugin.dart).
- **New Now Playing layout?** See
  [docs/ARCHITECTURE.md#player-layouts-libuiplayer_layouts](docs/ARCHITECTURE.md#player-layouts-libuiplayer_layouts).
- **Something bigger** (a new interface, a change to `ServiceRegistry`/
  `EventBus`, anything touching `lib/core/`)? Consider opening an issue
  first to discuss the approach — these are the parts of the codebase
  meant to change rarely, so it's worth checking the shape before writing
  a lot of code against it.

## Development workflow

1. Fork and clone; see [docs/BUILDING.md](docs/BUILDING.md) for setup.
2. Make your change.
3. Before opening a PR, both of these must pass clean:

   ```bash
   flutter analyze
   flutter test
   ```

   A new plugin or feature should come with tests, not just compile —
   this codebase treats "verify before building on top of an assumption"
   as a hard rule, not a nice-to-have (`test/id3_codec_safety_test.dart`
   exists specifically because a third-party library's write path was
   *assumed* to work and didn't). Mock HTTP with `package:http/testing.dart`
   rather than hitting real network in tests; seed
   `SharedPreferences.setMockInitialValues({})` in `setUp()` for anything
   touching `PluginStorage`/`AppSettings` (skipping this is a common,
   easy-to-hit mistake that hangs a widget test for its full timeout
   instead of failing fast).
4. Keep commits focused; write commit messages that explain *why*, not
   just what changed — the diff already shows what changed.

## Code style

- Follow the patterns already in the file you're editing before
  introducing a new one. This codebase has strong, consistent
  conventions (the read/write capability split for interfaces, the
  "every plugin owns its own `PluginStorage`, never touches `AppSettings`"
  rule, the "fail soft, never throw, out of a network call" contract) —
  matching them matters more than any individual line of code.
- Comments explain *why*, not *what* — a hidden constraint, a workaround
  for a specific bug, something that would surprise a reader. Don't
  narrate what well-named code already shows.
- No abstraction without a real, current use case. Three similar lines
  beat a premature shared helper.

## Reporting bugs / requesting features

Open a GitHub issue. For a bug, include:
- What you expected vs. what happened
- Platform (Android/Windows/etc.) and Flutter version (`flutter --version`)
- Steps to reproduce, if you have them

For a feature request, a concrete use case is more useful than a
description of the feature itself — it's easier to evaluate "I want to
do X" against the plugin-vs-core design rule above than an abstract ask.

## Conduct

Be respectful and assume good faith. Disagreements about architecture or
approach are normal and welcome — keep them focused on the work, not the
person.
