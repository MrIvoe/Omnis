import 'dart:async';

import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// A lightweight scrobbling plugin that records recently played tracks.
class ScrobblePlugin extends MusicPlugin {
  final List<String> _history = [];

  List<String> get history => List.unmodifiable(_history);

  @override
  String get id => 'scrobble';

  @override
  String get name => 'Scrobble';

  @override
  String get description => 'Records recently played tracks for a future sync layer.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onTrackStart(BaseTrack track) async {
    _history.add('${track.title} • ${track.artists.join(", ")}');
    if (_history.length > 10) {
      _history.removeAt(0);
    }
  }

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  dynamic uiSlot(String locationID) => null;

  @override
  Future<void> dispose() async {}
}
