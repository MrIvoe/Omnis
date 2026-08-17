import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/app_update_checker.dart';
import 'package:omnis/core/omnis_version.dart';
import 'package:omnis/core/semver.dart';
import 'package:url_launcher/url_launcher.dart';

/// Version, updates, and community/support links — reached from the
/// Settings home page's "About" card (also searchable there). Combines
/// three previously-nonexistent things in one place: a real "auto
/// updater" (checks GitHub for a newer tagged release via
/// [AppUpdateService], distinct from [AppSettings.autoUpdateCheckEnabled]
/// which is specifically for *plugin* updates), and the project's
/// GitHub/Discord/donation links.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _githubUrl = 'https://github.com/MrIvoe/Omnis';
  static const _discordUrl = 'https://discord.gg/jQRyckRVup';
  static const _donateUrl = 'https://buy.stripe.com/9B6aEZ86Jf3q86ugbI8Zq00';

  final _updateService = AppUpdateService();
  bool _checking = false;

  /// The cached last-known update, re-validated against
  /// [omnisCoreVersion] on every read rather than trusted blindly — a
  /// value cached before the user manually updated by some other means
  /// would otherwise go on claiming an update is available forever.
  String? get _availableUpdate {
    final cached = AppSettings.instance.lastKnownAppUpdateVersion;
    if (cached == null) return null;
    return compareVersions(cached, omnisCoreVersion) > 0 ? cached : null;
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    try {
      final latest = await _updateService.checkForUpdate();
      AppSettings.instance.lastKnownAppUpdateVersion = latest;
      AppSettings.instance.lastAppUpdateCheckAt = DateTime.now();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(latest != null
            ? 'Update available: v$latest'
            : 'You\'re on the latest version.'),
      ));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Couldn\'t open $url'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = AppSettings.instance;
    final update = _availableUpdate;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.music_note),
              title: Text('Omnis'),
              subtitle: Text('Version $omnisCoreVersion'),
            ),
          ),
          if (update != null)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.system_update),
                title: Text('Update available: v$update'),
                subtitle: const Text('Tap to view it on GitHub'),
                onTap: () => _openLink('$_githubUrl/releases'),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Automatically check for updates'),
                  subtitle: Text(settings.lastAppUpdateCheckAt != null
                      ? 'Last checked: '
                          '${settings.lastAppUpdateCheckAt!.toLocal()}'
                      : 'Never checked yet'),
                  value: settings.autoAppUpdateCheckEnabled,
                  onChanged: (value) =>
                      setState(() => settings.autoAppUpdateCheckEnabled = value),
                ),
                ListTile(
                  title: const Text('Check for updates now'),
                  trailing: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onTap: _checking ? null : _checkForUpdates,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Community & support', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('GitHub'),
                  subtitle: const Text('Source code, issues, releases'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openLink(_githubUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('Discord'),
                  subtitle: const Text('Chat with the community'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openLink(_discordUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.favorite_border),
                  title: const Text('Support Omnis'),
                  subtitle: const Text('Donate to support development'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openLink(_donateUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
