import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
import 'package:omnis/ui/widgets/artist_avatar.dart';

class _FakeProvider implements IArtistImageProvider {
  final String? Function(String) resolve;
  int calls = 0;

  _FakeProvider(this.resolve);

  @override
  bool get isAvailable => true;

  @override
  Future<String?> imageUrlFor(String artistName) async {
    calls++;
    return resolve(artistName);
  }
}

class _UnavailableProvider implements IArtistImageProvider {
  @override
  bool get isAvailable => false;

  @override
  Future<String?> imageUrlFor(String artistName) async =>
      throw StateError('must not be called while unavailable');
}

void main() {
  testWidgets('falls back to the person icon while no provider is registered',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ArtistAvatar(artistName: 'Ava', imageProvider: null),
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('falls back to the person icon when the provider is unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ArtistAvatar(
          artistName: 'Ava',
          imageProvider: _UnavailableProvider(),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('falls back to the person icon when the lookup finds nothing',
      (tester) async {
    final provider = _FakeProvider((_) => null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ArtistAvatar(artistName: 'Nobody', imageProvider: provider),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(provider.calls, 1);
  });

  testWidgets('does not query the provider for an empty artist name',
      (tester) async {
    final provider = _FakeProvider((_) => 'https://example.com/x.jpg');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ArtistAvatar(artistName: '', imageProvider: provider),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(provider.calls, 0);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });
}
