// Sample Omnis plugin: logs track starts to the console.
//
// Install via the Plugins tab by pasting a GitHub URL that contains
// this file plus an `omnis_plugin.yaml` manifest.

dynamic createPlugin(dynamic api) {
  return {
    'id': 'sample_logger',
    'name': 'Sample Logger',
    'description': 'Logs track starts to the console',
    'version': '1.0.0',
    'author': 'Omnis Team',
    'hooks': ['onTrackStart', 'onLibraryScan'],
  };
}

/// Called when a track starts playing.
/// [track] is a JSON Map with title, artists, album, etc.
dynamic onTrackStart(dynamic track) {
  // In a real plugin you'd fetch lyrics, scrobble, etc.
  // Here we just return a confirmation string.
  return 'logged';
}

/// Called once per file during a library scan.
/// [file] is the file path as a String.
dynamic onLibraryScan(dynamic file) {
  return 'scanned';
}
