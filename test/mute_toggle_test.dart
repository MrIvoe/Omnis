import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/mute_toggle.dart';

void main() {
  group('toggleMute', () {
    test('muting from a non-zero volume remembers it and returns 0.0', () {
      final result = toggleMute(0.7, null);

      expect(result.newVolume, 0.0);
      expect(result.volumeToRemember, 0.7);
    });

    test('unmuting restores the exact previously-remembered volume', () {
      final result = toggleMute(0.0, 0.7);

      expect(result.newVolume, 0.7);
      expect(result.volumeToRemember, isNull);
    });

    test('unmuting with no prior remembered state falls back to a full '
        '1.0 rather than leaving the user stuck silent', () {
      final result = toggleMute(0.0, null);

      expect(result.newVolume, 1.0);
      expect(result.volumeToRemember, isNull);
    });

    test('a real mute-then-unmute cycle round-trips to the exact '
        'starting volume', () {
      final muted = toggleMute(0.42, null);
      expect(muted.newVolume, 0.0);

      final unmuted = toggleMute(muted.newVolume, muted.volumeToRemember);
      expect(unmuted.newVolume, 0.42);
    });

    test('repeated toggling alternates correctly across several presses',
        () {
      double volume = 0.6;
      double? remembered;

      final first = toggleMute(volume, remembered); // mute
      volume = first.newVolume;
      remembered = first.volumeToRemember;
      expect(volume, 0.0);

      final second = toggleMute(volume, remembered); // unmute
      volume = second.newVolume;
      remembered = second.volumeToRemember;
      expect(volume, 0.6);

      final third = toggleMute(volume, remembered); // mute again
      volume = third.newVolume;
      remembered = third.volumeToRemember;
      expect(volume, 0.0);
      expect(remembered, 0.6);
    });

    test('volume changed externally while "muted" (still 0.0) does not '
        'crash and unmuting still restores the last remembered value',
        () {
      final muted = toggleMute(0.8, null);
      // Something else set the engine's volume to 0.0 too in the
      // meantime (a no-op from this toggle's perspective) — the
      // remembered value from the actual mute is still what should
      // come back.
      final unmuted = toggleMute(0.0, muted.volumeToRemember);
      expect(unmuted.newVolume, 0.8);
    });

    test('volume raised externally between a mute and the next press '
        'is treated as a fresh mute, not stale state', () {
      final muted = toggleMute(0.5, null);
      expect(muted.newVolume, 0.0);

      // The user dragged the volume slider up while "muted."
      const externallyRaisedVolume = 0.9;
      final result = toggleMute(externallyRaisedVolume, muted.volumeToRemember);

      expect(result.newVolume, 0.0);
      expect(result.volumeToRemember, externallyRaisedVolume);
    });

    test('a remembered volume of exactly 0.0 is treated the same as '
        'no remembered volume at all on unmute', () {
      final result = toggleMute(0.0, 0.0);
      expect(result.newVolume, 1.0);
    });
  });
}
