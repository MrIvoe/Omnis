import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A cheap, content-based identity for a local audio file — item 5's "no
/// fingerprint-based track identity" gap. Real bug this closes: every
/// scanned local track's id is `local:${file.path}` (see
/// `media_scanner.dart`'s `_trackFromFile`/`_scanAndroid`), so renaming or
/// moving a file gives it a brand-new id on the next scan. Since
/// favorites/ratings/play history/playlist membership are all keyed by
/// track id, a rename previously meant: the old id vanishes from the
/// library (its file no longer exists at the old path), a "new" track
/// appears with zero history, and everything that referenced the old id
/// is silently orphaned. This fingerprint lets a rescan recognize "this
/// is the same file that used to live somewhere else" and keep the old id
/// — see `LibraryPage._pickAndAdd`'s reconciliation step, which is the
/// only caller.
///
/// Hashes the file's size plus its first and last 64 KB (falling back to
/// the whole file when it's smaller than that) rather than the entire
/// file — full-file hashing would make rescanning a library of large
/// lossless FLACs noticeably slower for a signal that doesn't need every
/// byte: a rename/move never touches file content, so a large sample from
/// each end is already enough to distinguish real content changes (a
/// re-encode, a retagged copy that rewrote audio frames) from an
/// unrelated file that merely happens to be the same size. Returns `null`
/// (never throws) for a file that's unreadable or disappears between
/// being listed and being read — the same "a bad entry is skipped, not a
/// crash" contract `MediaScanner._trackForFile` already established.
Future<String?> computeFileFingerprint(String path) async {
  const sampleSize = 65536;
  RandomAccessFile? raf;
  try {
    final file = File(path);
    final length = await file.length();
    if (length <= 0) return null;
    raf = await file.open();
    final head = await raf.read(length < sampleSize ? length : sampleSize);
    // May overlap the head region for a file between one and two sample
    // sizes long — harmless (the overlapping bytes just get hashed
    // twice), and simpler than special-casing that range separately.
    var tail = Uint8List(0);
    if (length > sampleSize) {
      final tailStart = length - sampleSize;
      await raf.setPosition(tailStart);
      tail = Uint8List.fromList(await raf.read(length - tailStart));
    }
    final digest = sha256.convert([
      ...head,
      ...tail,
      ...length.toString().codeUnits,
    ]);
    return digest.toString();
  } catch (_) {
    return null;
  } finally {
    try {
      await raf?.close();
    } catch (_) {}
  }
}
