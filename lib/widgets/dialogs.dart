import 'package:flutter/material.dart';

import '../services/document_store.dart';
import '../theme/app_theme.dart';

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontFamily: 'Space Grotesk')),
      content: _PromptTextField(
        controller: controller,
        hint: hint,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Owns the dialog's TextEditingController so it is disposed exactly when the
/// dialog's widgets are unmounted (after the exit animation), not when the
/// pop result resolves. Disposing at pop-time corrupted rebuilds mid-exit.
class _PromptTextField extends StatefulWidget {
  const _PromptTextField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  State<_PromptTextField> createState() => _PromptTextFieldState();
}

class _PromptTextFieldState extends State<_PromptTextField> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: true,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: widget.onSubmitted,
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontFamily: 'Space Grotesk')),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: destructive ? ElevatedButton.styleFrom(backgroundColor: AppTheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Lets the user pick a folder (or "No folder"). Returns the chosen folder id
/// wrapped in a record so that "no folder" (null) is distinguishable from
/// dismissing the sheet.
Future<({String? folderId})?> showFolderPicker(BuildContext context, {String? current}) {
  final store = DocumentStore.instance;
  return showModalBottomSheet<({String? folderId})>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Move to folder',
                style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('No folder'),
            trailing: current == null ? const Icon(Icons.check, color: AppTheme.primaryGreen) : null,
            onTap: () => Navigator.pop(ctx, (folderId: null)),
          ),
          for (final f in store.folders)
            ListTile(
              leading: const Icon(Icons.folder, color: AppTheme.primaryGreen),
              title: Text(f.name),
              trailing: current == f.id ? const Icon(Icons.check, color: AppTheme.primaryGreen) : null,
              onTap: () => Navigator.pop(ctx, (folderId: f.id)),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('New folder…'),
            onTap: () async {
              final name = await showTextInputDialog(ctx, title: 'New folder', hint: 'Folder name', confirmLabel: 'Create');
              if (name == null || name.trim().isEmpty) return;
              final folder = await store.createFolder(name);
              if (ctx.mounted && folder != null) Navigator.pop(ctx, (folderId: folder.id));
            },
          ),
        ],
      ),
    ),
  );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? AppTheme.error : AppTheme.slate900,
      content: Text(message),
    ));
}
