import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';

/// Placeholder rows shown during the initial library scan, replacing what
/// used to be a single centered spinner with no sense of what's about to
/// appear. Row height follows [AppSettings.libraryDensity] — a compact
/// library shows more, shorter placeholder rows, matching what the real
/// list is about to render.
class LibraryShimmerList extends StatefulWidget {
  const LibraryShimmerList({super.key});

  @override
  State<LibraryShimmerList> createState() => _LibraryShimmerListState();
}

class _LibraryShimmerListState extends State<LibraryShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (!AppSettings.instance.reduceMotionEnabled) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        AppSettings.instance.libraryDensity == LibraryDensity.compact;
    final rowHeight = compact ? 56.0 : 72.0;
    final reduceMotion = AppSettings.instance.reduceMotionEnabled;
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: 0.4);

    Widget row() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: rowHeight - 16,
                height: rowHeight - 16,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: double.infinity,
                        height: 14,
                        color: base,
                        margin: const EdgeInsets.only(bottom: 8)),
                    Container(width: 140, height: 12, color: base),
                  ],
                ),
              ),
            ],
          ),
        );

    // Reduce-motion users still get the "content is coming" skeleton
    // shape — they just don't get the moving sweep, which is exactly
    // what "reduce motion" means: skip decorative motion, not the whole
    // affordance.
    if (reduceMotion) {
      return ListView.builder(
        itemCount: 10,
        itemBuilder: (context, index) => row(),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final t = _controller.value;
          return LinearGradient(
            colors: [base, highlight, base],
            stops: const [0.35, 0.5, 0.65],
            begin: Alignment(-1 - t * 2, 0),
            end: Alignment(1 - t * 2, 0),
          ).createShader(bounds);
        },
        child: ListView.builder(
          itemCount: 10,
          itemBuilder: (context, index) => row(),
        ),
      ),
    );
  }
}
