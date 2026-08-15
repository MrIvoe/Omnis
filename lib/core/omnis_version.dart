/// The running Omnis core version, compared against a plugin manifest's
/// `min_omnis_version:` (`PluginManifest.minOmnisVersion`) at install
/// time — item 26's other named gap: this field was parsed but never
/// read anywhere.
///
/// Kept as a manually-maintained constant rather than read from
/// `pubspec.yaml` at runtime (which would need a new dependency,
/// `package_info_plus`, just for this one narrow check) — must be kept
/// in sync with `pubspec.yaml`'s own `version:` field by hand.
const String omnisCoreVersion = '0.1.0';
