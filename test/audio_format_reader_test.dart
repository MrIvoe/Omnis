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

  /// Encodes [value] as a big-endian 80-bit IEEE 754 extended-precision
  /// float — independently of `AudioFormatReader._decodeExtended80`
  /// (via `BigInt`, so there's no risk of the same signed-64-bit-shift
  /// mistake the reader itself has to avoid), the exact format AIFF's
  /// `COMM` chunk stores its sample rate in.
  List<int> encodeExtended80(int value) {
    var bitWidth = 0;
    var v = value;
    while (v > 0) {
      bitWidth++;
      v >>= 1;
    }
    final exponent = bitWidth - 1;
    final biasedExponent = 16383 + exponent;
    final mantissa = BigInt.from(value) << (63 - exponent);
    final bytes = <int>[
      (biasedExponent >> 8) & 0xFF,
      biasedExponent & 0xFF,
    ];
    for (var i = 7; i >= 0; i--) {
      bytes.add(((mantissa >> (i * 8)) & BigInt.from(0xFF)).toInt());
    }
    return bytes;
  }

  /// Builds a real, spec-correct AIFF or AIFC `FORM`/`COMM` header —
  /// [compressionType] (e.g. `'NONE'`, `'sowt'`, `'ima4'`) makes it an
  /// AIFC container with that field appended to `COMM`; `null` builds a
  /// plain AIFF container with no such field at all.
  List<int> buildAiffHeader({
    required int sampleRate,
    required int channels,
    required int bitDepth,
    required int numSampleFrames,
    String? compressionType,
  }) {
    final rateBytes = encodeExtended80(sampleRate);
    final commData = <int>[
      (channels >> 8) & 0xFF, channels & 0xFF,
      (numSampleFrames >> 24) & 0xFF, (numSampleFrames >> 16) & 0xFF,
      (numSampleFrames >> 8) & 0xFF, numSampleFrames & 0xFF,
      (bitDepth >> 8) & 0xFF, bitDepth & 0xFF,
      ...rateBytes,
      if (compressionType != null) ...compressionType.codeUnits,
    ];
    final formType = compressionType != null ? 'AIFC' : 'AIFF';
    final formChunkSize = 4 + (8 + commData.length);
    return <int>[
      ...'FORM'.codeUnits,
      (formChunkSize >> 24) & 0xFF, (formChunkSize >> 16) & 0xFF,
      (formChunkSize >> 8) & 0xFF, formChunkSize & 0xFF,
      ...formType.codeUnits,
      ...'COMM'.codeUnits,
      (commData.length >> 24) & 0xFF, (commData.length >> 16) & 0xFF,
      (commData.length >> 8) & 0xFF, commData.length & 0xFF,
      ...commData,
    ];
  }

  /// Wraps [payload] in a single, spec-correct Ogg page (`OggS` capture
  /// pattern, a minimal fixed header, and a one-entry segment table) —
  /// sufficient for a test payload well under 255 bytes, which every id
  /// header here is.
  List<int> buildOggPage(List<int> payload) {
    return <int>[
      ...'OggS'.codeUnits,
      0, // version
      0x02, // header_type: beginning-of-stream
      ...List.filled(8, 0), // granule position (unused by the reader)
      ...List.filled(4, 0), // bitstream serial number (unused)
      0, 0, 0, 0, // page sequence number (unused)
      0, 0, 0, 0, // CRC checksum (unused — the reader doesn't verify it)
      1, // page_segments: one segment
      payload.length & 0xFF, // segment table: this page's one segment
      ...payload,
    ];
  }

  /// Builds a real, spec-correct Vorbis identification-header packet
  /// (packet type 1, `"vorbis"` signature, 30 bytes total) —
  /// independently of `AudioFormatReader._readOgg`'s own field offsets.
  List<int> buildVorbisIdHeader({
    required int sampleRate,
    required int channels,
  }) {
    return <int>[
      0x01,
      ...'vorbis'.codeUnits,
      0, 0, 0, 0, // vorbis_version
      channels & 0xFF,
      sampleRate & 0xFF, (sampleRate >> 8) & 0xFF,
      (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF,
      0, 0, 0, 0, // bitrate_maximum (unset)
      0, 0, 0, 0, // bitrate_nominal (unset — deliberately not reported)
      0, 0, 0, 0, // bitrate_minimum (unset)
      0x00, // blocksize_0/blocksize_1
      0x01, // framing_flag
    ];
  }

  /// Builds a real, spec-correct Opus `OpusHead` identification packet
  /// (19 bytes, the minimum/no-channel-mapping-table form).
  List<int> buildOpusHead({
    required int inputSampleRate,
    required int channels,
  }) {
    return <int>[
      ...'OpusHead'.codeUnits,
      1, // version
      channels & 0xFF,
      0, 0, // pre-skip
      inputSampleRate & 0xFF, (inputSampleRate >> 8) & 0xFF,
      (inputSampleRate >> 16) & 0xFF, (inputSampleRate >> 24) & 0xFF,
      0, 0, // output gain
      0, // channel mapping family
    ];
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

  group('AIFF/AIFC', () {
    test('reads sample rate, bit depth, channels, and a computed PCM '
        'bitrate from a plain AIFF COMM chunk', () async {
      final bytes = buildAiffHeader(
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        numSampleFrames: 1000,
      );
      final file = writeFile('test.aiff', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AIFF');
      expect(info.sampleRateHz, 44100);
      expect(info.bitDepth, 16);
      expect(info.channels, 2);
      // 44100 * 2 * 16 = 1411200 bits/s -> /1000 kbps.
      expect(info.bitrateKbps, 1411);
    });

    test('reads a less common sample rate (48000, 24-bit, mono) '
        'correctly — proves the 80-bit extended-float decode isn\'t '
        'hardcoded to 44100/16-bit', () async {
      final bytes = buildAiffHeader(
        sampleRate: 48000,
        channels: 1,
        bitDepth: 24,
        numSampleFrames: 500,
      );
      final file = writeFile('test.aiff', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.sampleRateHz, 48000);
      expect(info.bitDepth, 24);
      expect(info.channels, 1);
      expect(info.bitrateKbps, 1152); // 48000 * 1 * 24 / 1000
    });

    test("an AIFC container with compressionType 'NONE' is real PCM — "
        'gets the same computed bitrate a plain AIFF would', () async {
      final bytes = buildAiffHeader(
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        numSampleFrames: 1000,
        compressionType: 'NONE',
      );
      final file = writeFile('test.aifc', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AIFC (NONE)');
      expect(info.bitrateKbps, 1411);
    });

    test("an AIFC container with compressionType 'sowt' (byte-swapped, "
        'still-uncompressed PCM) also gets a computed bitrate', () async {
      final bytes = buildAiffHeader(
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        numSampleFrames: 1000,
        compressionType: 'sowt',
      );
      final file = writeFile('test.aifc', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AIFC (sowt)');
      expect(info.bitrateKbps, 1411);
    });

    test('a genuinely compressed AIFC (e.g. ima4) leaves bitrateKbps '
        'null rather than reporting a wrong PCM-derived number, while '
        'still reporting the real sample rate/channels/bit depth',
        () async {
      final bytes = buildAiffHeader(
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        numSampleFrames: 1000,
        compressionType: 'ima4',
      );
      final file = writeFile('test.aifc', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AIFC (ima4)');
      expect(info.sampleRateHz, 44100);
      expect(info.channels, 2);
      expect(info.bitrateKbps, isNull);
    });

    test('degrades to unknown for a non-FORM file with a .aiff extension',
        () async {
      final file = writeFile('fake.aiff', List.filled(50, 0));

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, isNull);
    });

    test('a .aif extension is recognized the same as .aiff', () async {
      final bytes = buildAiffHeader(
        sampleRate: 44100,
        channels: 2,
        bitDepth: 16,
        numSampleFrames: 1000,
      );
      final file = writeFile('test.aif', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AIFF');
    });
  });

  group('Ogg Vorbis/Opus', () {
    test('reads sample rate and channels from a Vorbis identification '
        'header, and leaves bitrate null (nominal bitrate is a '
        "non-binding encoder hint, not a real number)", () async {
      final page = buildOggPage(
          buildVorbisIdHeader(sampleRate: 44100, channels: 2));
      final file = writeFile('test.ogg', page);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'Ogg Vorbis');
      expect(info.sampleRateHz, 44100);
      expect(info.channels, 2);
      expect(info.bitrateKbps, isNull);
      expect(info.bitDepth, isNull);
    });

    test('reads a mono, less common sample rate correctly — proves the '
        'field offsets aren\'t hardcoded to one fixture', () async {
      final page =
          buildOggPage(buildVorbisIdHeader(sampleRate: 48000, channels: 1));
      final file = writeFile('test.ogg', page);

      final info = await AudioFormatReader.read(file.path);

      expect(info.sampleRateHz, 48000);
      expect(info.channels, 1);
    });

    test('reads channels from an OpusHead identification header and '
        "always reports 48000Hz — the rate Opus's decoder actually "
        "outputs at, not the header's own informational input-rate "
        'field', () async {
      final page = buildOggPage(
          buildOpusHead(inputSampleRate: 44100, channels: 2));
      final file = writeFile('test.opus', page);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'Opus');
      expect(info.sampleRateHz, 48000);
      expect(info.channels, 2);
      expect(info.bitrateKbps, isNull);
    });

    test('an .oga extension is recognized as Ogg too', () async {
      final page = buildOggPage(
          buildVorbisIdHeader(sampleRate: 44100, channels: 2));
      final file = writeFile('test.oga', page);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'Ogg Vorbis');
    });

    test('a real Ogg page whose payload is neither Vorbis nor Opus '
        '(e.g. a real Ogg FLAC/Theora stream) still gets a generic Ogg '
        'label rather than crashing or reporting unknown', () async {
      final page = buildOggPage(List.filled(20, 0x41)); // arbitrary payload
      final file = writeFile('test.ogg', page);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'Ogg');
      expect(info.sampleRateHz, isNull);
    });

    test('degrades to unknown for a non-OggS file with a .ogg extension',
        () async {
      final file = writeFile('fake.ogg', List.filled(50, 0));

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, isNull);
    });
  });

  /// Wraps [content] in an MP4 box (32-bit size + 4-char fourcc) — the
  /// building block every other M4A helper below composes, encoding real
  /// nesting rather than the reader's own box-walking logic run backwards.
  List<int> mp4Box(String fourcc, List<int> content) {
    final size = 8 + content.length;
    return <int>[
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      ...fourcc.codeUnits,
      ...content,
    ];
  }

  List<int> u32(int value) => [
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];

  List<int> u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

  /// Builds a real (version 0) `mdhd` box — the fallback source for a
  /// duration-derived bitrate when no more authoritative bitrate field
  /// (AAC's `esds` average, ALAC's magic-cookie average) is present.
  List<int> buildMdhd({required int timescale, required int duration}) {
    return mp4Box('mdhd', <int>[
      0, 0, 0, 0, // version + flags
      0, 0, 0, 0, // creation_time
      0, 0, 0, 0, // modification_time
      ...u32(timescale),
      ...u32(duration),
      0, 0, // language
      0, 0, // pre_defined
    ]);
  }

  /// Builds a real `hdlr` box declaring [handlerType] (`'soun'` for
  /// audio, `'vide'` for video) — what `AudioFormatReader._readM4a` uses
  /// to find the real audio track among possibly several.
  List<int> buildHdlr(String handlerType) {
    return mp4Box('hdlr', <int>[
      0, 0, 0, 0, // version + flags
      0, 0, 0, 0, // pre_defined
      ...handlerType.codeUnits,
      ...List.filled(12, 0), // reserved
      0, // empty name, null-terminated
    ]);
  }

  /// Builds a real MPEG-4 `AudioSampleEntry` (version 0: the fixed
  /// 28-byte legacy QuickTime sound-description fields, no extra
  /// version-1 fields) with [fourcc] `mp4a` or `alac`, plus whatever
  /// [children] boxes (an `esds` or a nested `alac` magic cookie) follow.
  List<int> buildAudioSampleEntry(
    String fourcc, {
    required int legacyChannels,
    required int legacySampleSize,
    required int legacySampleRate,
    List<int> children = const [],
  }) {
    return mp4Box(fourcc, <int>[
      ...List.filled(6, 0), // reserved
      0, 0, // data_reference_index
      0, 0, // version (0 — children start right after these 28 bytes)
      0, 0, // revision_level
      0, 0, 0, 0, // vendor
      ...u16(legacyChannels),
      ...u16(legacySampleSize),
      0, 0, // pre_defined
      0, 0, // reserved
      ...u32(legacySampleRate << 16),
      ...children,
    ]);
  }

  /// Builds a real `esds` box with a full `ES_Descriptor` →
  /// `DecoderConfigDescriptor` → `DecoderSpecificInfo` (an
  /// `AudioSpecificConfig` bitstream) chain — independently bit-packed,
  /// not the reader's own decode logic run backwards. [freqIndex]/
  /// [channelConfig] are AAC's own standard table indices (not raw Hz/
  /// channel-count values), matching what a real encoder actually writes.
  List<int> buildEsds({
    required int freqIndex,
    required int channelConfig,
    required int avgBitrateBps,
  }) {
    const audioObjectType = 2; // AAC LC
    final ascBits =
        (audioObjectType << 11) | (freqIndex << 7) | (channelConfig << 3);
    final asc = <int>[(ascBits >> 8) & 0xFF, ascBits & 0xFF];
    final decoderSpecificInfo = <int>[0x05, asc.length, ...asc];

    final decoderConfigContent = <int>[
      0x40, // objectTypeIndication: AAC
      0x15, // streamType(6)=5 (audio) | upStream(1)=0 | reserved(1)=1
      0, 0, 0, // bufferSizeDB
      ...u32(0), // maxBitrate (unused by the reader)
      ...u32(avgBitrateBps),
      ...decoderSpecificInfo,
    ];
    final decoderConfigDescr = <int>[
      0x04,
      decoderConfigContent.length,
      ...decoderConfigContent,
    ];

    final esDescrContent = <int>[
      0, 0, // ES_ID
      0, // flags: no stream dependence / URL / OCR
      ...decoderConfigDescr,
      0x06, 1, 0x02, // minimal SLConfigDescriptor
    ];
    final esDescr = <int>[0x03, esDescrContent.length, ...esDescrContent];

    return mp4Box('esds', <int>[0, 0, 0, 0, ...esDescr]);
  }

  /// Builds a real 24-byte `ALACSpecificConfig` "magic cookie" nested
  /// inside an `alac` sample entry — independently of the reader's own
  /// field offsets, unlike `esds`'s variable-length descriptors this is
  /// a fixed layout ALAC muxers write directly.
  List<int> buildAlacCookie({
    required int sampleRate,
    required int channels,
    required int bitDepth,
    required int avgBitrateBps,
  }) {
    return mp4Box('alac', <int>[
      ...u32(4096), // frameLength
      0, // compatibleVersion
      bitDepth & 0xFF,
      40, 10, 14, // pb, mb, kb — ALAC's internal Rice-coding params
      channels & 0xFF,
      ...u16(0), // maxRun
      ...u32(0), // maxFrameBytes (unused by the reader)
      ...u32(avgBitrateBps),
      ...u32(sampleRate),
    ]);
  }

  /// Builds a minimal but real video `trak` (just enough of `mdia`/
  /// `hdlr` to declare a `vide` handler) — used to prove the reader
  /// finds the *audio* track even when a video track appears first,
  /// rather than assuming the first `trak` is always the right one.
  List<int> buildVideoTrak() {
    return mp4Box('trak', mp4Box('mdia', buildHdlr('vide')));
  }

  /// Assembles a minimal but real MP4 container — `ftyp` + `moov` (one
  /// audio `trak` wrapping [sampleEntry] through real `mdia`/`mdhd`/
  /// `hdlr`/`minf`/`stbl`/`stsd` nesting) + a dummy `mdat` — enough real
  /// box structure for `AudioFormatReader._readM4a` to walk exactly the
  /// way a real encoder's output would, without needing every other box
  /// (`mvhd`, `tkhd`, ...) a real file also carries but this reader never
  /// reads. [mdatBeforeMoov] proves the top-level scan doesn't assume
  /// canonical box order — some muxers put `moov` after `mdat`.
  List<int> buildM4aFile({
    required List<int> sampleEntry,
    int timescale = 44100,
    int duration = 44100,
    List<List<int>> extraTraksBeforeAudio = const [],
    bool mdatBeforeMoov = false,
  }) {
    final stsd = mp4Box('stsd', <int>[
      0, 0, 0, 0, // version + flags
      ...u32(1), // entry_count
      ...sampleEntry,
    ]);
    final minf = mp4Box('minf', mp4Box('stbl', stsd));
    final mdia = mp4Box('mdia', <int>[
      ...buildMdhd(timescale: timescale, duration: duration),
      ...buildHdlr('soun'),
      ...minf,
    ]);
    final audioTrak = mp4Box('trak', mdia);
    final moov = mp4Box('moov', <int>[
      ...extraTraksBeforeAudio.expand((t) => t),
      ...audioTrak,
    ]);
    final ftyp = mp4Box(
        'ftyp', <int>[...'M4A '.codeUnits, 0, 0, 0, 0, ...'M4A mp42isom'.codeUnits]);
    final mdat = mp4Box('mdat', List.filled(8, 0));
    return mdatBeforeMoov
        ? <int>[...ftyp, ...mdat, ...moov]
        : <int>[...ftyp, ...moov, ...mdat];
  }

  group('M4A/AAC/ALAC (item 22)', () {
    test('reads AAC\'s real sample rate/channels from esds, overriding '
        'the sample entry\'s placeholder legacy fields', () async {
      final entry = buildAudioSampleEntry(
        'mp4a',
        legacyChannels: 2,
        legacySampleSize: 16,
        legacySampleRate: 44100,
        children: buildEsds(
          freqIndex: 3, // 48000 — deliberately different from the legacy field
          channelConfig: 1, // mono — deliberately different from the legacy field
          avgBitrateBps: 128000,
        ),
      );
      final bytes = buildM4aFile(sampleEntry: entry);
      final file = writeFile('song.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AAC (M4A)');
      expect(info.sampleRateHz, 48000);
      expect(info.channels, 1);
      expect(info.bitrateKbps, 128);
      // AAC is lossy — no real fixed-width PCM bit depth to report.
      expect(info.bitDepth, isNull);
    });

    test('falls back to the sample entry\'s legacy fields and a '
        'duration-derived bitrate when esds is absent', () async {
      final entry = buildAudioSampleEntry(
        'mp4a',
        legacyChannels: 2,
        legacySampleSize: 16,
        legacySampleRate: 44100,
      );
      final bytes = buildM4aFile(
        sampleEntry: entry,
        timescale: 44100,
        duration: 44100 * 10, // exactly 10 seconds
      );
      final file = writeFile('no_esds.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AAC (M4A)');
      expect(info.sampleRateHz, 44100);
      expect(info.channels, 2);
      expect(info.bitDepth, isNull);
      final expectedBitrate = ((bytes.length * 8) / 10 / 1000).round();
      expect(info.bitrateKbps, expectedBitrate);
    });

    test('reads ALAC\'s real bit depth/channels/sample rate/bitrate '
        'directly from its magic cookie', () async {
      final entry = buildAudioSampleEntry(
        'alac',
        legacyChannels: 2,
        legacySampleSize: 16,
        legacySampleRate: 44100,
        children: buildAlacCookie(
          sampleRate: 96000,
          channels: 2,
          bitDepth: 24,
          avgBitrateBps: 900000,
        ),
      );
      final bytes = buildM4aFile(sampleEntry: entry);
      final file = writeFile('song_lossless.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'ALAC (M4A)');
      expect(info.sampleRateHz, 96000);
      expect(info.channels, 2);
      expect(info.bitDepth, 24);
      expect(info.bitrateKbps, 900);
    });

    test('finds the audio track even when a video track appears first',
        () async {
      final entry = buildAudioSampleEntry(
        'mp4a',
        legacyChannels: 1,
        legacySampleSize: 16,
        legacySampleRate: 22050,
      );
      final bytes = buildM4aFile(
        sampleEntry: entry,
        extraTraksBeforeAudio: [buildVideoTrak()],
      );
      final file = writeFile('with_video_track.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'AAC (M4A)');
      expect(info.sampleRateHz, 22050);
      expect(info.channels, 1);
    });

    test('finds moov even when it appears after mdat (a streaming-'
        'optimized layout)', () async {
      final entry = buildAudioSampleEntry(
        'alac',
        legacyChannels: 2,
        legacySampleSize: 16,
        legacySampleRate: 44100,
        children: buildAlacCookie(
          sampleRate: 44100,
          channels: 2,
          bitDepth: 16,
          avgBitrateBps: 700000,
        ),
      );
      final bytes =
          buildM4aFile(sampleEntry: entry, mdatBeforeMoov: true);
      final file = writeFile('moov_after_mdat.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'ALAC (M4A)');
      expect(info.sampleRateHz, 44100);
      expect(info.bitDepth, 16);
    });

    test('labels an unrecognized sample-entry codec by its own fourcc',
        () async {
      final entry = buildAudioSampleEntry(
        'ac-3',
        legacyChannels: 6,
        legacySampleSize: 16,
        legacySampleRate: 48000,
      );
      final bytes = buildM4aFile(sampleEntry: entry);
      final file = writeFile('surround.m4a', bytes);

      final info = await AudioFormatReader.read(file.path);

      expect(info.codec, 'M4A (ac-3)');
      expect(info.sampleRateHz, 48000);
      expect(info.channels, 6);
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

      expect((await AudioFormatReader.read(m4a.path)).codec,
          'AAC/ALAC (M4A)');
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
