// The capability interfaces (`ILyricsProvider`, `IPlayHistoryProvider`,
// `IQueueBuilder`, `IMetadataProvider`, `IAudioAnalysisProvider`,
// `IFileTagWriter`, `IVisualizerProvider`) moved to `omnis_plugin_api` —
// see `packages/omnis_plugin_api/lib/service_interfaces.dart` for the
// real definitions. Re-exported from their original path so every
// existing `import 'package:omnis/plugin_api/service_interfaces.dart'`
// in this app keeps working unchanged.
export 'package:omnis_plugin_api/service_interfaces.dart';
