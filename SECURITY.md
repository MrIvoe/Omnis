# Security Policy

This file is about **reporting a vulnerability**. If you want to
understand what a downloaded plugin can and can't do before you decide
whether to trust one, that's [docs/PLUGIN_SECURITY.md](docs/PLUGIN_SECURITY.md)
instead — it's a design document, not a reporting channel.

## Reporting a vulnerability

Please don't open a public issue for a security problem — that gives
anyone watching the repo a working exploit before there's a fix.

Instead, use GitHub's private reporting:

1. Go to the [Security tab](https://github.com/MrIvoe/Omnis/security)
   of this repository.
2. Click **Report a vulnerability** to open a private advisory.

If that's not available to you for some reason, contact the maintainer
directly through their GitHub profile
([@MrIvoe](https://github.com/MrIvoe)) and ask for a private channel to
share details.

Please include:
- What the issue is and why it's a security problem, not just a bug
- Steps to reproduce, or a proof of concept if you have one
- What you think the impact is (data exposure, code execution,
  permission bypass, etc.) and, if relevant, on which platform

## What counts as in scope

- The Core kernel (`lib/core/`) — anything that would let a downloaded
  plugin exceed the permissions it declared, escape the `dart_eval`
  sandbox, or reach `dart:ui`/`package:omnis` it shouldn't be able to.
- The plugin installer/downloader — path traversal, zip-slip, or
  arbitrary file write from a malicious plugin archive or manifest.
- Credential handling for streaming integrations (Spotify/YouTube
  OAuth tokens) — anywhere a token could leak to logs, disk in
  plaintext, or another plugin.
- Any of the bundled plugins in this repo or in
  [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins).

**Already-known, already-documented gaps are not new reports** — read
[docs/PLUGIN_SECURITY.md](docs/PLUGIN_SECURITY.md)'s "What sandboxed
does *not* mean" section first. Things like "a plugin with `storage`
gets broad filesystem access" or "there's no plugin registry/curation"
are known, disclosed trade-offs, not vulnerabilities to report — though
a concrete PR that narrows one of them is very welcome as a normal
contribution.

## Response

This is a small project maintained on personal time, not a company
with an SLA — there's no guaranteed response window. A private report
will get a reply acknowledging it, and a fix (or an explanation of why
it's not treated as a vulnerability) once it's been looked at. Credit
in the release notes if you'd like it; anonymous if you'd rather not.

## Supported versions

Omnis doesn't yet have a stable release line — `main` is the only
thing that receives fixes. If that changes (tagged releases with a
support window), this section will be updated to say which versions
get security fixes.
