import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/audio_format_reader.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('omnis_audio_format_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File writeFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  /// Builds a real, spec-correct FLAC STREAMINFO header (magic + one
  /// metadata block) for the given sample rate/channels/bit depth/total
  /// sample count — the exact bit layout `AudioFormatReader._readFlac`
  /// decodes, built independently here (packing, not unpacking) so the
  /// test isn't just re-running the same code against itself.
  List<int> buildFlacHeader({
    required int sampleRate,
    required int channels,
    required int bitDepth,
    required int totalSamples,
  }) {
    final bytes = <int>[]
      ..addAll('fLaC'.codeUnits)
      // Metadata block header: last-block=1, type=0 (STREAMINFO), size=34.
      ..add(0x80)
      ..addAll([0x00, 0x00, 0x22])
      // min/max block size, min/max frame size — values don't matter.
      ..addAll([0x10, 0x00, 0x10, 0x00, 0, 0, 0, 0, 0, 0]);

    final channelsMinus1 = channels - 1;
    final bpsMinus1 = bitDepth - 1;
    final x = (sampleRate << 12) |
        (channelsMinus1 << 9) |
        (bpsMinus1 << 4) |
        ((totalSamples >> 32) & 0xF);
    bytes.addAll([
      (x >> 24) & 0xFF,
      (x >> 16) & 0xFF,
      (x >> 8) & 0xFF,
      x & 0xFF,
    ]);
    final lo = totalSamples & 0xFFFFFFFF;
    bytes.addAll([
      (lo >> 24) & 0xFF,
      (lo >> 16) & 0xFF,
      (lo >> 8) & 0xFF,
      lo & 0xFF,
    ]);
    bytes.addAll(List.filled(16, 0)); // MD5, unused by the reader.
    return bytes;
  }

  List<int> buildWavHeader({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    required int dataBytes,
  }) {
    final blockAlign = channels * bitsPerSample ~/ 8;
    final byteRate = sampleRate * blockAlign;
    final fmtChunk = <int>[
      1, 0, // audioFormat = PCM
      channels & 0xFF, (channels >> 8) & 0xFF,
      sampleRate & 0xFF, (sampleRate >> 8) & 0xFF,
      (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF,
      byteRate & 0xFF, (byteRate >> 8) & 0xFF,
      (byteRate >> 16) & 0xFF, (byteRate >> 24) & 0xFF,
      blockAlign & 0xFF, (blockAlign >> 8) & 0xFF,
      bitsPerSample & 0xFF, (bitsPerSample >> 8) & 0xFF,
    ];
    final riffChunkSize = 4 + (8 + fmtChunk.length) + (8 + dataBytes);
    return <int>[
      ...'RIFF'.codeUnits,
      riffChunkSize & 0xFF,
      (riffChunkSize >> 8) & 0xFF,
      (riffChunkSize >> 16) & 0xFF,
      (riffChunkSize >> 24) & 0xFF,
      ...'WAVE'.codeUnits,
      ...'fmt '.codeUnits,
      fmtChunk.length & 0xFF, 0, 0, 0,
      ...fmtChunk,
      ...'data'.codeUnits,
      dataBytes & 0xFF,
      (dataBytes >> 8) & 0xFF,
      (dataBytes >> 16) & 0xFF,
      (dataBytes >> 24) & 0xFF,
      ...List.filled(dataBytes, 0),
    ];
  }

  /// Builds an MPEG1 Layer III (standard "mp3") frame header at the start
  /// of the returned bytes, for a given bitrate table index/sample rate
  /// index/channel mode — mirroring ISO/IEC 11172-3's bit layout, not the
  /// reader's own tables, so a mistake in the reader's tables wouldn't
  /// silently pass.
  List<int> buildMp3Frame({
    required int bitrateIndex,
    required int sampleRateIndex,
    required bool mono,
    int totalBytes = 200,
  }) {
    final b1 = 0xE0 | (0x3 << 3) | (0x1 << 1) | 0x1; // MPEG1, Layer III
    final b2 = (bitrateIndex << 4) | (sampleRateIndex << 2);
    final b3 = mono ? 0xC0 : 0x00;
    final bytes = List<int>.filled(totalBytes, 0);
    bytes[0] = 0xFF;
    bytes[1] = b1;
    bytes[2] = b2;
    bytes[3] = b3;
    return bytes;
  }

  group('FLAC', () {
    test('reads real sample rate, bit depth, channels, and a computed '
        'average bitrate from the STREAMINFO block', () async {
      const sampleRate = 44100;
      const channels = 2;
      const bitDepth = 16;
      const totalSamples = 44100 * 10; // 10 seconds
      final header = buildFlacHeader(
        sampleRate: sampleRate,
        channels: channels,
        bitDepth: bitDepth,
        totalSamples: totalSamples,
      );
      // Pad to simulate real file bytes past the STREAMINFO block —
      // bitrate is computed from total file size, so this matters.
      final file = writeFile(
        'test.flac',
        [...header, ...List.filled(50000, 0)],
      );

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'FLAC');
      expect(info.sampleRateHz, sampleRate);
      expect(info.bitDepth, bitDepth);
      expect(info.channels, channels);
      // fileLength*8 / durationSeconds / 1000, duration = 10s.
      final expectedBitrate =
          ((header.length + 50000) * 8 / 10 / 1000).round();
      expect(info.bitrateKbps, expectedBitrate);
    });

    test('a mono, high-res file reports 1 channel and 24-bit depth',
        () async {
      final header = buildFlacHeader(
        sampleRate: 96000,
        channels: 1,
        bitDepth: 24,
        totalSamples: 96000 * 5,
      );
      final file = writeFile('mono.flac', header);

      final info = await AudioFormatReader.read(file.path);

      expect(info.sampleRateHz, 96000);
      expect(info.channels, 1);
      expect(info.bitDepth, 24);
    });

    test('degrades to unknown for a file with the right extension but no '
        'real fLaC magic', () async {
      final file = writeFile('fake.flac', List.filled(50, 0));

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, isNull);
      expect(info.sampleRateHz, isNull);
    });
  });

  group('WAV', () {
    test('reads sample rate, bit depth, channels, and byte-rate-derived '
        'bitrate from the fmt chunk', () async {
      final bytes = buildWavHeader(
        sampleRate: 44100,
        channels: 2,
        bitsPerSample: 16,
        dataBytes: 1000,
      );
      final file = writeFile('test.wav', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'PCM (WAV)');
      expect(info.sampleRateHz, 44100);
      expect(info.bitDepth, 16);
      expect(info.channels, 2);
      // byteRate = 44100 * 2 * 16/8 = 176400 bytes/s -> *8/1000 kbps.
      expect(info.bitrateKbps, 1411);
    });

    test('degrades to unknown for a non-RIFF file with a .wav extension',
        () async {
      final file = writeFile('fake.wav', List.filled(50, 0));

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, isNull);
    });
  });

  group('MP3', () {
    test('reads sample rate/channels/CBR bitrate from a plain (non-VBR) '
        'frame header', () async {
      // MPEG1 Layer III: bitrateIndex 9 -> 128kbps, sampleRateIndex 0 ->
      // 44100Hz (ISO/IEC 11172-3 tables).
      final bytes = buildMp3Frame(
        bitrateIndex: 9,
        sampleRateIndex: 0,
        mono: false,
      );
      final file = writeFile('test.mp3', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'MP3');
      expect(info.sampleRateHz, 44100);
      expect(info.channels, 2);
      expect(info.bitrateKbps, 128);
    });

    test('a mono frame reports 1 channel', () async {
      final bytes = buildMp3Frame(
        bitrateIndex: 5, // 64kbps
        sampleRateIndex: 2, // 32000Hz
        mono: true,
      );
      final file = writeFile('mono.mp3', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.channels, 1);
      expect(info.sampleRateHz, 32000);
      expect(info.bitrateKbps, 64);
    });

    test('prefers a Xing VBR header\'s computed average bitrate over the '
        'misleading first-frame bitrate', () async {
      final bytes = buildMp3Frame(
        bitrateIndex: 9, // 128kbps — NOT the real average, by design.
        sampleRateIndex: 0, // 44100Hz
        mono: false,
        totalBytes: 5000,
      );
      // MPEG1 stereo side-info is 32 bytes; Xing sits right after it.
      const tagStart = 4 + 32;
      const totalFrames = 1000;
      bytes.setRange(tagStart, tagStart + 4, 'Xing'.codeUnits);
      // Flags: bit0 set -> frame-count field present.
      bytes.setRange(tagStart + 4, tagStart + 8, [0, 0, 0, 1]);
      bytes.setRange(tagStart + 8, tagStart + 12, [
        (totalFrames >> 24) & 0xFF,
        (totalFrames >> 16) & 0xFF,
        (totalFrames >> 8) & 0xFF,
        totalFrames & 0xFF,
      ]);
      final file = writeFile('vbr.mp3', bytes);

      final info = await AudioFormatReader.read(file.path);

      // duration = totalFrames * 1152 (MPEG1 Layer III) / sampleRate
      final durationSeconds = totalFrames * 1152 / 44100;
      final expectedBitrate =
          ((bytes.length * 8) / durationSeconds / 1000).round();
      expect(info.bitrateKbps, expectedBitrate);
      expect(info.bitrateKbps, isNot(128));
    });

    test('skips a leading ID3v2 tag before searching for the frame sync',
        () async {
      final frame = buildMp3Frame(
        bitrateIndex: 9,
        sampleRateIndex: 0,
        mono: false,
      );
      // Minimal ID3v2 header: "ID3" + version(2) + flags(1) + synchsafe
      // size(4) = 10 bytes total, size field claims 20 bytes of tag data.
      final id3 = <int>[
        ...'ID3'.codeUnits,
        3, 0, // version
        0, // flags
        0, 0, 0, 20, // synchsafe size = 20
      ];
      final file = writeFile(
        'tagged.mp3',
        [...id3, ...List.filled(20, 0), ...frame],
      );

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'MP3');
      expect(info.sampleRateHz, 44100);
    });
  });

  group('unsupported/unknown formats', () {
    test('still labels the codec by extension for formats without a full '
        'header parser', () async {
      final m4a = writeFile('song.m4a', List.filled(20, 0));
      final ogg = writeFile('song.ogg', List.filled(20, 0));
      final aiff = writeFile('song.aiff', List.filled(20, 0));

      expect((await AudioFormatReader.read(m4a.path)).codec,
          'AAC/ALAC (M4A)');
      expect((await AudioFormatReader.read(ogg.path)).codec, 'Ogg Vorbis');
      expect((await AudioFormatReader.read(aiff.path)).codec, 'AIFF');
      // No numeric fields guessed for these.
      expect((await AudioFormatReader.read(m4a.path)).sampleRateHz, isNull);
    });

    test('an unrecognized extension returns AudioFormatInfo.unknown',
        () async {
      final file = writeFile('notes.txt', List.filled(20, 0));

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, isNull);
      expect(info.sampleRateHz, isNull);
    });

    test('a nonexistent path never throws — degrades to unknown', () async {
      final info =
          await AudioFormatReader.read('${tempDir.path}/does_not_exist.mp3');

      expect(info.codec, isNull);
    });
  });
}
