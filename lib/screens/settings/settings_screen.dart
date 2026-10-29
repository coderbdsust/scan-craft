import 'package:flutter/material.dart';

import '../../models/scan_document.dart';
import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dialogs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final store = DocumentStore.instance;

  Future<void> _update(void Function(AppSettings s) change) async {
    await store.updateSettings(change);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _section('SCANNING'),
          SwitchListTile(
            title: const Text('Auto-capture'),
            subtitle: const Text('Take the photo automatically once a page is detected and held steady'),
            value: s.autoCapture,
            activeThumbColor: AppTheme.primaryGreen,
            onChanged: (v) => _update((s) => s.autoCapture = v),
          ),
          _section('DEFAULTS FOR NEW DOCUMENTS'),
          ListTile(
            title: const Text('Export resolution'),
            trailing: DropdownButton<int>(
              value: s.defaultDpi,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 150, child: Text('150 DPI')),
                DropdownMenuItem(value: 300, child: Text('300 DPI')),
                DropdownMenuItem(value: 600, child: Text('600 DPI')),
              ],
              onChanged: (v) {
                if (v != null) _update((s) => s.defaultDpi = v);
              },
            ),
          ),
          ListTile(
            title: const Text('Color profile'),
            trailing: DropdownButton<String>(
              value: s.defaultColorProfile,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in ColorProfile.values)
                  DropdownMenuItem(value: p, child: Text(ColorProfile.label(p))),
              ],
              onChanged: (v) {
                if (v != null) _update((s) => s.defaultColorProfile = v);
              },
            ),
          ),
          _section('DATA'),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: AppTheme.error),
            title: const Text('Delete all documents', style: TextStyle(color: AppTheme.error)),
            subtitle: const Text('Removes every scan, folder and export from this device'),
            onTap: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Delete everything?',
                message: 'All ${store.documents.length} document(s) and folders will be permanently removed. '
                    'This cannot be undone.',
                confirmLabel: 'Delete all',
              );
              if (!ok) return;
              await store.deleteAll();
              if (context.mounted) showSnack(context, 'All documents deleted');
            },
          ),
          _section('ABOUT'),
          const ListTile(
            title: Text('ScanCraft'),
            subtitle: Text('Version 1.0.0 • Scans are processed and stored only on this device.'),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppTheme.slate500)),
      );
}
