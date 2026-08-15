import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

/// One immediate child box found by [AudioFormatReader._parseMp4Boxes]:
/// its fourcc [type] plus the [start, end) content range within whatever
/// buffer it was parsed from (already past that child's own header).
class _Mp4Box {
  final String type;
  final int start;
  final int end;
  const _Mp4Box(this.type, this.start, this.end);
}

/// Result of [AudioFormatReader._parseEsds] — an AAC `esds` box's real,
/// non-placeholder sample rate/channel count/average bitrate, whatever
/// subset of them was actually present and parseable.
class _EsdsInfo {
  final int? sampleRate;
  final int? channels;
  final int? avgBitrateBps;
  const _EsdsInfo({this.sampleRate, this.channels, this.avgBitrateBps});
}

/// Result of [AudioFormatReader._parseAlacCookie] — an ALAC magic
/// cookie's directly-stored sample rate/channels/bit depth/average
/// bitrate.
class _AlacInfo {
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;
  final int? avgBitrateBps;
  const _AlacInfo(
      {this.sampleRate, this.channels, this.bitDepth, this.avgBitrateBps});
}

/// Sniffs [AudioFormatInfo] straight from a local audio file's header —
/// no native decoder, no ffprobe (this app has no native build step to
/// bundle one into; see `docs/BUILDING.md`). FLAC, WAV, MP3, AIFF/AIFC,
/// and Ogg Vorbis/Opus headers are parsed for real: sample rate and
/// channel count in every case, plus a real average bitrate for the
/// formats where one can be derived honestly rather than guessed (a VBR
/// header's frame/byte counts for MP3, file-size/duration for FLAC,
/// computed directly from channels/rate/bit-depth for the uncompressed
/// PCM formats — Ogg deliberately doesn't get one: Vorbis's header
/// "nominal bitrate" is an explicitly non-binding encoder hint, not a
/// real number, and Opus's header carries no bitrate field at all).
/// Every other recognized extension still gets a codec label, with the
/// numeric fields deliberately left `null` rather than guessed — full
/// parsing of MP4/M4A boxes or WMA's ASF headers is real, separate work
/// not attempted here.
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
          return await _readM4a(File(path));
        case 'aac':
          return const AudioFormatInfo(codec: 'AAC');
        case 'ogg':
        case 'oga':
        case 'opus':
          return await _readOgg(File(path));
        case 'wma':
          return const AudioFormatInfo(codec: 'WMA');
        case 'aiff':
        case 'aif':
        case 'aifc':
          return await _readAiff(File(path));
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

  static Future<AudioFormatInfo> _readAiff(File file) async {
    final raf = await file.open();
    try {
      final formHeader = await raf.read(12);
      if (formHeader.length < 12 ||
          formHeader[0] != 0x46 || // F
          formHeader[1] != 0x4F || // O
          formHeader[2] != 0x52 || // R
          formHeader[3] != 0x4D) {
        // M
        return AudioFormatInfo.unknown;
      }
      final formType = String.fromCharCodes(formHeader.sublist(8, 12));
      // AIFF (plain PCM) and AIFC (compressed, possibly-just-byte-swapped
      // PCM) share the same FORM container and the same leading COMM
      // fields — only AIFC's COMM has an extra compressionType after them.
      if (formType != 'AIFF' && formType != 'AIFC') {
        return AudioFormatInfo.unknown;
      }

      final fileLength = await file.length();
      var pos = 12;
      // AIFF chunks are big-endian, word-aligned exactly like RIFF's:
      // an odd-sized chunk's data is followed by one unpadded pad byte.
      while (pos + 8 <= fileLength) {
        await raf.setPosition(pos);
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) break;
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = (chunkHeader[4] << 24) |
            (chunkHeader[5] << 16) |
            (chunkHeader[6] << 8) |
            chunkHeader[7];
        if (chunkId == 'COMM') {
          // channels(2) | numSampleFrames(4) | sampleSize(2) |
          // sampleRate(10, 80-bit IEEE 754 extended) | [compressionType(4)]
          final toRead = chunkSize < 18 ? chunkSize : 18;
          final comm = await raf.read(toRead);
          if (comm.length < 18) {
            return AudioFormatInfo(codec: formType);
          }
          final channels = (comm[0] << 8) | comm[1];
          final bitDepth = (comm[6] << 8) | comm[7];
          final sampleRate = _decodeExtended80(comm.sublist(8, 18)).round();

          String? compressionType;
          if (formType == 'AIFC' && chunkSize >= 22) {
            final extra = await raf.read(4);
            if (extra.length == 4) {
              compressionType = String.fromCharCodes(extra);
            }
          }
          // 'NONE' is AIFC's own uncompressed marker; 'sowt' is
          // little-endian PCM (still uncompressed, just byte-swapped) —
          // both have a real, computable PCM bitrate. Any other
          // compressionType (e.g. 'ima4') genuinely isn't PCM, so the
          // straightforward channels*rate*bitDepth formula would be
          // wrong for it — left null rather than guessed, same stance
          // the MP3/WAV readers already take for anything they can't
          // derive honestly.
          final isPcm = formType == 'AIFF' ||
              compressionType == null ||
              compressionType == 'NONE' ||
              compressionType == 'sowt';
          final bitrateKbps = isPcm &&
                  sampleRate > 0 &&
                  channels > 0 &&
                  bitDepth > 0
              ? (sampleRate * channels * bitDepth / 1000).round()
              : null;

          return AudioFormatInfo(
            codec: formType == 'AIFC'
                ? 'AIFC (${compressionType ?? "unknown"})'
                : 'AIFF',
            sampleRateHz: sampleRate > 0 ? sampleRate : null,
            bitDepth: bitDepth > 0 ? bitDepth : null,
            channels: channels > 0 ? channels : null,
            bitrateKbps: bitrateKbps,
          );
        }
        pos += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }
      return AudioFormatInfo(codec: formType);
    } finally {
      await raf.close();
    }
  }

  /// Decodes a big-endian 80-bit IEEE 754 extended-precision float — the
  /// format AIFF's `COMM` chunk stores its sample rate in (the one field
  /// neither WAV nor FLAC need, since both use a plain 32-bit integer).
  /// Unlike 32/64-bit IEEE floats, the 80-bit format's mantissa has an
  /// *explicit* leading integer bit rather than an implicit one, so the
  /// decode is: value = sign * (64-bit mantissa, as an integer) *
  /// 2^(exponent - 63) — the `- 63` accounts for the mantissa being a
  /// whole 64-bit integer rather than a fraction in `[1, 2)`.
  static double _decodeExtended80(List<int> bytes) {
    final sign = (bytes[0] & 0x80) != 0 ? -1.0 : 1.0;
    final exponent = (((bytes[0] & 0x7F) << 8) | bytes[1]) - 16383;
    var mantissa = 0.0;
    for (var i = 2; i < 10; i++) {
      mantissa = mantissa * 256 + bytes[i];
    }
    return sign * mantissa * math.pow(2.0, exponent - 63);
  }

  /// Reads just the first Ogg page's payload — the identification
  /// header packet, for both Vorbis and Opus streams — to determine
  /// sample rate/channels. Deliberately does not look inside the
  /// payload's own codec-specific bitrate story the way MP3's Xing tag
  /// does: Vorbis's declared "nominal bitrate" is a rough target the
  /// encoder aimed for, not a computable-from-first-principles number
  /// the way PCM's `rate * channels * depth` is, and Opus's header
  /// carries no bitrate field at all (it's adaptive, no header-declared
  /// rate exists to report) — both left `null` rather than reported as
  /// if they were exact, the same "don't guess what can't be derived
  /// honestly" stance every other reader here already holds. Neither
  /// format has a fixed PCM bit depth to report either (both are lossy,
  /// decoded internally at whatever precision the decoder chooses), so
  /// `bitDepth` stays `null` too — the same convention MP3 already
  /// follows in this reader.
  static Future<AudioFormatInfo> _readOgg(File file) async {
    final raf = await file.open();
    try {
      final pageHeader = await raf.read(27);
      if (pageHeader.length < 27 ||
          pageHeader[0] != 0x4F || // O
          pageHeader[1] != 0x67 || // g
          pageHeader[2] != 0x67 || // g
          pageHeader[3] != 0x53) {
        // S
        return AudioFormatInfo.unknown;
      }
      final segmentCount = pageHeader[26];
      final segmentTable = await raf.read(segmentCount);
      if (segmentTable.length < segmentCount) {
        return const AudioFormatInfo(codec: 'Ogg');
      }
      // The first packet's total length is the sum of consecutive
      // 255-valued ("continues into the next segment") lacing values up
      // to and including the first one under 255 — for an id header
      // packet (always well under 255 bytes), that's just its own single
      // segment entry, but summing correctly handles the general case
      // instead of assuming exactly one segment.
      var packetLength = 0;
      for (final segmentSize in segmentTable) {
        packetLength += segmentSize;
        if (segmentSize < 255) break;
      }
      if (packetLength <= 0) {
        return const AudioFormatInfo(codec: 'Ogg');
      }
      final payload = await raf.read(packetLength);

      if (payload.length >= 30 &&
          payload[0] == 0x01 &&
          String.fromCharCodes(payload.sublist(1, 7)) == 'vorbis') {
        final channels = payload[11];
        final sampleRate = payload[12] |
            (payload[13] << 8) |
            (payload[14] << 16) |
            (payload[15] << 24);
        return AudioFormatInfo(
          codec: 'Ogg Vorbis',
          sampleRateHz: sampleRate > 0 ? sampleRate : null,
          channels: channels > 0 ? channels : null,
        );
      }

      if (payload.length >= 19 &&
          String.fromCharCodes(payload.sublist(0, 8)) == 'OpusHead') {
        final channels = payload[9];
        // Opus always decodes at 48kHz regardless of the header's own
        // "input sample rate" field (which just records the source
        // material's original rate for reference) — reporting 48000
        // matches what actually comes out of the decoder, the same
        // "report what's real" stance the rest of this reader takes.
        return AudioFormatInfo(
          codec: 'Opus',
          sampleRateHz: 48000,
          channels: channels > 0 ? channels : null,
        );
      }

      return const AudioFormatInfo(codec: 'Ogg');
    } finally {
      await raf.close();
    }
  }

  /// Reads an M4A/MP4 container's `moov` atom to find the audio track's
  /// real sample rate/channels/bit-depth/bitrate — an MP4 box tree, not a
  /// linear chunk format like WAV/AIFF or a page format like Ogg, so this
  /// walks `moov` → `trak` (the first one whose `mdia`/`hdlr` declares a
  /// `soun` handler, tolerating a video track appearing first) → `mdia` →
  /// `minf` → `stbl` → `stsd` → the first sample entry (`mp4a` for AAC,
  /// `alac` for Apple Lossless, anything else reported by its own fourcc).
  /// `moov` can appear anywhere in the file (some muxers put it after
  /// `mdat`), so the top-level scan walks every box until it's found or
  /// the file ends, without ever reading `mdat`'s actual audio data.
  ///
  /// The sample entry's own legacy fields (channel count/sample size/
  /// sample rate, present in every `mp4a`/`alac` entry for backward
  /// compatibility with pre-MP4 QuickTime) are read first, then
  /// overridden with more authoritative values where they exist: AAC's
  /// real sample rate/channel count live in `esds`'s buried
  /// `AudioSpecificConfig` (the legacy fields are commonly just
  /// placeholders for AAC specifically — a well-known MP4 quirk, not a
  /// guess), and ALAC's nested `alac` magic-cookie box carries its own
  /// authoritative bit depth (a real, meaningful field for a *lossless*
  /// codec, unlike AAC) plus sample rate/channels/average bitrate
  /// directly. AAC never gets a `bitDepth`, matching Ogg Vorbis/Opus's
  /// existing stance in this reader: it's lossy, decoded at whatever
  /// precision the decoder chooses, not a real fixed-width PCM value.
  /// A missing/malformed `esds` or `alac` cookie falls back to the
  /// legacy fields rather than losing everything already parsed; a
  /// missing/zero average-bitrate field falls back to a duration-derived
  /// estimate the same way FLAC's reader already does (`mdhd`'s
  /// timescale/duration against the whole file size).
  ///
  /// A bare `.aac` file (an ADTS elementary stream, not an MP4 container
  /// at all — a completely different frame-sync format, closer in shape
  /// to MP3) is deliberately not handled here; that's real, separate work.
  static Future<AudioFormatInfo> _readM4a(File file) async {
    final raf = await file.open();
    try {
      final fileLength = await file.length();
      final moovBytes = await _findTopLevelMp4Box(raf, fileLength, 'moov');
      if (moovBytes == null) {
        return const AudioFormatInfo(codec: 'AAC/ALAC (M4A)');
      }
      final moovChildren = _parseMp4Boxes(moovBytes);

      _Mp4Box? audioTrak;
      _Mp4Box? firstTrak;
      for (final trak in moovChildren.where((b) => b.type == 'trak')) {
        firstTrak ??= trak;
        final trakBytes = moovBytes.sublist(trak.start, trak.end);
        final mdia = _findMp4Box(_parseMp4Boxes(trakBytes), 'mdia');
        if (mdia == null) continue;
        final mdiaBytes = trakBytes.sublist(mdia.start, mdia.end);
        final hdlr = _findMp4Box(_parseMp4Boxes(mdiaBytes), 'hdlr');
        if (hdlr == null) continue;
        final hdlrBytes = mdiaBytes.sublist(hdlr.start, hdlr.end);
        if (hdlrBytes.length >= 12 &&
            String.fromCharCodes(hdlrBytes.sublist(8, 12)) == 'soun') {
          audioTrak = trak;
          break;
        }
      }
      final trak = audioTrak ?? firstTrak;
      if (trak == null) return const AudioFormatInfo(codec: 'AAC/ALAC (M4A)');

      final trakBytes = moovBytes.sublist(trak.start, trak.end);
      final trakChildren = _parseMp4Boxes(trakBytes);
      final mdiaBox = _findMp4Box(trakChildren, 'mdia');
      if (mdiaBox == null) return const AudioFormatInfo(codec: 'AAC/ALAC (M4A)');
      final mdiaBytes = trakBytes.sublist(mdiaBox.start, mdiaBox.end);
      final mdiaChildren = _parseMp4Boxes(mdiaBytes);

      int? timescale;
      int? durationUnits;
      final mdhdBox = _findMp4Box(mdiaChildren, 'mdhd');
      if (mdhdBox != null) {
        final mdhd = mdiaBytes.sublist(mdhdBox.start, mdhdBox.end);
        if (mdhd.isNotEmpty && mdhd[0] == 1 && mdhd.length >= 32) {
          timescale = _readU32(mdhd, 20);
          durationUnits = _readU64(mdhd, 24);
        } else if (mdhd.length >= 20) {
          timescale = _readU32(mdhd, 12);
          durationUnits = _readU32(mdhd, 16);
        }
      }

      final minfBox = _findMp4Box(mdiaChildren, 'minf');
      final stblBox = minfBox == null
          ? null
          : _findMp4Box(
              _parseMp4Boxes(mdiaBytes.sublist(minfBox.start, minfBox.end)),
              'stbl');
      if (minfBox == null || stblBox == null) {
        return AudioFormatInfo(
            codec: 'AAC/ALAC (M4A)', sampleRateHz: timescale);
      }
      final minfBytes = mdiaBytes.sublist(minfBox.start, minfBox.end);
      final stblBytes = minfBytes.sublist(stblBox.start, stblBox.end);
      final stsdBox = _findMp4Box(_parseMp4Boxes(stblBytes), 'stsd');
      if (stsdBox == null) {
        return AudioFormatInfo(
            codec: 'AAC/ALAC (M4A)', sampleRateHz: timescale);
      }
      final stsd = stblBytes.sublist(stsdBox.start, stsdBox.end);
      if (stsd.length < 8) {
        return AudioFormatInfo(
            codec: 'AAC/ALAC (M4A)', sampleRateHz: timescale);
      }
      // FullBox header(4) + entry_count(4), then the sample entries.
      final entriesBuf = stsd.sublist(8);
      final sampleEntries = _parseMp4Boxes(entriesBuf);
      if (sampleEntries.isEmpty) {
        return AudioFormatInfo(
            codec: 'AAC/ALAC (M4A)', sampleRateHz: timescale);
      }
      final entry = sampleEntries.first;
      final entryType = entry.type;
      final entryContent = entriesBuf.sublist(entry.start, entry.end);

      final codec = switch (entryType) {
        'mp4a' => 'AAC (M4A)',
        'alac' => 'ALAC (M4A)',
        _ => 'M4A ($entryType)',
      };

      int? channels;
      int? sampleRate;
      int? bitDepth;
      int? bitrateBps;

      if (entryContent.length >= 28) {
        final legacyChannels = _readU16(entryContent, 16);
        final legacySampleSize = _readU16(entryContent, 18);
        final legacySampleRate = _readU32(entryContent, 24) >> 16;
        channels = legacyChannels > 0 ? legacyChannels : null;
        bitDepth = legacySampleSize > 0 ? legacySampleSize : null;
        sampleRate = legacySampleRate > 0 ? legacySampleRate : null;
        // AAC is lossy — decoded at whatever precision the decoder
        // chooses, so the legacy sample-size field (a compatibility
        // placeholder, usually 16) isn't a real number to report.
        if (entryType == 'mp4a') bitDepth = null;

        // version 0's children start right after the fixed 28-byte
        // legacy fields; version 1 (rare for audio, common for some
        // uncompressed variants) inserts 16 more bytes first. Version 2
        // uses a different, larger layout not handled here — falls back
        // to the legacy fields above rather than misreading children.
        final version = _readU16(entryContent, 8);
        final childrenStart =
            version == 1 ? 44 : (version == 0 ? 28 : null);
        if (childrenStart != null && entryContent.length > childrenStart) {
          try {
            final childBuf = entryContent.sublist(childrenStart);
            final children = _parseMp4Boxes(childBuf);
            if (entryType == 'mp4a') {
              final esds = _findMp4Box(children, 'esds');
              if (esds != null) {
                final parsed =
                    _parseEsds(childBuf.sublist(esds.start, esds.end));
                if (parsed != null) {
                  sampleRate = parsed.sampleRate ?? sampleRate;
                  channels = parsed.channels ?? channels;
                  bitrateBps = parsed.avgBitrateBps;
                }
              }
            } else if (entryType == 'alac') {
              final alac = _findMp4Box(children, 'alac');
              if (alac != null) {
                final parsed =
                    _parseAlacCookie(childBuf.sublist(alac.start, alac.end));
                if (parsed != null) {
                  sampleRate = parsed.sampleRate ?? sampleRate;
                  channels = parsed.channels ?? channels;
                  bitDepth = parsed.bitDepth ?? bitDepth;
                  bitrateBps = parsed.avgBitrateBps;
                }
              }
            }
          } catch (_) {
            // Malformed nested box: keep the legacy-field values already
            // read above rather than losing them too.
          }
        }
      }

      int? bitrateKbps = bitrateBps != null && bitrateBps > 0
          ? (bitrateBps / 1000).round()
          : null;
      if (bitrateKbps == null &&
          timescale != null &&
          timescale > 0 &&
          durationUnits != null &&
          durationUnits > 0) {
        final durationSeconds = durationUnits / timescale;
        if (durationSeconds > 0) {
          bitrateKbps = ((fileLength * 8) / durationSeconds / 1000).round();
        }
      }

      return AudioFormatInfo(
        codec: codec,
        sampleRateHz: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
        bitrateKbps: bitrateKbps,
      );
    } finally {
      await raf.close();
    }
  }

  /// Scans top-level MP4 boxes from the start of the file until [type] is
  /// found (or the file ends), returning just that box's content bytes
  /// without ever reading past it — in particular, never reading `mdat`'s
  /// actual audio-sample data, which can be the overwhelming majority of
  /// the file. Handles the 64-bit box-size extension (`size == 1`,
  /// followed by an 8-byte real size) since a large `mdat` earlier in the
  /// file can legitimately need one, even though `moov` itself almost
  /// never does.
  static Future<Uint8List?> _findTopLevelMp4Box(
      RandomAccessFile raf, int fileLength, String type) async {
    var pos = 0;
    while (pos + 8 <= fileLength) {
      await raf.setPosition(pos);
      final header = await raf.read(8);
      if (header.length < 8) break;
      var size = _readU32(header, 0);
      final boxType = String.fromCharCodes(header.sublist(4, 8));
      var headerSize = 8;
      if (size == 1) {
        final ext = await raf.read(8);
        if (ext.length < 8) break;
        size = _readU64(ext, 0);
        headerSize = 16;
      } else if (size == 0) {
        size = fileLength - pos;
      }
      if (size < headerSize) break;
      if (boxType == type) {
        final contentSize = size - headerSize;
        if (contentSize <= 0) return Uint8List(0);
        await raf.setPosition(pos + headerSize);
        return await raf.read(contentSize);
      }
      pos += size;
    }
    return null;
  }

  /// Parses a byte buffer that is itself the *content* of some parent MP4
  /// box (i.e. already past that parent's own size+type header) into its
  /// immediate child boxes — [_Mp4Box.start]/[_Mp4Box.end] are content
  /// offsets within [bytes], each excluding that child's own header, so
  /// they're ready to hand straight to this same function again one level
  /// deeper. Stops (rather than throwing) at the first malformed or
  /// truncated box, returning whatever real children were found before it.
  static List<_Mp4Box> _parseMp4Boxes(List<int> bytes) {
    final boxes = <_Mp4Box>[];
    var pos = 0;
    while (pos + 8 <= bytes.length) {
      var size = _readU32(bytes, pos);
      final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
      var headerSize = 8;
      if (size == 1) {
        if (pos + 16 > bytes.length) break;
        size = _readU64(bytes, pos + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = bytes.length - pos;
      }
      if (size < headerSize) break;
      final contentEnd = pos + size;
      if (contentEnd > bytes.length) break;
      boxes.add(_Mp4Box(type, pos + headerSize, contentEnd));
      pos += size;
    }
    return boxes;
  }

  static _Mp4Box? _findMp4Box(List<_Mp4Box> boxes, String type) {
    for (final box in boxes) {
      if (box.type == type) return box;
    }
    return null;
  }

  static int _readU16(List<int> b, int off) => (b[off] << 8) | b[off + 1];

  static int _readU32(List<int> b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static int _readU64(List<int> b, int off) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | b[off + i];
    }
    return v;
  }

  static const _aacSampleRates = [
    96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050,
    16000, 12000, 11025, 8000, 7350,
  ];

  /// Parses an `esds` box's content (already past its own size+type
  /// header) down through the MPEG-4 descriptor chain — `ES_Descriptor`
  /// → `DecoderConfigDescriptor` (real average bitrate lives here) →
  /// `DecoderSpecificInfo` (an `AudioSpecificConfig` bitstream, read with
  /// an MSB-first bit reader since it's not byte-aligned: 5-bit object
  /// type, 4-bit sampling-frequency index — or an explicit 24-bit value
  /// when the index is the escape value `0xF` — then a 4-bit channel
  /// configuration). Each descriptor's length is itself a variable-length
  /// base-128 encoding (continuation bit `0x80`), not a fixed field.
  /// Returns whatever was successfully parsed even if a later piece (most
  /// often `DecoderSpecificInfo`, which not every `esds` bothers writing)
  /// is missing or malformed, rather than an all-or-nothing result.
  static _EsdsInfo? _parseEsds(List<int> content) {
    if (content.length < 5) return null;
    var pos = 4; // FullBox version(1) + flags(3)

    int readDescLen() {
      var len = 0;
      for (var i = 0; i < 4; i++) {
        if (pos >= content.length) throw const FormatException('esds');
        final b = content[pos++];
        len = (len << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      return len;
    }

    if (pos >= content.length || content[pos] != 0x03) return null;
    pos++; // ES_DescrTag
    readDescLen();
    pos += 2; // ES_ID
    if (pos >= content.length) return null;
    final flags = content[pos++];
    if (flags & 0x80 != 0) pos += 2; // streamDependenceFlag
    if (flags & 0x40 != 0) {
      if (pos >= content.length) return null;
      final urlLen = content[pos++];
      pos += urlLen;
    }
    if (flags & 0x20 != 0) pos += 2; // OCR stream

    if (pos >= content.length || content[pos] != 0x04) return null;
    pos++; // DecoderConfigDescrTag
    readDescLen();
    pos += 1; // objectTypeIndication
    pos += 1; // streamType/upStream/reserved
    pos += 3; // bufferSizeDB
    if (pos + 8 > content.length) return null;
    pos += 4; // maxBitrate
    final avgBitrate = _readU32(content, pos);
    pos += 4;
    final bitrateResult =
        _EsdsInfo(avgBitrateBps: avgBitrate > 0 ? avgBitrate : null);

    if (pos >= content.length || content[pos] != 0x05) return bitrateResult;
    pos++; // DecoderSpecificInfoTag
    final dsiLen = readDescLen();
    if (dsiLen < 2 || pos + dsiLen > content.length) return bitrateResult;
    final asc = content.sublist(pos, pos + dsiLen);

    var bitPos = 0;
    int readBits(int n) {
      var v = 0;
      for (var i = 0; i < n; i++) {
        final byteIndex = bitPos ~/ 8;
        if (byteIndex >= asc.length) throw const FormatException('asc');
        final bitIndex = 7 - (bitPos % 8);
        v = (v << 1) | ((asc[byteIndex] >> bitIndex) & 1);
        bitPos++;
      }
      return v;
    }

    try {
      final audioObjectType = readBits(5);
      if (audioObjectType == 31) readBits(6); // extended type, unused here
      final freqIndex = readBits(4);
      int? sampleRate;
      if (freqIndex == 0xF) {
        sampleRate = readBits(24);
      } else if (freqIndex < _aacSampleRates.length) {
        sampleRate = _aacSampleRates[freqIndex];
      }
      final channelConfig = readBits(4);
      int? channels;
      if (channelConfig >= 1 && channelConfig <= 6) {
        channels = channelConfig;
      } else if (channelConfig == 7) {
        channels = 8;
      }
      return _EsdsInfo(
        sampleRate: sampleRate,
        channels: channels,
        avgBitrateBps: bitrateResult.avgBitrateBps,
      );
    } catch (_) {
      return bitrateResult;
    }
  }

  /// Parses an `ALACSpecificConfig` "magic cookie" (a 24-byte fixed
  /// layout, unlike `esds`'s variable-length descriptors) nested inside
  /// an `alac` sample entry: `frameLength`(4), `compatibleVersion`(1),
  /// `bitDepth`(1), `pb`/`mb`/`kb`(1 each, ALAC's internal Rice-coding
  /// parameters — not needed here), `numChannels`(1), `maxRun`(2),
  /// `maxFrameBytes`(4), `avgBitRate`(4), `sampleRate`(4). Every field
  /// this reader actually surfaces — bit depth, channels, sample rate,
  /// bitrate — is stored directly and exactly, unlike AAC's `esds`: ALAC
  /// is lossless, so there's no lossy-encoder-hint ambiguity to navigate.
  static _AlacInfo? _parseAlacCookie(List<int> content) {
    if (content.length < 24) return null;
    final bitDepth = content[5];
    final channels = content[9];
    final avgBitRate = _readU32(content, 16);
    final sampleRate = _readU32(content, 20);
    return _AlacInfo(
      sampleRate: sampleRate > 0 ? sampleRate : null,
      channels: channels > 0 ? channels : null,
      bitDepth: bitDepth > 0 ? bitDepth : null,
      avgBitrateBps: avgBitRate > 0 ? avgBitRate : null,
    );
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
