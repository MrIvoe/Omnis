# Cutting a release

## Platform status

Only Android and Windows are built and published right now.

- **iOS / macOS** — blocked on enrolling in the Apple Developer
  Program (paid, identity-verified) — without it there's no way to
  install a build on a real device or distribute a beta at all.
- **Linux / Web** — no platform folder exists yet, and at least one
  dependency (`just_waveform`) has no Linux/Web support, so this needs
  a real per-feature compatibility pass before it's worth building, not
  just `flutter create --platforms=...`.

Both are tracked as future work, not part of this release pipeline
yet.

How a version gets from a commit on `main` to a downloadable beta on
the [Releases page](https://github.com/MrIvoe/Omnis/releases).
`.github/workflows/release.yml` does the build/publish automatically —
this doc covers the one-time keystore setup and the every-release tag
flow.

## One-time setup: Android signing keystore

Do this once, on your own machine. **The keystore file and its
passwords must never be committed or pasted into an AI assistant, an
issue, or a PR** — that's the same key every future update has to be
signed with; treat it like a password to your bank.

1. Generate the keystore:

   ```bash
   keytool -genkey -v -keystore omnis-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias omnis
   ```

   You'll be prompted for a store password, a key password, and some
   identity fields (name/org — anything reasonable works, they're not
   checked). **Back up `omnis-release.jks` and both passwords
   somewhere durable and private** (a password manager, an encrypted
   drive) — outside this repo. If you lose it, you can never publish
   an update under the same signing identity again; existing installs
   would need to be uninstalled and reinstalled from scratch.

2. Base64-encode it, for pasting into a GitHub secret:

   ```bash
   base64 -w0 omnis-release.jks > omnis-release.jks.b64
   ```

   (On Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("omnis-release.jks")) | Out-File omnis-release.jks.b64`)

3. In the repo on GitHub: **Settings → Secrets and variables → Actions
   → New repository secret**. Add all four:

   | Secret name | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | contents of `omnis-release.jks.b64` |
   | `ANDROID_KEYSTORE_PASSWORD` | the store password from step 1 |
   | `ANDROID_KEY_ALIAS` | `omnis` (or whatever alias you used) |
   | `ANDROID_KEY_PASSWORD` | the key password from step 1 |

4. Delete `omnis-release.jks.b64` locally once the secret is saved —
   it's no longer needed and is plain-text-encoded key material.

You only do this once. Every release after this reuses the same four
secrets.

### Building a signed release locally (optional)

If you want a release-signed APK on your own machine, without waiting
for CI: create `android/key.properties` (gitignored, never commit it)
pointing at your local keystore —

```properties
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=omnis
storeFile=<absolute-path-to-omnis-release.jks>
```

— then `flutter build apk --release` picks it up automatically
(`android/app/build.gradle` checks for this file and falls back to
debug signing when it's absent, so this step stays optional for
everyone else).

## Every release: cut a tag

1. Bump `version:` in `pubspec.yaml` (e.g. `0.1.0+1` → `0.2.0+2` — the
   part after `+` is the Android version code and must strictly
   increase every release).
2. Commit that as its own change, reviewed like anything else.
3. Tag it and push the tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

Pushing the tag triggers `.github/workflows/release.yml`, which builds
Android (APK + App Bundle, release-signed) and Windows (zipped release
build), then publishes both to a new pre-release GitHub Release named
after the tag, with auto-generated release notes from the commits
since the last tag.

No existing app-level tag convention predates this — `v0.1.0`-style
tags are for the app itself; the `plugin-api-vX.Y.Z` tags already in
this repo belong to `packages/omnis_plugin_api` and are unrelated.
