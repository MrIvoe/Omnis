import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis_plugins/tag_editor_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseTrack _track({
  String id = 't1',
  String title = 'Song',
  List<String> artists = const ['Artist'],
}) =>
    BaseTrack(
      id: id,
      title: title,
      artists: artists,
      album: 'Album',
      duration: 180,
      type: TrackType.local,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.initialize();
    tempDir = await Directory.systemTemp.createTemp('omnis_tag_editor_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File freshAudioFile() {
    // Untagged "audio file" — the realistic case TagEditorPlugin's
    // ensureId3v2Header workaround exists for. No leading 'ID3' bytes.
    final file = File('${tempDir.path}/song.mp3');
    file.writeAsBytesSync(List.filled(200, 0xFF));
    return file;
  }

  group('TagEditorPlugin read/write round trip', () {
    test('writing to a completely untagged file does not throw', () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      final ok = await plugin.writeTags(file.path, title: 'New Title');

      expect(ok, isTrue);
    });

    test('written title/artist/album/artwork round-trip through readTags',
        () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();
      final art = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);

      final ok = await plugin.writeTags(
        file.path,
        title: 'Sunrise',
        artist: 'Ava',
        album: 'Morning',
        artworkBytes: art,
      );
      expect(ok, isTrue);

      final tags = await plugin.readTags(file.path);
      expect(tags.title, 'Sunrise');
      expect(tags.artist, 'Ava');
      expect(tags.album, 'Morning');
      expect(tags.artwork, isNotNull);
    });

    test('extraFields round-trip as readable custom tags', () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      await plugin.writeTags(
        file.path,
        title: 'Sunrise',
        extraFields: {'GENRE': 'Electronic', 'BPM': '128'},
      );

      final tags = await plugin.readTags(file.path);
      expect(tags.genre, 'Electronic');
      expect(tags.bpm, '128');
    });

    test('replayGainValues parses standard ReplayGain TXXX tags', () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      await plugin.writeTags(
        file.path,
        title: 'Sunrise',
        extraFields: {
          'REPLAYGAIN_TRACK_GAIN': '-6.50 dB',
          'REPLAYGAIN_TRACK_PEAK': '0.988315',
          'REPLAYGAIN_ALBUM_GAIN': '-7.20 dB',
          'REPLAYGAIN_ALBUM_PEAK': '0.995000',
        },
      );

      final tags = await plugin.readTags(file.path);
      final gain = tags.replayGainValues;
      expect(gain, isNotNull);
      expect(gain!.trackGain, -6.50);
      expect(gain.trackPeak, 0.988315);
      expect(gain.albumGain, -7.20);
      expect(gain.albumPeak, 0.995000);
    });

    test('replayGainValues is case-insensitive (external scanners vary)', () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      await plugin.writeTags(
        file.path,
        title: 'Sunrise',
        extraFields: {'replaygain_track_gain': '-3.10 dB'},
      );

      final tags = await plugin.readTags(file.path);
      expect(tags.replayGainValues?.trackGain, -3.10);
    });

    test('replayGainValues is null when the file has no ReplayGain tags', () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      await plugin.writeTags(file.path, title: 'Sunrise');

      final tags = await plugin.readTags(file.path);
      expect(tags.replayGainValues, isNull);
    });

    test('a second, unrelated write does not lose fields from the first',
        () async {
      final plugin = TagEditorPlugin();
      final file = freshAudioFile();

      await plugin.writeTags(file.path, title: 'T', artist: 'A', album: 'Al');
      await plugin.writeTags(file.path, extraFields: {'GENRE': 'Rock'});

      final tags = await plugin.readTags(file.path);
      expect(tags.title, 'T', reason: 'must survive the second, unrelated write');
      expect(tags.artist, 'A');
      expect(tags.album, 'Al');
      expect(tags.genre, 'Rock');
    });

    test('reading an unreadable path returns empty tags, never throws',
        () async {
      final plugin = TagEditorPlugin();
      final tags = await plugin.readTags('${tempDir.path}/does_not_exist.mp3');
      expect(tags.isEmpty, isTrue);
    });

    test('writing to an unwritable path returns false, never throws',
        () async {
      final plugin = TagEditorPlugin();
      final ok = await plugin.writeTags(
        '${tempDir.path}/missing_dir/song.mp3',
        title: 'X',
      );
      expect(ok, isFalse);
    });
  });

  group('smart re-tag tracking', () {
    test('a track is not auto-tagged until explicitly marked', () {
      final plugin = TagEditorPlugin();
      expect(plugin.wasAutoTagged('t1'), isFalse);
    });

    test('marking persists across a fresh plugin instance', () async {
      final plugin = TagEditorPlugin();
      await plugin.markAutoTagged('t1');

      final freshInstance = TagEditorPlugin();
      // A fresh PluginStorage starts cold (its own `_prefs` is null until
      // something awaits it) even though it reads the same underlying
      // SharedPreferences store as `plugin`'s — warm it explicitly before
      // the synchronous check below.
      await freshInstance.storage.initialize();
      expect(freshInstance.wasAutoTagged('t1'), isTrue);
    });

    test('clearAutoTagged is the redo-anyway escape hatch', () async {
      final plugin = TagEditorPlugin();
      await plugin.markAutoTagged('t1');
      expect(plugin.wasAutoTagged('t1'), isTrue);

      await plugin.clearAutoTagged('t1');
      expect(plugin.wasAutoTagged('t1'), isFalse);
    });
  });

  group('artist separator splitting', () {
    test('splits on a default separator like "feat."', () {
      final plugin = TagEditorPlugin();
      expect(plugin.splitArtists('Artist1 feat. Artist2'),
          ['Artist1', 'Artist2']);
    });

    test('is case-insensitive and configurable', () async {
      final plugin = TagEditorPlugin();
      await plugin.setArtistSeparators(['x']);
      expect(plugin.splitArtists('Artist1 X Artist2'), ['Artist1', 'Artist2']);
    });

    test('leaves a plain artist name untouched when nothing matches', () {
      final plugin = TagEditorPlugin();
      // splitArtists only tokenizes where a configured separator actually
      // matches — plain names with no separator come back as the single,
      // unmodified original string, not word-split.
      expect(plugin.splitArtists('Solo Artist'), ['Solo Artist']);
      expect(plugin.splitArtists('SoloArtist'), ['SoloArtist']);
    });

    test('extracts a featured artist wrongly baked into the title', () {
      final plugin = TagEditorPlugin();
      final result =
          plugin.extractFeaturedArtistFromTitle('Song Title (feat. Artist2)');
      expect(result.title, 'Song Title');
      expect(result.featuredArtist, 'Artist2');
    });

    test('leaves a title with no featured-artist marker unchanged', () {
      final plugin = TagEditorPlugin();
      final result = plugin.extractFeaturedArtistFromTitle('Plain Title');
      expect(result.title, 'Plain Title');
      expect(result.featuredArtist, isNull);
    });

    test('cleanArtistFields moves a featured artist out of the title', () {
      final plugin = TagEditorPlugin();
      final track = _track(title: 'Song (ft. Guest)', artists: ['Main']);

      final cleaned = plugin.cleanArtistFields(track);

      expect(cleaned, isNotNull);
      expect(cleaned!.title, 'Song');
      expect(cleaned.artists, containsAll(['Main', 'Guest']));
    });

    test('cleanArtistFields returns null when nothing needs to change', () {
      final plugin = TagEditorPlugin();
      final track = _track(title: 'Plain Song', artists: ['Solo Artist']);

      // 'Solo Artist' contains no configured separator, so this is a
      // genuine no-op — the important behavior under test.
      expect(plugin.cleanArtistFields(track), isNull);
    });
  });
}
