import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scan_document.dart';
import '../services/auth_service.dart';
import '../services/document_store.dart';
import '../theme/app_theme.dart';
import 'dialogs.dart';

/// Opens a document, asking for biometrics first when it is locked.
Future<void> openDocument(BuildContext context, ScanDocument doc) async {
  if (doc.locked) {
    final error = await AuthService.authenticate('Unlock "${doc.name}"');
    if (!context.mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
  }
  Navigator.pushNamed(context, '/detail', arguments: doc.id);
}

/// Rename / star / move / delete menu shared by the library and storage views.
Future<void> showDocumentMenu(BuildContext context, ScanDocument doc) async {
  final store = DocumentStore.instance;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open'),
            onTap: () => Navigator.pop(ctx, 'open'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: Icon(doc.starred ? Icons.star : Icons.star_border),
            title: Text(doc.starred ? 'Remove star' : 'Star'),
            onTap: () => Navigator.pop(ctx, 'star'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('Move to folder'),
            onTap: () => Navigator.pop(ctx, 'move'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.error),
            title: const Text('Delete', style: TextStyle(color: AppTheme.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await openDocument(context, doc);
    case 'rename':
      final name = await showTextInputDialog(context, title: 'Rename document', initial: doc.name);
      if (name != null) await store.rename(doc.id, name);
    case 'star':
      await store.setStarred(doc.id, !doc.starred);
    case 'move':
      final picked = await showFolderPicker(context, current: doc.folderId);
      if (picked != null) await store.moveToFolder(doc.id, picked.folderId);
    case 'delete':
      final ok = await showConfirmDialog(
        context,
        title: 'Delete document?',
        message: '"${doc.name}" and its ${doc.pageCount} page(s) will be removed from this device.',
      );
      if (ok) await store.deleteDocument(doc.id);
  }
}

/// Thumbnail of a page image, or a lock/placeholder icon.
class PageThumb extends StatelessWidget {
  const PageThumb({super.key, this.file, this.locked = false, this.iconSize = 24});

  final File? file;
  final bool locked;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return Center(child: Icon(Icons.lock, color: AppTheme.tertiary, size: iconSize));
    }
    final f = file;
    if (f == null) {
      return Center(child: Icon(Icons.description, color: AppTheme.slate400, size: iconSize));
    }
    return Image.file(
      f,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 300,
      errorBuilder: (_, _, _) =>
          Center(child: Icon(Icons.broken_image_outlined, color: AppTheme.slate400, size: iconSize)),
    );
  }
}
