import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/plugins/tag_editor_plugin.dart';
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
    // This used to only be checked at the library_page.dart call site,
    // which meant the guard only held because there was exactly one
    // caller. Enforcing it here means any future caller (auto-refresh, a
    // rescan button elsewhere, a plugin hook) can't accidentally bypass
    // the user's "don't scan my files" choice.
    if (AppSettings.instance.librarySource == LibrarySource.none) {
      return [];
    }
    final tracks = (!kIsWeb && Platform.isAndroid)
        ? await _scanAndroid(limit: limit)
        : await _scanFilesystem(limit: limit);
    // The doc comment above has always promised "sorted by title" but
    // neither scan path actually sorted before returning.
    tracks.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return tracks;
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
      // MediaStore surfaces the file's embedded genre tag for free — no
      // network call, no API key. This used to be read and then silently
      // discarded (BaseTrack.genres defaulted to empty for every scanned
      // track), which is why SmartPlaylistPlugin's mood/genre matching
      // never had anything to match against for a real local library.
      final genre = song.genre;
      tracks.add(BaseTrack(
        id: 'local:${song.id}',
        title: song.title,
        artists: [artist.isNotEmpty ? artist : 'Unknown Artist'],
        album: album.isNotEmpty ? album : 'Unknown Album',
        // MediaStore reports DURATION in milliseconds, but BaseTrack.duration
        // is seconds everywhere else in the app (the library JSON, the tests,
        // the media notification). Storing raw milliseconds here made every
        // scanned track claim a duration ~1000x too large.
        duration: ((song.duration ?? 0) / 1000).round(),
        type: TrackType.local,
        localPath: song.data,
        trackNumber: song.track,
        genres: (genre != null && genre.isNotEmpty) ? [genre] : const [],
        // Store the MediaStore artwork ID so the AlbumArt widget can
        // load the cover via on_audio_query's QueryArtworkWidget.
        coverArt: 'mediastore://${song.id}',
      ));
    }
    return tracks;
  }

  /// Desktop/iOS fallback: recursive filesystem walk.
  ///
  /// Unlike the Android path (pre-indexed by the OS MediaStore), nothing
  /// here already knows the artist/album/genre for these files — so each
  /// one is read for its real embedded ID3 tags via [TagEditorPlugin]
  /// rather than being stored as a permanent "Unknown Artist" placeholder.
  /// Artwork bytes are deliberately *not* extracted here
  /// (`includeArtwork: false`): decoding every embedded picture during a
  /// bulk scan would slow it down and bloat the persisted library JSON for
  /// no benefit — `TrackArtwork` reads artwork lazily, per-file, only for
  /// what's actually on screen.
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

    final tagEditor = TagEditorPlugin();
    final tracks = <BaseTrack>[];
    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (tracks.length >= limit) break;
        final fileName = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (entity is File &&
            fileName.isNotEmpty &&
            !fileName.startsWith('.') &&
            extensions.contains(entity.path.split('.').last.toLowerCase())) {
          tracks.add(await _trackFromFile(entity, tagEditor));
        }
      }
    } catch (_) {
      // Unreadable directories should not kill the scan.
    }
    return tracks;
  }

  /// Builds a [BaseTrack] for one local file, preferring real embedded
  /// tags over filename-derived guesses wherever a tag is actually
  /// present. A completely untagged file still falls back to the filename
  /// (title) and "Unknown Artist"/"Unknown Album", same as before.
  Future<BaseTrack> _trackFromFile(File file, TagEditorPlugin tagEditor) async {
    final fallbackTitle = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '')
        : 'Unknown';

    final tags = await tagEditor.readTags(file.path, includeArtwork: false);

    final rawArtist = tags.artist?.trim() ?? '';
    final artists = rawArtist.isEmpty
        ? const ['Unknown Artist']
        : tagEditor.splitArtists(rawArtist);

    final title =
        (tags.title != null && tags.title!.trim().isNotEmpty)
            ? tags.title!.trim()
            : fallbackTitle;
    final album =
        (tags.album != null && tags.album!.trim().isNotEmpty)
            ? tags.album!.trim()
            : 'Unknown Album';
    final genre = tags.genre?.trim();
    final year = int.tryParse((tags.year ?? '').trim());
    final trackNumber = int.tryParse((tags.track ?? '').trim());
    final discNumber = int.tryParse((tags.disc ?? '').trim());

    return BaseTrack(
      id: 'local:${file.path}',
      title: title,
      artists: artists.isEmpty ? const ['Unknown Artist'] : artists,
      album: album,
      duration: 0,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      genres: (genre != null && genre.isNotEmpty) ? [genre] : const [],
      type: TrackType.local,
      localPath: file.path,
      // Picked up for free from the same tag read above (no extra file
      // I/O) — this is the only thing that ever populates
      // BaseTrack.replayGain, which is what actually makes
      // ReplayGainPlugin's gain contribution non-1.0 for anything. Only
      // present when the file was already tagged by an external
      // ReplayGain scanner (mp3gain, foobar2000, ...); Omnis doesn't
      // compute loudness itself.
      replayGain: tags.replayGainValues,
    );
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
