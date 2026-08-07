// `BaseTrack` moved to `omnis_plugin_api` so both the app and
// `omnis_plugins` (the bundled-plugin package, hosted in the
// `Omnis-Plugins` repo) can depend on it without a circular package
// dependency — see `packages/omnis_plugin_api/lib/base_track.dart` for
// the real definition. Re-exported from its original path so every
// existing `import 'package:omnis/core/base_track.dart'` in this app
// keeps working unchanged.
export 'package:omnis_plugin_api/base_track.dart';
