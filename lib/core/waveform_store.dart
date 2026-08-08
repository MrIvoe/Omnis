import 'dart:io';

import 'package:just_waveform/just_waveform.dart';
import 'package:omnis/core/base_track.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Computes and caches [Waveform] peak data for local tracks, for
/// `lib/ui/widgets/waveform_seek_bar.dart`.
///
/// `just_waveform` only ships native support for Android/iOS/macOS (see
/// pubspec.yaml's comment) and only ever works against a real local file.
/// Every path through [waveformFor] degrades to `null` instead of
/// throwing — a streaming track, an unsupported platform, a missing
/// plugin (a plain `flutter test` environment has no platform channel
/// registered), a missing/unreadable file, or extraction failure are all
/// the same signal to a caller: fall back to the plain slider.
class WaveformStore {
  Future<Directory> _root() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'waveforms'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// The cached or freshly-extracted waveform for [track], or `null` when
  /// one can't be produced.
  Future<Waveform?> waveformFor(BaseTrack track) async {
    final path = track.localPath;
    if (track.type != TrackType.local || path == null) return null;

    final audioFile = File(path);
    if (!await audioFile.exists()) return null;

    final int mtimeMs;
    try {
      mtimeMs = (await audioFile.lastModified()).millisecondsSinceEpoch;
    } catch (_) {
      return null;
    }

    final root = await _root();
    // Keyed by track id + source file mtime: a re-tagged/replaced file
    // gets a new filename here, so a stale cache is never read back. The
    // orphaned old file is just never touched again rather than swept up
    // eagerly — not worth a disk-listing pass for a cache that's small
    // (one file per track ever played) and self-healing on next extract.
    final cacheFile = File(
      p.join(root.path, '${_safeFileName(track.id)}_$mtimeMs.wave'),
    );

    if (await cacheFile.exists()) {
      try {
        return await JustWaveform.parse(cacheFile);
      } catch (_) {
        // Corrupt cache file — fall through to a fresh extraction rather
        // than permanently blocking this track's waveform.
      }
    }

    try {
      await for (final progress in JustWaveform.extract(
        audioInFile: audioFile,
        waveOutFile: cacheFile,
      )) {
        if (progress.waveform != null) return progress.waveform;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _safeFileName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
