// `PluginDestination` lives in `omnis_plugin_api` — see
// `packages/omnis_plugin_api/lib/plugin_destination.dart` for the real
// definition. Re-exported here so app code imports it through the same
// `package:omnis/plugin_api/...` boundary every other shared contract in
// this directory already uses, rather than reaching past it into the
// package directly.
export 'package:omnis_plugin_api/plugin_destination.dart';
