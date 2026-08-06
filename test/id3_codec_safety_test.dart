import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:id3_codec/id3_codec.dart';

/// This is not a test of Omnis code — it's a safety/shape check on the
/// third-party `id3_codec` package's real behavior, run before anything in
/// the app is built on top of an assumption about it. Two real findings
/// came out of writing this, both load-bearing for `TagEditorPlugin`:
///
/// 1. `id3_codec`'s "no existing tag" write path (`_createNewID3Body`)
///    builds its header via a fixed-length `List.filled(10, 0x00)` and
///    then calls `.replaceRange()` on it — which Dart's
///    `FixedLengthListMixin` rejects unconditionally, even for a
///    same-length replacement. That's a real bug in the package, hit by
///    any file that has no ID3v2 tag yet (a very ordinary case, not an
///    edge case). Worked around by always ensuring a minimal valid empty
///    ID3v2.3 header exists before encoding ([_fakeAudioBytes] here,
///    `ensureId3v2Header` in the real plugin) — that forces the encoder
///    down its "edit existing tag" path, which does not have this bug.
/// 2. `ID3MetataInfo.toTagMap()` is **not** a flat `{'TIT2': 'value'}`
///    map — it's `{Header: {...}, Frames: [{'Frame ID': 'TIT2', 'Content':
///    {'Information': 'value'}, ...}, ...], Padding: {...}}`. A real
///    frame lookup has to search `Frames` by `'Frame ID'` and unwrap
///    `'Content'`, not index the top-level map directly.
void main() {
  /// Minimal valid empty ID3v2.3 header + filler bytes standing in for
  /// "an audio file with no tag yet." Must be growable — `List.filled`/a
  /// raw `Uint8List` (what `File.readAsBytes()` returns) are fixed-length
  /// and throw `Unsupported operation` the moment the encoder tries to
  /// resize them, so `TagEditorPlugin` must call `.toList()` on bytes
  /// read from disk before handing them to `ID3Encoder`.
  List<int> fakeAudioBytes() => <int>[
        0x49, 0x44, 0x33, // 'ID3'
        0x03, 0x00, // version 2.3.0
        0x00, // flags
        0x00, 0x00, 0x00, 0x00, // size = 0 (synchsafe)
        ...List.filled(54, 0), // filler "audio data"
      ];

  /// A tiny fake image starting with a real PNG signature. id3_codec
  /// sniffs the first two bytes to choose the APIC frame's MIME type and
  /// silently skips writing the frame at all for anything it doesn't
  /// recognise as a known image format — confirmed via image_type.dart,
  /// not assumed; arbitrary non-image bytes reproduced exactly that
  /// silent-drop before this fix.
  Uint8List fakePngBytes() => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ...List.generate(42, (i) => i % 256),
      ]);

  /// Finds a frame by its ID (e.g. 'TIT2', 'APIC') in a decoded tag map
  /// and returns its unwrapped Content. Frame content shapes differ per
  /// frame type — most text frames nest their value under
  /// `Content['Information']`; this returns the raw Content map so
  /// callers can pick the field they need.
  Map<String, dynamic>? frame(Map<String, dynamic> tagMap, String frameId) {
    final frames = tagMap['Frames'];
    if (frames is! List) return null;
    for (final f in frames) {
      if (f is Map && f['Frame ID'] == frameId) {
        final content = f['Content'];
        return content is Map ? Map<String, dynamic>.from(content) : null;
      }
    }
    return null;
  }

  String? textFrame(Map<String, dynamic> tagMap, String frameId) =>
      frame(tagMap, frameId)?['Information']?.toString();

  Map<String, dynamic> tagMapOf(List<int> bytes) {
    final metadatas = ID3Decoder(bytes).decodeSync();
    // Prefer ID3v2 (richer) when both v1 and v2 are present; a 64-byte
    // fixture is too short to ever contain a v1 tag (which needs the tag
    // in the last 128 bytes) but real files could have both.
    for (final m in metadatas.reversed) {
      final map = m.toTagMap();
      if (map.containsKey('Frames')) return map;
    }
    return metadatas.isEmpty ? {} : metadatas.first.toTagMap();
  }

  test('encoding only title preserves previously-written artist/album/art',
      () {
    final afterFullWrite =
        ID3Encoder(fakeAudioBytes()).encodeSync(MetadataV2p3Body(
      title: 'Original Title',
      artist: 'Original Artist',
      album: 'Original Album',
      imageBytes: fakePngBytes(),
    ));

    final beforeTags = tagMapOf(afterFullWrite);
    expect(textFrame(beforeTags, 'TIT2'), 'Original Title');
    expect(textFrame(beforeTags, 'TPE1'), 'Original Artist');
    expect(textFrame(beforeTags, 'TALB'), 'Original Album');
    expect(frame(beforeTags, 'APIC'), isNotNull,
        reason: 'artwork with a recognised image signature must be written');

    // Now edit ONLY the title, on top of those existing bytes.
    final afterTitleOnlyEdit =
        ID3Encoder(afterFullWrite).encodeSync(const MetadataV2p3Body(
      title: 'Renamed Title',
    ));

    final afterTags = tagMapOf(afterTitleOnlyEdit);
    expect(textFrame(afterTags, 'TIT2'), 'Renamed Title',
        reason: 'the field we asked to change');
    expect(textFrame(afterTags, 'TPE1'), 'Original Artist',
        reason: 'must survive an edit that never mentioned artist');
    expect(textFrame(afterTags, 'TALB'), 'Original Album',
        reason: 'must survive an edit that never mentioned album');
    expect(frame(afterTags, 'APIC'), isNotNull,
        reason: 'artwork must survive an edit that never mentioned it');
  });

  test(
      'userDefines (custom TXXX frames) round-trip and coexist with native frames',
      () {
    final bytes = ID3Encoder(fakeAudioBytes()).encodeSync(const MetadataV2p3Body(
      title: 'T',
      artist: 'A',
      userDefines: {'GENRE': 'Electronic', 'BPM': '128'},
    ));

    final tags = tagMapOf(bytes);
    expect(textFrame(tags, 'TIT2'), 'T');
    expect(textFrame(tags, 'TPE1'), 'A');
    // TXXX frames decode with their custom key/value inside Content —
    // assert loosely on presence in the serialized form rather than
    // hard-coding the exact nested shape, which is the package's own
    // internal choice for a multi-value frame type.
    final serialized = tags.toString();
    expect(serialized, contains('Electronic'));
    expect(serialized, contains('128'));
  });

  test('a second round of userDefines edits does not lose the first round',
      () {
    final afterFirst =
        ID3Encoder(fakeAudioBytes()).encodeSync(const MetadataV2p3Body(
      title: 'T',
      userDefines: {'GENRE': 'Electronic'},
    ));
    final afterSecond =
        ID3Encoder(afterFirst).encodeSync(const MetadataV2p3Body(
      userDefines: {'BPM': '128'},
    ));

    final serialized = tagMapOf(afterSecond).toString();
    expect(serialized, contains('Electronic'),
        reason: 'first custom frame must survive a later, different edit');
    expect(serialized, contains('128'));
  });
}
