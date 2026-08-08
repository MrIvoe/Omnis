import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';

/// Draws [waveform]'s peaks as bars, colored up to the current playback
/// position, with the same drag-to-seek contract
/// `player_widgets.dart`'s `PlayerProgressBar` uses for its plain
/// [Slider]: [onSeek] fires continuously while dragging or on a direct
/// tap, [onSeekEnd] fires once on release.
class WaveformSeekBar extends StatelessWidget {
  final Waveform waveform;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onSeekEnd;
  final double height;

  const WaveformSeekBar({
    super.key,
    required this.waveform,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onSeekEnd,
    this.height = 56,
  });

  Duration _durationAtDx(double dx, double width) {
    if (width <= 0) return Duration.zero;
    final ratio = (dx / width).clamp(0.0, 1.0);
    return duration * ratio;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = duration.inMicroseconds > 0
        ? (position.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => onSeek(_durationAtDx(d.localPosition.dx, width)),
          onTapUp: (_) => onSeekEnd?.call(),
          onHorizontalDragStart: (d) =>
              onSeek(_durationAtDx(d.localPosition.dx, width)),
          onHorizontalDragUpdate: (d) =>
              onSeek(_durationAtDx(d.localPosition.dx, width)),
          onHorizontalDragEnd: (_) => onSeekEnd?.call(),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                waveform: waveform,
                progress: progress,
                playedColor: theme.colorScheme.primary,
                unplayedColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.24),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Waveform waveform;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.length == 0 || size.width <= 0) return;

    final barCount = size.width.floor().clamp(1, waveform.length);
    final barWidth = size.width / barCount;
    final midY = size.height / 2;

    // One pass over the whole waveform for the loudest sample, so every
    // bar's height is relative to the track's own peak — normalizing
    // per-bar instead would make quiet passages look as loud as the
    // chorus.
    var maxAbs = 1;
    for (var i = 0; i < waveform.length; i++) {
      final lo = waveform.getPixelMin(i).abs();
      final hi = waveform.getPixelMax(i).abs();
      if (lo > maxAbs) maxAbs = lo;
      if (hi > maxAbs) maxAbs = hi;
    }

    final playedPaint = Paint()..color = playedColor;
    final unplayedPaint = Paint()..color = unplayedColor;
    final playedBars = (barCount * progress).round();

    for (var bar = 0; bar < barCount; bar++) {
      final pixelIndex = (bar * waveform.length / barCount).floor();
      final top = midY -
          (waveform.getPixelMax(pixelIndex).abs() / maxAbs) * midY;
      final bottom = midY +
          (waveform.getPixelMin(pixelIndex).abs() / maxAbs) * midY;
      final rect = Rect.fromLTRB(
        bar * barWidth,
        top.clamp(0.0, size.height),
        bar * barWidth + barWidth * 0.7,
        bottom.clamp(0.0, size.height),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        bar < playedBars ? playedPaint : unplayedPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      !identical(oldDelegate.waveform, waveform) ||
      oldDelegate.progress != progress ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.unplayedColor != unplayedColor;
}
