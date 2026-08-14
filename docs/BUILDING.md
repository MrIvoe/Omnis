# Building Omnis

## Prerequisites

- **Flutter** — stable channel, matching the Dart SDK constraint in
  `pubspec.yaml` (`>=3.0.0 <4.0.0`). [Install Flutter](https://docs.flutter.dev/get-started/install)
  if you don't have it, then confirm your setup:

  ```bash
  flutter doctor
  ```

- **Android** builds need the Android SDK (installed via Android Studio)
  with `compileSdk 36` and NDK `27.0.12077973` available — `flutter
  doctor`/a failed Gradle sync will tell you if either is missing, and
  Android Studio's SDK Manager installs both. `android/app/build.gradle`
  pins both explicitly (higher than Flutter's own bundled defaults at the
  time this was written) because `flutter_web_auth_2` (Spotify/YouTube
  OAuth) and `webview_flutter_android` (YouTube's embedded player)
  require them; `android/settings.gradle` and
  `android/gradle/wrapper/gradle-wrapper.properties` are pinned to
  matching Android Gradle Plugin (8.9.1), Kotlin (2.1.0), and Gradle
  (8.11.1) versions for the same reason — this whole chain (compileSdk →
  AGP → Gradle → Kotlin) had to move together; bumping just one link
  produced a build error pointing at the next.
- **Windows desktop** builds need the Visual Studio Build Tools with the
  "Desktop development with C++" workload. `flutter doctor` checks for
  this too — but a green `flutter doctor` check isn't sufficient on its
  own: `flutter build windows` also needs the *specific* installed VS
  version to be one this Flutter SDK's CMake-generator detection
  recognizes. Confirmed on 2026-08-13 in the dev environment this repo
  was originally built in: `flutter doctor` reported Visual Studio
  fully green (Build Tools 2026, 18.3.x), but `flutter build windows`
  still failed —
  `CMake Error ... Generator "Visual Studio 16 2019" could not find any
  instance of Visual Studio` — because the pinned Flutter SDK there
  (3.27.4, January 2025) predates VS2026's existence and falls back to
  a hardcoded VS2019 generator string that doesn't match anything
  actually installed. Fix is a Flutter SDK upgrade (or a matching older
  VS install), neither of which this repo's own files can control —
  if you hit this exact CMake error, that's what's happening.
- **iOS/macOS**: this repository doesn't have an `ios/`/`macos/`
  platform folder yet (`flutter create --platforms=ios,macos .` would add
  one) — nothing here has been built or tested for those platforms.
- **Web**: not evaluated in this repo; `youtube_player_iframe`'s
  WebView-based approach behaves differently on web (an actual iframe,
  not a WebView), and hasn't been exercised here.

## Clone and install dependencies

```bash
git clone <your-fork-or-this-repo-url>
cd Omnis
flutter pub get
```

## Running

```bash
flutter devices        # see what's available
flutter run             # runs on the first available device
flutter run -d windows   # Windows desktop
flutter run -d <device-id>  # a specific Android device/emulator
```

First launch is intentionally fast: `main()` only waits on a single
`SharedPreferences` read before calling `runApp()`; the rest of the
bootstrap (audio engine, plugin manager, installed plugins, layouts) runs
behind `HomePage`'s own loading gate, after something is already on
screen. See [ARCHITECTURE.md](ARCHITECTURE.md#startup-speed).

### Real-device smoke testing (Android)

Confirmed working end-to-end on 2026-08-13 via a debug APK
(`flutter build apk --debug`) installed on the `Medium_Phone_API_36.1`
AVD (`flutter emulators --launch <id>`, then `adb install -r
build/app/outputs/flutter-apk/app-debug.apk`): onboarding renders, the
bottom nav shows all six tabs including the new Radio tab, and Radio's
"Top stations" list genuinely round-trips a live call to the real Radio
Browser API (real station names, real favicon images loading over the
network) — not a mock. `adb logcat -d "*:E" | grep <package>` showed
zero errors across the whole session. This is the first real-device
verification any UI work in this repo's history has had, as opposed to
`flutter analyze`/`flutter test` alone — Windows desktop (the only other
platform folder present) doesn't build in every environment; see the
Windows note above.

## Testing and static analysis

Run both before opening a PR — see [CONTRIBUTING.md](../CONTRIBUTING.md)
for the full checklist:

```bash
flutter analyze
flutter test
```

A handful of test files exercise real file I/O (ID3 tag round-trips) or
pump real widget trees, so the full suite takes longer than a typical
unit-test run — that's expected. If you're only touching one plugin,
`flutter test test/your_file_test.dart` is faster while iterating.

## Building release artifacts

```bash
# Android APK (unsigned/debug-signed by default — see "Signing" below)
flutter build apk --release

# Android App Bundle (what the Play Store wants)
flutter build appbundle --release

# Windows desktop (produces a folder under build/windows/, not an installer)
flutter build windows --release

# Web
flutter build web --release
```

### Signing an Android release

`flutter build apk --release` without any signing configuration produces
an APK signed with Flutter's own debug key — installable for testing,
**not** acceptable for the Play Store or for distributing to users as a
trusted update path. To sign with your own key:

1. Generate a keystore (once):

   ```bash
   keytool -genkey -v -keystore ~/omnis-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias omnis
   ```

2. Create `android/key.properties` (**do not commit this file** — it's
   already covered by `.gitignore`'s general secrets patterns, but double
   check before committing anything under `android/`):

   ```properties
   storePassword=<your-store-password>
   keyPassword=<your-key-password>
   keyAlias=omnis
   storeFile=<absolute-path-to-omnis-release.jks>
   ```

3. Wire it into `android/app/build.gradle`'s `signingConfigs`/
   `buildTypes.release` block — this repo doesn't include that wiring by
   default since it would otherwise require every contributor to have a
   keystore just to build a debug APK. See
   [Flutter's own signing guide](https://docs.flutter.dev/deployment/android#signing-the-app)
   for the exact Gradle snippet.

## Plugin catalog

Downloadable (non-bundled) plugins — the ones installed at runtime via
Plugins → paste a URL, not compiled into the app — live in their own repo,
[MrIvoe/Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins)
(`C:\Users\MrIvo\Github\Omnis-Plugins` locally), split out from this repo
so they version and publish independently of the app itself. Bundled
plugins (`lib/plugins/`) are unaffected — this only concerns the
`plugins_page.dart` install flow.

The Plugins page fetches the real, live `catalog.json` published at the
root of Omnis-Plugins (`PluginInstaller.fetchCatalog()`, added
2026-08-14) — no GitHub API call, no auth, just `raw.githubusercontent.com`
serving one small JSON file, the same lightweight approach update-checking
already used for a single manifest. **Publish a new `catalog.json` to
Omnis-Plugins whenever a plugin installable this way is added, renamed, or
removed** — this repo has nothing to edit for that anymore.
`officialPluginCatalog` in `lib/core/plugin_catalog.dart` is now only the
offline/fetch-failure fallback (shown if the catalog fetch fails — no
network, GitHub unreachable, a malformed response), not the source of
truth; keep it in sync with `catalog.json` as a last-resort safety net,
not a second list to maintain independently. A stale/removed catalog
entry still fails loudly at install time (missing `omnis_plugin.yaml` →
an error shown to the user), not silently.

## The Essentia companion service

Real BPM/key/mood audio analysis (`AudioAnalysisPlugin`) talks to a
separate Python service, not something this Flutter build produces.
See `tools/essentia_service/README.md` to build and deploy it — it's
optional; the plugin does nothing until you configure a service URL in
its own settings.

## Troubleshooting

- **`flutter_web_auth_2 requires Android SDK version 36 or higher`** — if
  you see this, your local Android SDK platform 36 isn't installed yet;
  open the SDK Manager in Android Studio and install it (the Gradle
  config already targets it, per the Prerequisites note above).
- **A widget test hangs for ~10 minutes then times out** — almost always
  a missing `SharedPreferences.setMockInitialValues({})` in that test's
  `setUp()`. Any plugin touching `PluginStorage` (which is most of them)
  needs it; see [PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md#testing-your-plugin).
