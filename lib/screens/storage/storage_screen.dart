import 'package:flutter/material.dart';

import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_actions.dart';

/// Shows how much space the vault uses and lets the user free some up.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  final store = DocumentStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scans = store.scansBytes;
    final exports = store.exportsBytes;
    final docs = store.documents.toList()
      ..sort((a, b) => store.documentBytes(b).compareTo(store.documentBytes(a)));

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        title: const Text('Storage', style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatBytes(scans + exports),
                    style: const TextStyle(fontFamily: 'Space Grotesk', fontSize: 28, fontWeight: FontWeight.bold)),
                const Text('used by ScanCraft on this device', style: TextStyle(color: AppTheme.slate500)),
                const SizedBox(height: 16),
                _row(Icons.description, 'Scanned pages', formatBytes(scans), AppTheme.primaryGreen),
                const SizedBox(height: 8),
                _row(Icons.ios_share, 'Exported PDFs & JPGs', formatBytes(exports), AppTheme.tertiary),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: exports == 0
                      ? null
                      : () async {
                          await store.clearExports();
                          if (context.mounted) showSnack(context, 'Exported files cleared');
                        },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clear exported files'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Exports are re-created whenever you share. Your scans are not affected.',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('LARGEST DOCUMENTS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppTheme.slate500)),
          const SizedBox(height: 8),
          if (docs.isEmpty)
            const Text('No documents yet.', style: TextStyle(color: AppTheme.slate500))
          else
            for (final d in docs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 52,
                      child: PageThumb(file: d.pages.isEmpty ? null : store.pageFile(d, 0), locked: d.locked),
                    ),
                  ),
                  title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${pluralize(d.pageCount, 'page')} • ${formatRelative(d.updatedAt)}'),
                  trailing: Text(formatBytes(store.documentBytes(d)),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => openDocument(context, d),
                  onLongPress: () => showDocumentMenu(context, d),
                ),
              ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
