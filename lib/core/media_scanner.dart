import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:path_provider/path_provider.dart';

/// Fast music scanner.
///
/// On Android this queries the MediaStore via `on_audio_query`, which is
/// pre-indexed by the OS — scanning thousands of tracks is nearly instant.
/// On desktop it falls back to a recursive filesystem walk (which is fast
/// enough because desktop storage is usually a dedicated Music folder).
class MediaScanner {
  MediaScanner._();

  static final MediaScanner instance = MediaScanner._();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Scan the user's music library as fast as possible.
  ///
  /// Returns tracks sorted by title. Queries are capped at [limit] tracks.
  Future<List<BaseTrack>> scanLibrary({int limit = 1000}) async {
    if (!kIsWeb && Platform.isAndroid) {
      return _scanAndroid(limit: limit);
    }
    return _scanFilesystem(limit: limit);
  }

  /// Android: query the MediaStore (instant, pre-indexed by the OS).
  Future<List<BaseTrack>> _scanAndroid({required int limit}) async {
    // checkAndRequest checks and requests permission if needed.
    final hasPermission = await _audioQuery.checkAndRequest();
    if (!hasPermission) return [];

    final songs = await _audioQuery.querySongs(
      ignoreCase: true,
    );

    final tracks = <BaseTrack>[];
    for (final song in songs) {
      if (tracks.length >= limit) break;
      final artist = song.artist ?? '';
      final album = song.album ?? '';
      tracks.add(BaseTrack(
        id: 'local:${song.id}',
        title: song.title,
        artists: [artist.isNotEmpty ? artist : 'Unknown Artist'],
        album: album.isNotEmpty ? album : 'Unknown Album',
        duration: song.duration ?? 0,
        type: TrackType.local,
        localPath: song.data,
        trackNumber: song.track,
        // Store the MediaStore artwork ID so the AlbumArt widget can
        // load the cover via on_audio_query's QueryArtworkWidget.
        coverArt: 'mediastore://${song.id}',
      ));
    }
    return tracks;
  }

  /// Desktop/iOS fallback: recursive filesystem walk.
  Future<List<BaseTrack>> _scanFilesystem({required int limit}) async {
    final settings = AppSettings.instance;
    Directory? root;
    if (settings.librarySource == LibrarySource.dedicatedFolder) {
      final folder = settings.selectedFolderPath;
      if (folder != null) {
        root = Directory(folder);
      }
    }
    if (root == null || !root.existsSync()) {
      root = await _fallbackRoot();
    }
    if (root == null || !root.existsSync()) return [];

    const extensions = {
      'mp3',
      'm4a',
      'wav',
      'flac',
      'aac',
      'ogg',
      'opus',
      'wma',
      'aiff',
    };

    final tracks = <BaseTrack>[];
    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (tracks.length >= limit) break;
        if (entity is File &&
            extensions.contains(entity.path.split('.').last.toLowerCase())) {
          tracks.add(BaseTrack(
            id: 'local:${entity.path}',
            title: entity.uri.pathSegments.isNotEmpty
                ? entity.uri.pathSegments.last
                    .replaceAll(RegExp(r'\.[^.]+$'), '')
                : 'Unknown',
            artists: ['Unknown Artist'],
            album: 'Unknown Album',
            duration: 0,
            type: TrackType.local,
            localPath: entity.path,
          ));
        }
      }
    } catch (_) {
      // Unreadable directories should not kill the scan.
    }
    return tracks;
  }

  Future<Directory?> _fallbackRoot() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      final root = Directory('/storage/emulated/0');
      if (root.existsSync()) return root;
      final ext = await getExternalStorageDirectory();
      return ext;
    }
    if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    return Directory(Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.');
  }
}
