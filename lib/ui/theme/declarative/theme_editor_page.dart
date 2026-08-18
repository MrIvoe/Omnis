import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/settings/settings_widgets.dart'
    show ColorIndicator, SliderListTile;
import 'package:omnis/ui/theme/declarative/declarative_omnis_theme.dart';
import 'package:omnis/ui/theme/declarative/theme_installer.dart'
    show ThemeInstallException;
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/theme/omnis_typography.dart';
import 'package:omnis/ui/widgets/color_picker_dialog.dart';

/// Turns a `camelCase` manifest key into a human title, e.g. `onPrimary`
/// -> `On primary`. Shared by the color-role rows and the font dropdown
/// so neither needs its own hand-maintained label table — a new
/// [ThemeManifest.recognizedColorKeys] entry or [OmnisTypography.allowedFonts]
/// key gets a sane label for free.
String _titleFromCamel(String key) {
  final spaced =
      key.replaceAllMapped(RegExp('(?<=[a-z0-9])[A-Z]'), (m) => ' ${m[0]}');
  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

/// Lets a user build their own [ThemeManifest] with a live Now Playing
/// preview, rather than only picking among the six built-in presets or
/// hand-writing YAML and importing it from a URL/file.
///
/// Every control here maps 1:1 to a field [ThemeManifest.parse] already
/// recognizes — see that class's own doc comment for why this editor
/// deliberately never grows a field beyond that closed set (a "custom
/// font URL" or "custom animation curve" field would reopen the exact
/// sandboxing question the closed-schema design exists to avoid).
///
/// Structural template: [LayoutEditorPage]
/// (`lib/ui/player_layouts/declarative/layout_editor_page.dart`) — same
/// state-management shape (plain `setState`, a name field, a "Save"
/// action that builds a manifest, installs it, selects it, and pops),
/// applied to [ThemeManifest] instead of `LayoutManifest`. Saving
/// produces a `ThemeManifest`-shaped JSON document — JSON is a valid
/// YAML subset — and installs it through exactly the same
/// [ThemeManager.installFromText] -> [ThemeManifest.parse] path an
/// imported `.yaml` file does.
class ThemeEditorPage extends StatefulWidget {
  final ThemeManager themeManager;

  /// Builds the [ThemeData] the live preview renders with — defaults to
  /// the real [DeclarativeOmnisTheme.build], the only builder production
  /// code ever passes. Overridable *only* for tests: that real path
  /// flows through `OmnisTypography.build` -> `google_fonts`, which
  /// attempts a genuine network font fetch on every rebuild and — a
  /// documented, pre-existing test-infrastructure dead end (see
  /// `docs/OMNIS_2_0_FINISHED_TASK.md`'s 2026-08-15 high-contrast entry,
  /// which hit and gave up on this exact problem) — leaks an unhandled
  /// async exception into whichever test happens to be running whenever
  /// that fetch eventually settles, confirmed there to survive even
  /// `GoogleFonts.config.allowRuntimeFetching = false`. Rather than
  /// re-fighting that same dead end, this widget's own tests inject a
  /// small font-network-free builder that still exercises the real
  /// color/shape wiring the preview actually needs to prove.
  @visibleForTesting
  final ThemeData Function(ThemeManifest manifest)? previewThemeBuilder;

  const ThemeEditorPage({
    super.key,
    required this.themeManager,
    this.previewThemeBuilder,
  });

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  final TextEditingController _nameController =
      TextEditingController(text: 'My Theme');
  bool _saving = false;

  Brightness _brightness = Brightness.dark;
  final Map<String, Color> _colors = _defaultColors(Brightness.dark);
  String _fontKey = OmnisTypography.defaultFont;
  double _textScale = 1.0;
  double _cornerRadius = 16.0;
  ThemeMotionStyle _motionStyle = ThemeMotionStyle.standard;

  bool _backgroundEnabled = false;
  String _backgroundType = 'color'; // 'color' | 'gradient'
  Color _backgroundSolidColor = const Color(0xFF16213E);
  final List<Color> _backgroundGradientStops = [
    const Color(0xFF16213E),
    const Color(0xFF0F0F1E),
  ];

  static Map<String, Color> _defaultColors(Brightness brightness) {
    final seeded =
        ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness);
    return {
      'primary': seeded.primary,
      'secondary': seeded.secondary,
      'surface': seeded.surface,
      'background': seeded.surface,
      'error': seeded.error,
      'onPrimary': seeded.onPrimary,
      'onSecondary': seeded.onSecondary,
      'onSurface': seeded.onSurface,
      'onError': seeded.onError,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The in-progress manifest, rebuilt on every `setState` — feeds both
  /// the live preview and (at save time, after a JSON round trip through
  /// [ThemeManifest.parse] for real validation) the installed theme.
  ThemeManifest _liveManifest() {
    final name = _nameController.text.trim();
    return ThemeManifest(
      id: '_preview',
      name: name.isEmpty ? 'My Theme' : name,
      description: 'A custom theme you designed.',
      author: 'You',
      version: '1.0.0',
      brightness: _brightness,
      colors: Map.of(_colors),
      fontKey: _fontKey,
      textScale: _textScale,
      cornerRadius: _cornerRadius,
      motionStyle: _motionStyle,
      background: _backgroundJson(),
      sourceUrl: 'local',
    );
  }

  Map<String, dynamic>? _backgroundJson() {
    if (!_backgroundEnabled) return null;
    final colors = _backgroundType == 'gradient'
        ? _backgroundGradientStops.map(ColorPickerDialog.colorToHex).toList()
        : [ColorPickerDialog.colorToHex(_backgroundSolidColor)];
    return {'type': _backgroundType, 'colors': colors};
  }

  Map<String, dynamic> _manifestJson(String id, String name) {
    return {
      'id': id,
      'name': name,
      'description': 'A custom theme you designed.',
      'author': 'You',
      'version': '1.0.0',
      'brightness': _brightness == Brightness.light ? 'light' : 'dark',
      'colors': {
        for (final key in ThemeManifest.recognizedColorKeys)
          key: ColorPickerDialog.colorToHex(_colors[key]!),
      },
      'typography': {'fontFamily': _fontKey, 'scale': _textScale},
      'shape': {'cornerRadius': _cornerRadius},
      'motion': {
        'style': switch (_motionStyle) {
          ThemeMotionStyle.snappy => 'snappy',
          ThemeMotionStyle.gentle => 'gentle',
          ThemeMotionStyle.standard => 'standard',
        },
      },
      if (_backgroundJson() case final background?) 'background': background,
    };
  }

  Future<void> _pickColor({
    required String title,
    required Color initial,
    required ValueChanged<Color> onPicked,
  }) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => ColorPickerDialog(initialColor: initial, title: title),
    );
    if (picked != null && mounted) setState(() => onPicked(picked));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Give your theme a name.');
      return;
    }

    setState(() => _saving = true);
    final id = 'custom_theme_${DateTime.now().millisecondsSinceEpoch}';
    final text = jsonEncode(_manifestJson(id, name));

    // Validate our own generator's output before persisting — the task
    // (and this class's own contract) is clear that a parse() failure on
    // our own generated text is a bug in the generator above, never a
    // reason to skip validation and install unchecked text.
    if (ThemeManifest.parse(text, sourceUrl: 'local') == null) {
      if (mounted) {
        _toast('Could not build a valid theme from these settings — this '
            'is a bug, please report it.');
        setState(() => _saving = false);
      }
      return;
    }

    try {
      final theme = await widget.themeManager.installFromText(text);
      AppSettings.instance.customThemeId = theme.id;
      if (mounted) Navigator.of(context).pop(true);
    } on ThemeInstallException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = _liveManifest();
    final previewTheme =
        (widget.previewThemeBuilder ?? DeclarativeOmnisTheme.build)(manifest);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Theme name',
          ),
          style: theme.textTheme.titleLarge,
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Theme(
              data: previewTheme,
              child: _ThemePreview(manifest: manifest),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: const ValueKey('theme_editor_controls_list'),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _SectionHeader('Brightness'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<Brightness>(
                    key: const ValueKey('brightness_toggle'),
                    segments: const [
                      ButtonSegment(
                          value: Brightness.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark')),
                      ButtonSegment(
                          value: Brightness.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light')),
                    ],
                    selected: {_brightness},
                    onSelectionChanged: (value) =>
                        setState(() => _brightness = value.first),
                  ),
                ),
                const _SectionHeader('Colors'),
                for (final key in ThemeManifest.recognizedColorKeys)
                  ListTile(
                    key: ValueKey('theme_color_$key'),
                    title: Text(_titleFromCamel(key)),
                    trailing: ColorIndicator(color: _colors[key]!),
                    onTap: () => _pickColor(
                      title: 'Choose ${_titleFromCamel(key)} color',
                      initial: _colors[key]!,
                      onPicked: (c) => _colors[key] = c,
                    ),
                  ),
                const _SectionHeader('Typography'),
                ListTile(
                  title: const Text('Font'),
                  trailing: DropdownButton<String>(
                    key: const ValueKey('font_dropdown'),
                    value: _fontKey,
                    items: [
                      for (final key in OmnisTypography.allowedFonts.keys)
                        DropdownMenuItem(
                            value: key, child: Text(_titleFromCamel(key))),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _fontKey = value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Only fonts registered in OmnisTypography are offered '
                    'here. A theme file naming any other font (e.g. one '
                    'imported from elsewhere) silently falls back to '
                    '${_titleFromCamel(OmnisTypography.defaultFont)} — the '
                    'same rule this dropdown enforces up front.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                SliderListTile(
                  key: const ValueKey('scale_slider'),
                  title: 'Text scale',
                  value: _textScale,
                  min: 0.8,
                  max: 1.3,
                  divisions: 50,
                  label: _textScale.toStringAsFixed(2),
                  onChanged: (value) => setState(() => _textScale = value),
                ),
                const _SectionHeader('Shape'),
                SliderListTile(
                  key: const ValueKey('corner_radius_slider'),
                  title: 'Corner radius',
                  value: _cornerRadius,
                  min: 0,
                  max: 32,
                  divisions: 32,
                  label: _cornerRadius.toStringAsFixed(0),
                  onChanged: (value) => setState(() => _cornerRadius = value),
                ),
                const _SectionHeader('Motion'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<ThemeMotionStyle>(
                    key: const ValueKey('motion_selector'),
                    segments: const [
                      ButtonSegment(
                          value: ThemeMotionStyle.standard,
                          label: Text('Standard')),
                      ButtonSegment(
                          value: ThemeMotionStyle.snappy,
                          label: Text('Snappy')),
                      ButtonSegment(
                          value: ThemeMotionStyle.gentle,
                          label: Text('Gentle')),
                    ],
                    selected: {_motionStyle},
                    onSelectionChanged: (value) =>
                        setState(() => _motionStyle = value.first),
                  ),
                ),
                const _SectionHeader('Background'),
                SwitchListTile(
                  key: const ValueKey('background_toggle'),
                  title: const Text('Custom background'),
                  subtitle: const Text(
                      'Override Now Playing\'s background for this theme'),
                  value: _backgroundEnabled,
                  onChanged: (value) =>
                      setState(() => _backgroundEnabled = value),
                ),
                if (_backgroundEnabled) ..._buildBackgroundControls(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBackgroundControls(ThemeData theme) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<String>(
          key: const ValueKey('background_type_selector'),
          segments: const [
            ButtonSegment(value: 'color', label: Text('Solid color')),
            ButtonSegment(value: 'gradient', label: Text('Gradient')),
          ],
          selected: {_backgroundType},
          onSelectionChanged: (value) =>
              setState(() => _backgroundType = value.first),
        ),
      ),
      if (_backgroundType == 'color')
        ListTile(
          key: const ValueKey('background_solid_color_tile'),
          title: const Text('Background color'),
          trailing: ColorIndicator(color: _backgroundSolidColor),
          onTap: () => _pickColor(
            title: 'Choose background color',
            initial: _backgroundSolidColor,
            onPicked: (c) => _backgroundSolidColor = c,
          ),
        )
      else ...[
        for (var i = 0; i < _backgroundGradientStops.length; i++)
          ListTile(
            key: ValueKey('background_gradient_stop_$i'),
            title: Text('Stop ${i + 1}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorIndicator(color: _backgroundGradientStops[i]),
                if (_backgroundGradientStops.length > 2)
                  IconButton(
                    key: ValueKey('remove_gradient_stop_$i'),
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove stop',
                    onPressed: () =>
                        setState(() => _backgroundGradientStops.removeAt(i)),
                  ),
              ],
            ),
            onTap: () => _pickColor(
              title: 'Choose stop ${i + 1} color',
              initial: _backgroundGradientStops[i],
              onPicked: (c) => _backgroundGradientStops[i] = c,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            key: const ValueKey('add_gradient_stop_button'),
            onPressed: () => setState(
                () => _backgroundGradientStops.add(_backgroundGradientStops.last)),
            icon: const Icon(Icons.add),
            label: const Text('Add stop'),
          ),
        ),
      ],
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// A mocked Now Playing screen rendered under the in-progress
/// [ThemeManifest] via [DeclarativeOmnisTheme.build] (applied by the
/// caller wrapping this in a [Theme]) — every color/font/shape control on
/// the page above updates this live, the same way a real Now Playing
/// screen would look once this theme is installed and selected.
///
/// [manifest.background] is interpreted here directly, matching
/// [ThemeManifest.background]'s own doc comment ("interpreted by
/// whatever renders Now Playing's background, not by this class") —
/// nothing in the shipped app wires that field into rendering yet, so
/// this preview's interpretation of it is illustrative, not a claim
/// that toggling it here changes the real Now Playing screen today.
class _ThemePreview extends StatelessWidget {
  final ThemeManifest manifest;

  const _ThemePreview({required this.manifest});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: SizedBox(
              width: 88,
              height: 88,
              child: Icon(Icons.music_note,
                  size: 36, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Text('Sample Track Title', style: theme.textTheme.titleMedium),
          Text('Sample Artist', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 0.4,
                minHeight: 4,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.skip_previous, color: scheme.onSurface),
              const SizedBox(width: 20),
              FilledButton(
                onPressed: () {},
                child: const Icon(Icons.play_arrow),
              ),
              const SizedBox(width: 20),
              Icon(Icons.skip_next, color: scheme.onSurface),
            ],
          ),
        ],
      ),
    );

    return DecoratedBox(
      key: const ValueKey('theme_editor_preview'),
      decoration: _backgroundDecoration(scheme),
      child: SingleChildScrollView(child: Center(child: content)),
    );
  }

  BoxDecoration _backgroundDecoration(ColorScheme scheme) {
    final background = manifest.background;
    if (background == null) {
      return BoxDecoration(color: scheme.surface);
    }
    final rawColors = background['colors'];
    final stops = <Color>[
      if (rawColors is List)
        for (final entry in rawColors)
          if (entry is String && ColorPickerDialog.colorFromHex(entry) != null)
            ColorPickerDialog.colorFromHex(entry)!,
    ];
    if (stops.isEmpty) return BoxDecoration(color: scheme.surface);
    if (background['type'] == 'gradient' && stops.length > 1) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: stops,
        ),
      );
    }
    return BoxDecoration(color: stops.first);
  }
}
