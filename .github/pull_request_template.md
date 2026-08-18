## What does this PR do, and why?

<!-- The "why" matters more than the "what" — the diff already shows what changed. -->

## Checklist

- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes, including new tests for anything this PR adds
- [ ] **Does this belong in this repo at all, or as a plugin in
      [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins)?** The
      kernel (`lib/core/`) never imports a concrete plugin — if this PR
      adds a feature rather than fixing this repo's own kernel/UI, it
      almost certainly belongs as a plugin in the separate Omnis-Plugins
      repo, reaching the Core only through `PluginContext`/
      `PluginStorage`/`ServiceRegistry`/`EventBus`. See
      [CONTRIBUTING.md](../CONTRIBUTING.md#the-one-rule-that-shapes-everything-else)
      if you're not sure.
- [ ] If this touches a plugin's persisted state, it goes through that
      plugin's own `PluginStorage` — not a new `AppSettings` key.
- [ ] Any network call fails soft (returns an empty/default result) —
      never throws out to the UI.

## Testing

<!-- How did you verify this? Manual steps, screenshots for UI changes, etc. -->
