import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugins/tag_editor_plugin.dart';
import 'package:path_provider/path_provider.dart';

/// Fast music scanner.
///
/// On Android this queries the MediaStore via `on_audio_query`, which is
/// pre-indexed by the OS — scanning thousands of tracks is nearly instant.
/// On desktop it falls back to a recursive filesystem walk (which is fast
/// enough because desktop storage is usually a dedicated Music folder).
class MediaScanner {
  MediaScanner._({Stream<FileSystemEntity> Function(Directory)? lister})
      : _lister =
            lister ?? ((dir) => dir.list(recursive: true, followLinks: false));

  static final MediaScanner instance = MediaScanner._();

  /// Constructs an independent instance with an injectable directory
  /// lister, bypassing [instance]'s singleton — the same
  /// constructor-injection pattern `MetadataEnrichmentPlugin(client: ...)`
  /// uses for its `http.Client`. Lets a test simulate a stream that
  /// errors partway through without needing a real unreadable directory
  /// (permission semantics differ too much across platforms/CI to fake
  /// that reliably any other way).
  @visibleForTesting
  factory MediaScanner.forTesting({
    required Stream<FileSystemEntity> Function(Directory) lister,
  }) =>
      MediaScanner._(lister: lister);

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final Stream<FileSystemEntity> Function(Directory) _lister;

  /// Scan the user's music library as fast as possible.
  ///
  /// [knownTracks] is the caller's already-persisted library (if any) —
  /// on the filesystem-walk path (desktop/iOS), a file whose path and
  /// mtime still match an entry here is reused as-is instead of having
  /// its tags re-read, which is what makes a repeat scan of a large,
  /// mostly-unchanged library fast. The Android path ignores it (the
  /// MediaStore query is already effectively instant either way).
  ///
  /// Returns tracks sorted by title. Queries are capped at [limit] tracks.
  Future<List<BaseTrack>> scanLibrary({
    int limit = 1000,
    List<BaseTrack> knownTracks = const [],
  }) async {
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
        : await _scanFilesystem(limit: limit, knownTracks: knownTracks);
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
        // Real "date added to this device" from the OS's own index — free,
        // no bookkeeping needed the way the filesystem-walk path requires.
        dateAdded: song.dateAdded != null
            ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000)
            : null,
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
  Future<List<BaseTrack>> _scanFilesystem({
    required int limit,
    List<BaseTrack> knownTracks = const [],
  }) async {
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
    final files = <File>[];
    // A blanket try/catch around the whole `await for` below used to mean
    // one bad entry (permission denied, a broken symlink, removable
    // storage unmounting mid-scan) threw out of the loop entirely —
    // everything the walk hadn't reached yet was silently never seen, no
    // crash, no signal, just a truncated library. `handleError` catches
    // the error *as a stream event* instead, which lets `await for` keep
    // consuming whatever the stream still has to offer after it, rather
    // than propagating the error into (and terminating) the loop.
    var skippedCount = 0;
    await for (final entity in _lister(root).handleError((Object error) {
      skippedCount++;
      debugPrint('Omnis: skipped an unreadable path during library scan: $error');
    })) {
      if (files.length >= limit) break;
      final fileName = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      if (entity is File &&
          fileName.isNotEmpty &&
          !fileName.startsWith('.') &&
          extensions.contains(entity.path.split('.').last.toLowerCase())) {
        files.add(entity);
      }
    }
    if (skippedCount > 0) {
      debugPrint(
          'Omnis: library scan completed with $skippedCount skipped path(s).');
    }

    // Reading and ID3-decoding each file used to happen one at a time —
    // every file waited for the previous one's disk read to finish before
    // starting its own, even though these are independent, I/O-bound
    // operations with nothing to serialize on. Processing in concurrent
    // batches lets the OS/disk actually overlap those reads instead of
    // going strictly file-by-file, which is what made scanning a real
    // (thousands-of-files) desktop library feel slow. The batch size
    // caps how many files are open at once rather than firing all of
    // them at the OS simultaneously for a very large library.
    const batchSize = 32;
    final knownByPath = <String, BaseTrack>{
      for (final t in knownTracks)
        if (t.localPath != null) t.localPath!: t,
    };
    final tracks = <BaseTrack>[];
    for (var i = 0; i < files.length; i += batchSize) {
      final batch = files.skip(i).take(batchSize);
      final results = await Future.wait(
        batch.map((file) => _trackForFile(file, tagEditor, knownByPath)),
      );
      tracks.addAll(results.whereType<BaseTrack>());
    }
    return tracks;
  }

  /// A cheap mtime stat, compared against [knownByPath]'s cached entry for
  /// this same path — an unchanged file reuses its previous scan's
  /// [BaseTrack] outright, skipping the expensive ID3 tag decode entirely.
  /// This is what makes a repeat scan of a large, mostly-unchanged library
  /// fast: only new or actually-modified files pay [_trackFromFile]'s
  /// cost.
  ///
  /// Returns `null` (never throws) if the file becomes unreadable between
  /// being listed and being read here — a deleted file, or removable
  /// storage that unmounted mid-scan. Before this, `file.lastModified()`
  /// throwing here propagated out of the `Future.wait` batch in
  /// [_scanFilesystem] and aborted the *entire* scan, discarding every
  /// track already found — the same "one bad entry breaks everything"
  /// failure mode the directory-listing stream's `handleError` above
  /// already guards against, just one step later in the pipeline.
  Future<BaseTrack?> _trackForFile(
    File file,
    TagEditorPlugin tagEditor,
    Map<String, BaseTrack> knownByPath,
  ) async {
    try {
      final mtime = await file.lastModified();
      final known = knownByPath[file.path];
      if (known != null && known.fileModifiedAt == mtime) {
        return known;
      }
      return await _trackFromFile(file, tagEditor, mtime: mtime);
    } catch (e) {
      debugPrint(
          'Omnis: skipped "${file.path}" during scan — became unreadable: $e');
      return null;
    }
  }

  /// Builds a [BaseTrack] for one local file, preferring real embedded
  /// tags over filename-derived guesses wherever a tag is actually
  /// present. A completely untagged file still falls back to the filename
  /// (title) and "Unknown Artist"/"Unknown Album", same as before.
  Future<BaseTrack> _trackFromFile(
    File file,
    TagEditorPlugin tagEditor, {
    required DateTime mtime,
  }) async {
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
    final rawAlbumArtist = tags.albumArtist?.trim();

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
      // Real data when present — the standard TPE2 frame or a
      // TXXX:ALBUMARTIST custom field (see TrackTags.albumArtist).
      // `null`, not empty-string, when absent: BaseTrack.albumArtist
      // documents null as "unknown, fall back to artists.first."
      albumArtist: (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty)
          ? rawAlbumArtist
          : null,
      fileModifiedAt: mtime,
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
