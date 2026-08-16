import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/library_statistics.dart';

BaseTrack _track({
  required String id,
  String album = 'Album',
  List<String> artists = const ['Artist'],
  List<String> genres = const [],
  int duration = 200,
  String? codec,
  int? bitrateKbps,
  int? bitDepth,
  int? sampleRateHz,
}) =>
    BaseTrack(
      id: id,
      title: 'Title $id',
      artists: artists,
      album: album,
      duration: duration,
      genres: genres,
      type: TrackType.local,
      codec: codec,
      bitrateKbps: bitrateKbps,
      bitDepth: bitDepth,
      sampleRateHz: sampleRateHz,
    );

void main() {
  group('LibraryStatistics.compute', () {
    test('an empty library returns all-zero/null stats without crashing',
        () {
      final stats = LibraryStatistics.compute(const []);

      expect(stats.trackCount, 0);
      expect(stats.albumCount, 0);
      expect(stats.artistCount, 0);
      expect(stats.genreCount, 0);
      expect(stats.totalDuration, Duration.zero);
      expect(stats.averageBitrateKbps, isNull);
      expect(stats.averageTrackLength, isNull);
      expect(stats.losslessCount, 0);
      expect(stats.lossyCount, 0);
      expect(stats.hiResCount, 0);
    });

    test('trackCount is just the input length', () {
      final tracks = [_track(id: '1'), _track(id: '2'), _track(id: '3')];
      expect(LibraryStatistics.compute(tracks).trackCount, 3);
    });

    test('albumCount counts unique album names', () {
      final tracks = [
        _track(id: '1', album: 'A'),
        _track(id: '2', album: 'A'),
        _track(id: '3', album: 'B'),
      ];
      expect(LibraryStatistics.compute(tracks).albumCount, 2);
    });

    test('a blank album never counts', () {
      final tracks = [_track(id: '1', album: ''), _track(id: '2', album: '  ')];
      expect(LibraryStatistics.compute(tracks).albumCount, 0);
    });

    test('artistCount counts unique artists across multi-artist tracks',
        () {
      final tracks = [
        _track(id: '1', artists: const ['Ava', 'Bo']),
        _track(id: '2', artists: const ['Bo']),
        _track(id: '3', artists: const ['Cy']),
      ];
      expect(LibraryStatistics.compute(tracks).artistCount, 3);
    });

    test('genreCount counts unique genres across multi-genre tracks', () {
      final tracks = [
        _track(id: '1', genres: const ['Rock', 'Pop']),
        _track(id: '2', genres: const ['Pop']),
      ];
      expect(LibraryStatistics.compute(tracks).genreCount, 2);
    });

    test('totalDuration sums every track\'s duration', () {
      final tracks = [
        _track(id: '1', duration: 100),
        _track(id: '2', duration: 200),
        _track(id: '3', duration: 50),
      ];
      expect(LibraryStatistics.compute(tracks).totalDuration,
          const Duration(seconds: 350));
    });

    test('averageTrackLength divides total duration by track count', () {
      final tracks = [
        _track(id: '1', duration: 100),
        _track(id: '2', duration: 300),
      ];
      expect(LibraryStatistics.compute(tracks).averageTrackLength,
          const Duration(seconds: 200));
    });

    test('averageBitrateKbps ignores tracks with an unknown bitrate', () {
      final tracks = [
        _track(id: '1', bitrateKbps: 320),
        _track(id: '2', bitrateKbps: null),
        _track(id: '3', bitrateKbps: 128),
      ];
      expect(LibraryStatistics.compute(tracks).averageBitrateKbps, 224);
    });

    test('averageBitrateKbps is null when no track has a known bitrate',
        () {
      final tracks = [_track(id: '1', bitrateKbps: null)];
      expect(LibraryStatistics.compute(tracks).averageBitrateKbps, isNull);
    });

    test('losslessCount only counts FLAC/WAV', () {
      final tracks = [
        _track(id: '1', codec: 'FLAC'),
        _track(id: '2', codec: 'WAV'),
        _track(id: '3', codec: 'MP3'),
      ];
      expect(LibraryStatistics.compute(tracks).losslessCount, 2);
    });

    test('lossyCount only counts known lossy codecs', () {
      final tracks = [
        _track(id: '1', codec: 'MP3'),
        _track(id: '2', codec: 'Opus'),
        _track(id: '3', codec: 'FLAC'),
      ];
      expect(LibraryStatistics.compute(tracks).lossyCount, 2);
    });

    test('AAC/ALAC (M4A) counts toward neither lossless nor lossy — an '
        'ambiguous container, not a guessable codec', () {
      final tracks = [_track(id: '1', codec: 'AAC/ALAC (M4A)')];
      final stats = LibraryStatistics.compute(tracks);
      expect(stats.losslessCount, 0);
      expect(stats.lossyCount, 0);
    });

    test('a null codec counts toward neither lossless nor lossy', () {
      final tracks = [_track(id: '1', codec: null)];
      final stats = LibraryStatistics.compute(tracks);
      expect(stats.losslessCount, 0);
      expect(stats.lossyCount, 0);
    });

    test('hiResCount counts a track meeting either the bit-depth or '
        'sample-rate threshold, not requiring both', () {
      final tracks = [
        _track(id: 'depth-only', bitDepth: 24, sampleRateHz: 44100),
        _track(id: 'rate-only', bitDepth: 16, sampleRateHz: 96000),
        _track(id: 'neither', bitDepth: 16, sampleRateHz: 44100),
      ];
      expect(LibraryStatistics.compute(tracks).hiResCount, 2);
    });

    test('a 48000Hz track exactly at the threshold counts as hi-res', () {
      final tracks = [_track(id: '1', sampleRateHz: 48000)];
      expect(LibraryStatistics.compute(tracks).hiResCount, 1);
    });

    test('unknown bit depth/sample rate never counts as hi-res', () {
      final tracks = [_track(id: '1')];
      expect(LibraryStatistics.compute(tracks).hiResCount, 0);
    });
  });
}
