import 'dart:io';

/// Real audio-format facts sniffed directly from a local file's own
/// header bytes — codec/container, sample rate, bit depth, channel
/// count, and (for the formats fully parsed here) a real bitrate, not a
/// guess. Distinct from ID3/tag reading (`TagEditorPlugin`): this reads
/// the audio stream's own framing, never embedded metadata frames.
class AudioFormatInfo {
  final String? codec;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? bitrateKbps;
  final int? channels;

  const AudioFormatInfo({
    this.codec,
    this.sampleRateHz,
    this.bitDepth,
    this.bitrateKbps,
    this.channels,
  });

  static const unknown = AudioFormatInfo();
}

/// Sniffs [AudioFormatInfo] straight from a local audio file's header —
/// no native decoder, no ffprobe (this app has no native build step to
/// bundle one into; see `docs/BUILDING.md`). FLAC, WAV, and MP3 headers
/// are simple enough to parse reliably in pure Dart and are fully
/// supported, including a real average bitrate (from a VBR header's
/// frame/byte counts for MP3, from file-size/duration for FLAC). Every
/// other recognized extension still gets a codec label, with the
/// numeric fields deliberately left `null` rather than guessed — full
/// parsing of MP4/M4A boxes, Ogg pages, or WMA's ASF headers is real,
/// separate work not attempted here.
class AudioFormatReader {
  const AudioFormatReader._();

  /// Reads just enough of [path] to determine its format — never the
  /// whole file. Never throws: an unreadable/truncated/corrupt file
  /// degrades to [AudioFormatInfo.unknown], the same "don't break the
  /// scan over one bad file" contract the rest of `MediaScanner` follows.
  static Future<AudioFormatInfo> read(String path) async {
    try {
      final dot = path.lastIndexOf('.');
      final ext =
          dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
      switch (ext) {
        case 'flac':
          return await _readFlac(File(path));
        case 'wav':
          return await _readWav(File(path));
        case 'mp3':
          return await _readMp3(File(path));
        case 'm4a':
          return const AudioFormatInfo(codec: 'AAC/ALAC (M4A)');
        case 'aac':
          return const AudioFormatInfo(codec: 'AAC');
        case 'ogg':
          return const AudioFormatInfo(codec: 'Ogg Vorbis');
        case 'opus':
          return const AudioFormatInfo(codec: 'Opus');
        case 'wma':
          return const AudioFormatInfo(codec: 'WMA');
        case 'aiff':
          return const AudioFormatInfo(codec: 'AIFF');
        default:
          return AudioFormatInfo.unknown;
      }
    } catch (_) {
      return AudioFormatInfo.unknown;
    }
  }

  static Future<AudioFormatInfo> _readFlac(File file) async {
    final raf = await file.open();
    try {
      final header = await raf.read(42);
      if (header.length < 42 ||
          header[0] != 0x66 || // f
          header[1] != 0x4C || // L
          header[2] != 0x61 || // a
          header[3] != 0x43) {
        // C
        return AudioFormatInfo.unknown;
      }
      // STREAMINFO block starts right after the 4-byte magic + 4-byte
      // metadata-block header. Layout (big-endian, bit-packed):
      // sample_rate(20) | channels-1(3) | bits_per_sample-1(5) | total_samples(36)
      final x =
          (header[18] << 24) | (header[19] << 16) | (header[20] << 8) | header[21];
      final sampleRate = x >> 12;
      final channels = ((x >> 9) & 0x7) + 1;
      final bitDepth = ((x >> 4) & 0x1F) + 1;
      final totalSamplesHi = x & 0xF;
      final totalSamplesLo = (header[22] << 24) |
          (header[23] << 16) |
          (header[24] << 8) |
          header[25];
      final totalSamples =
          (totalSamplesHi << 32) | (totalSamplesLo & 0xFFFFFFFF);

      int? bitrateKbps;
      if (sampleRate > 0 && totalSamples > 0) {
        final durationSeconds = totalSamples / sampleRate;
        if (durationSeconds > 0) {
          final fileLength = await file.length();
          bitrateKbps = ((fileLength * 8) / durationSeconds / 1000).round();
        }
      }

      return AudioFormatInfo(
        codec: 'FLAC',
        sampleRateHz: sampleRate > 0 ? sampleRate : null,
        bitDepth: bitDepth,
        channels: channels,
        bitrateKbps: bitrateKbps,
      );
    } finally {
      await raf.close();
    }
  }

  static Future<AudioFormatInfo> _readWav(File file) async {
    final raf = await file.open();
    try {
      final riffHeader = await raf.read(12);
      if (riffHeader.length < 12 ||
          riffHeader[0] != 0x52 || // R
          riffHeader[1] != 0x49 || // I
          riffHeader[2] != 0x46 || // F
          riffHeader[3] != 0x46 || // F
          riffHeader[8] != 0x57 || // W
          riffHeader[9] != 0x41 || // A
          riffHeader[10] != 0x56 || // V
          riffHeader[11] != 0x45) {
        // E
        return AudioFormatInfo.unknown;
      }

      final fileLength = await file.length();
      var pos = 12;
      // RIFF chunks are word-aligned: an odd-sized chunk's data is
      // followed by one pad byte not counted in its declared size.
      while (pos + 8 <= fileLength) {
        await raf.setPosition(pos);
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) break;
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = chunkHeader[4] |
            (chunkHeader[5] << 8) |
            (chunkHeader[6] << 16) |
            (chunkHeader[7] << 24);
        if (chunkId == 'fmt ') {
          final toRead = chunkSize < 16 ? chunkSize : 16;
          final fmt = await raf.read(toRead);
          if (fmt.length < 16) return const AudioFormatInfo(codec: 'WAV');
          final audioFormat = fmt[0] | (fmt[1] << 8);
          final channels = fmt[2] | (fmt[3] << 8);
          final sampleRate =
              fmt[4] | (fmt[5] << 8) | (fmt[6] << 16) | (fmt[7] << 24);
          final byteRate =
              fmt[8] | (fmt[9] << 8) | (fmt[10] << 16) | (fmt[11] << 24);
          final bitsPerSample = fmt[14] | (fmt[15] << 8);
          return AudioFormatInfo(
            codec: audioFormat == 3
                ? 'IEEE Float (WAV)'
                : audioFormat == 1
                    ? 'PCM (WAV)'
                    : 'WAV',
            sampleRateHz: sampleRate > 0 ? sampleRate : null,
            bitDepth: bitsPerSample > 0 ? bitsPerSample : null,
            channels: channels > 0 ? channels : null,
            bitrateKbps: byteRate > 0 ? (byteRate * 8 / 1000).round() : null,
          );
        }
        pos += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }
      return const AudioFormatInfo(codec: 'WAV');
    } finally {
      await raf.close();
    }
  }

  static const _mpeg1Layer3Bitrates = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1,
  ];
  static const _mpeg2Layer3Bitrates = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1,
  ];
  static const _mpeg1SampleRates = [44100, 48000, 32000, -1];
  static const _mpeg2SampleRates = [22050, 24000, 16000, -1];
  static const _mpeg25SampleRates = [11025, 12000, 8000, -1];

  static Future<AudioFormatInfo> _readMp3(File file) async {
    final raf = await file.open();
    try {
      final fileLength = await file.length();
      // Skip a leading ID3v2 tag, if present, so the frame-sync search
      // below doesn't waste time scanning through embedded artwork bytes
      // that can incidentally look like a frame sync.
      var searchStart = 0;
      final id3Header = await raf.read(10);
      if (id3Header.length == 10 &&
          id3Header[0] == 0x49 && // I
          id3Header[1] == 0x44 && // D
          id3Header[2] == 0x33) {
        // 3
        final size = ((id3Header[6] & 0x7F) << 21) |
            ((id3Header[7] & 0x7F) << 14) |
            ((id3Header[8] & 0x7F) << 7) |
            (id3Header[9] & 0x7F);
        searchStart = 10 + size;
      }
      if (searchStart < 0 || searchStart >= fileLength) {
        return const AudioFormatInfo(codec: 'MP3');
      }
      await raf.setPosition(searchStart);
      final remaining = fileLength - searchStart;
      final windowSize = remaining < 64 * 1024 ? remaining : 64 * 1024;
      final window = await raf.read(windowSize);

      for (var i = 0; i + 4 <= window.length; i++) {
        if (window[i] != 0xFF || (window[i + 1] & 0xE0) != 0xE0) continue;
        final b1 = window[i + 1];
        final b2 = window[i + 2];
        final b3 = window[i + 3];
        final versionBits = (b1 >> 3) & 0x3;
        final layerBits = (b1 >> 1) & 0x3;
        if (layerBits != 0x1) continue; // only Layer III handled
        final bitrateIndex = (b2 >> 4) & 0xF;
        final sampleRateIndex = (b2 >> 2) & 0x3;
        final channelMode = (b3 >> 6) & 0x3;
        if (bitrateIndex == 0 || bitrateIndex == 0xF) continue;
        if (sampleRateIndex == 0x3) continue;

        List<int> bitrateTable;
        List<int> sampleRateTable;
        if (versionBits == 0x3) {
          bitrateTable = _mpeg1Layer3Bitrates;
          sampleRateTable = _mpeg1SampleRates;
        } else if (versionBits == 0x2) {
          bitrateTable = _mpeg2Layer3Bitrates;
          sampleRateTable = _mpeg2SampleRates;
        } else if (versionBits == 0x0) {
          bitrateTable = _mpeg2Layer3Bitrates;
          sampleRateTable = _mpeg25SampleRates;
        } else {
          continue; // reserved version
        }
        final bitrate = bitrateTable[bitrateIndex];
        final sampleRate = sampleRateTable[sampleRateIndex];
        if (bitrate <= 0 || sampleRate <= 0) continue;
        final channels = channelMode == 0x3 ? 1 : 2;

        // A VBR file's *first* frame bitrate isn't its average — LAME
        // and friends write a "Xing"/"Info" tag inside that first frame
        // (in place of real audio) holding the true total frame/byte
        // counts. Prefer the average it implies when present.
        final vbrBitrate = _tryReadXingAverageBitrate(
          window,
          frameStart: i,
          versionBits: versionBits,
          channelMode: channelMode,
          sampleRate: sampleRate,
          fileLength: fileLength,
        );

        return AudioFormatInfo(
          codec: 'MP3',
          sampleRateHz: sampleRate,
          channels: channels,
          bitrateKbps: vbrBitrate ?? bitrate,
        );
      }
      return const AudioFormatInfo(codec: 'MP3');
    } finally {
      await raf.close();
    }
  }

  static int? _tryReadXingAverageBitrate(
    List<int> window, {
    required int frameStart,
    required int versionBits,
    required int channelMode,
    required int sampleRate,
    required int fileLength,
  }) {
    final isMpeg1 = versionBits == 0x3;
    final isMono = channelMode == 0x3;
    // Xing/Info sits right after the side-information block, whose size
    // depends on MPEG version and channel mode (standard fixed values).
    final sideInfoSize = isMpeg1 ? (isMono ? 17 : 32) : (isMono ? 9 : 17);
    final tagStart = frameStart + 4 + sideInfoSize;
    if (tagStart + 8 > window.length) return null;
    final tag = String.fromCharCodes(window.sublist(tagStart, tagStart + 4));
    if (tag != 'Xing' && tag != 'Info') return null;
    final flags = (window[tagStart + 4] << 24) |
        (window[tagStart + 5] << 16) |
        (window[tagStart + 6] << 8) |
        window[tagStart + 7];
    if (flags & 0x1 == 0) return null; // frame-count field absent
    final framesOffset = tagStart + 8;
    if (framesOffset + 4 > window.length) return null;
    final totalFrames = (window[framesOffset] << 24) |
        (window[framesOffset + 1] << 16) |
        (window[framesOffset + 2] << 8) |
        window[framesOffset + 3];
    if (totalFrames <= 0) return null;
    // Layer III samples-per-frame: 1152 for MPEG1, 576 for MPEG2/2.5.
    final samplesPerFrame = isMpeg1 ? 1152 : 576;
    final durationSeconds = totalFrames * samplesPerFrame / sampleRate;
    if (durationSeconds <= 0) return null;
    return ((fileLength * 8) / durationSeconds / 1000).round();
  }
}
