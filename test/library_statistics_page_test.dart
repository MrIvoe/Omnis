import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/ui/library_statistics_page.dart';

BaseTrack _track({
  required String id,
  String album = 'Album',
  List<String> artists = const ['Artist'],
  int duration = 200,
  String? codec,
  int? bitrateKbps,
}) =>
    BaseTrack(
      id: id,
      title: 'Title $id',
      artists: artists,
      album: album,
      duration: duration,
      type: TrackType.local,
      codec: codec,
      bitrateKbps: bitrateKbps,
    );

void main() {
  testWidgets('an empty library shows the empty state, not a crash',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LibraryStatisticsPage(tracks: []),
    ));

    expect(find.textContaining('empty'), findsOneWidget);
  });

  testWidgets('shows real counts, not placeholders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryStatisticsPage(tracks: [
        _track(id: '1', album: 'A', codec: 'FLAC', bitrateKbps: 900),
        _track(id: '2', album: 'B', codec: 'MP3', bitrateKbps: 320),
        _track(id: '3', album: 'C', codec: 'MP3', bitrateKbps: 128),
      ]),
    ));

    // Read each tile's own trailing value directly, rather than
    // find.text() on bare digit strings that collide across
    // unrelated tiles (several stats legitimately share a small
    // integer value).
    final values = <String, String>{
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        (tile.title as Text).data!: (tile.trailing as Text).data!,
    };

    expect(values['Tracks'], '3');
    expect(values['Albums'], '3');
    expect(values['Lossless tracks'], '1');
    expect(values['Lossy tracks'], '2');
  });

  testWidgets('total duration renders in a human-readable form',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LibraryStatisticsPage(tracks: [
        _track(id: '1', duration: 3600), // 1 hour
      ]),
    ));

    expect(find.text('Total duration'), findsOneWidget);
    expect(find.textContaining('1 h'), findsOneWidget);
  });
}
