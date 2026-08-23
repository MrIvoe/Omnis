// `CustomTagKeys`/`TagFrame`/`TrackTags` — the value types `ITagWriter`'s
// `readTags` returns — live in `omnis_plugin_api`; see
// `packages/omnis_plugin_api/lib/track_tags.dart` for the real
// definitions. Re-exported here so app code importing `ITagWriter` via
// `package:omnis/plugin_api/service_interfaces.dart` can pull its return
// type from the same `omnis/plugin_api/...` path, matching every other
// interface-associated value type in this directory (`AudioAnalysisResult`,
// `EnrichmentResult`, `PlayRecord`, `LyricLine`, ...).
export 'package:omnis_plugin_api/track_tags.dart';
