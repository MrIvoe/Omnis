import 'package:flutter/material.dart';

/// Small colored square used to preview the current accent color.
class ColorIndicator extends StatelessWidget {
  final Color color;

  const ColorIndicator({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
    );
  }
}

/// A `ListTile` whose subtitle is a `Slider` — the shape every numeric
/// setting on these pages uses (album art scale, short-track threshold,
/// volume, speed, pitch).
class SliderListTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;

  const SliderListTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}
