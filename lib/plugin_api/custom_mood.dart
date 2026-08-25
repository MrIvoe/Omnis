// `CustomMood`/`CustomMoodIcon` — the value type `IMoodPlayer`'s
// `playCustomMood`/`customMoods` accept and return — live in
// `omnis_plugin_api`; see `packages/omnis_plugin_api/lib/custom_mood.dart`
// for the real definitions. Re-exported here so app code importing
// `IMoodPlayer` via `package:omnis/plugin_api/service_interfaces.dart`
// can pull its parameter type from the same `omnis/plugin_api/...` path,
// matching every other interface-associated value type in this directory
// (`AudioAnalysisResult`, `EnrichmentResult`, `PlayRecord`, `LyricLine`,
// `TrackTags`, ...).
//
// This replaces the app's own `lib/core/custom_mood.dart`, which Tier 2
// task 4 removed when the Moods cluster moved into `MoodsPlugin`. Only
// the value type moved here — `CustomMoodStore`, which persists custom
// moods, is plugin-private state and now lives in the `omnis_plugins`
// package next to the Moods page that owns it.
export 'package:omnis_plugin_api/custom_mood.dart';
