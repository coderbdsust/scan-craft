import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/scan_document.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
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

  String? _busy; // label of a running backup/restore

  /// Backups above this size go through the share sheet (streamed from a
  /// file) instead of the Save screen, which needs the bytes in memory.
  static const _maxSaveDialogBytes = 250 * 1024 * 1024;

  Future<void> _backup() async {
    if (store.documents.isEmpty) {
      showSnack(context, 'Nothing to back up yet.');
      return;
    }
    // The backup contains locked documents too, so ask for the same unlock.
    if (store.documents.any((d) => d.locked)) {
      final error = await AuthService.authenticate('Unlock to include locked documents in the backup');
      if (!mounted) return;
      if (error != null) {
        showSnack(context, error, error: true);
        return;
      }
    }
    setState(() => _busy = 'Creating backup…');
    File? zip;
    try {
      zip = await BackupService(store).createBackup();
      if (!mounted) return;
      setState(() => _busy = null);
      final name = zip.uri.pathSegments.last;
      if (await zip.length() > _maxSaveDialogBytes) {
        await SharePlus.instance.share(ShareParams(files: [XFile(zip.path)], subject: name));
      } else {
        final uri = await FilePicker.saveFile(
          fileName: name,
          bytes: await zip.readAsBytes(),
          mimeType: 'application/zip',
          dialogTitle: 'Save backup to Google Drive',
        );
        if (mounted && uri != null) showSnack(context, 'Backup saved: $name');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
      try {
        await zip?.delete();
      } catch (_) {}
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      dialogTitle: 'Choose a ScanCraft backup',
    );
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null || !mounted) return;
    setState(() => _busy = 'Restoring…');
    try {
      final (added, skipped) = await BackupService(store).restore(File(path));
      if (!mounted) return;
      showSnack(
        context,
        skipped == 0
            ? 'Restored $added document(s).'
            : 'Restored $added document(s); $skipped already on this device were kept.',
      );
    } catch (e) {
      if (mounted) showSnack(context, 'Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

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
          ListTile(
            title: const Text('Cropped page shape'),
            subtitle: const Text('Cropped pages are stretched to this paper shape'),
            trailing: DropdownButton<String>(
              value: s.pageShape,
              underline: const SizedBox.shrink(),
              items: [
                for (final p in PageShape.values)
                  DropdownMenuItem(value: p, child: Text(PageShape.label(p))),
              ],
              onChanged: (v) {
                if (v != null) _update((s) => s.pageShape = v);
              },
            ),
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
          _section('BACKUP TO GOOGLE DRIVE'),
          ListTile(
            leading: const Icon(Icons.add_to_drive, color: AppTheme.primaryGreen),
            title: const Text('Back up all documents'),
            subtitle: const Text(
                'Saves one backup file. In the Save screen pick Google Drive (☰ menu) and a folder.'),
            trailing: _busy == 'Creating backup…' ? const _Spinner() : null,
            enabled: _busy == null,
            onTap: _backup,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restore from backup'),
            subtitle: const Text('Pick a backup file (e.g. from Google Drive). Existing documents are kept.'),
            trailing: _busy == 'Restoring…' ? const _Spinner() : null,
            enabled: _busy == null,
            onTap: _restore,
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

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
