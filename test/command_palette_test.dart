import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/command_palette.dart';

void main() {
  test('paletteCommands is pinned to the 11 spec-named commands this '
      'pass actually wires up — a change here should be deliberate, not '
      'silent drift', () {
    expect(
      paletteCommands.map((c) => c.id).toList(),
      [
        'play',
        'pause',
        'next',
        'previous',
        'shuffle',
        'open_settings',
        'enable_driving_mode',
        'open_lyrics',
        'change_theme',
        'customize_home',
        'scan_library',
      ],
    );
  });

  group('matchCommands', () {
    test('an empty query returns every command in its fixed order', () {
      expect(matchCommands(''), paletteCommands);
    });

    test('a whitespace-only query is treated the same as empty', () {
      expect(matchCommands('   '), paletteCommands);
    });

    test('matches case-insensitively against the title', () {
      final results = matchCommands('PLAY');
      expect(results.map((c) => c.id), containsAll(['play']));
    });

    test('matches against a keyword, not just the title', () {
      final results = matchCommands('preferences');
      expect(results.single.id, 'open_settings');
    });

    test('a query matching nothing returns an empty list', () {
      expect(matchCommands('xyzzy'), isEmpty);
    });

    test('a title starting with the query ranks above one that merely '
        'contains it', () {
      const commands = [
        PaletteCommand(id: 'contains', title: 'Something play related'),
        PaletteCommand(id: 'starts', title: 'Play something'),
      ];
      final results = matchCommands('play', commands);
      expect(results.first.id, 'starts');
    });

    test('a custom command list is used instead of the default when '
        'supplied', () {
      const custom = [PaletteCommand(id: 'custom', title: 'Custom Command')];
      expect(matchCommands('custom', custom).single.id, 'custom');
      expect(matchCommands('play', custom), isEmpty);
    });
  });
}
