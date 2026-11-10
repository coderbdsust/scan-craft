import 'dart:io';

import 'package:archive/archive_io.dart';

import 'document_store.dart';

/// Whole-library backups as a single .zip the user saves wherever they like
/// (e.g. Google Drive through the system "Save to" screen).
///
/// Layout: `library.json` plus `docs/<document id>/<page>.jpg`.
class BackupService {
  BackupService(this.store);

  final DocumentStore store;

  static const indexName = 'library.json';

  /// Suggested file name, e.g. `ScanCraft-backup-2026-11-10.zip`.
  static String fileName([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'ScanCraft-backup-${t.year}-${two(t.month)}-${two(t.day)}.zip';
  }

  /// Writes the backup into the app's temp folder and returns it.
  Future<File> createBackup() async {
    await store.tempDir.create(recursive: true);
    final zip = File('${store.tempDir.path}/${fileName()}');
    final index = File('${store.tempDir.path}/$indexName');
    await index.writeAsString(store.exportIndexJson());

    final encoder = ZipFileEncoder()..create(zip.path);
    try {
      await encoder.addFile(index, indexName);
      for (final doc in store.documents) {
        for (var i = 0; i < doc.pages.length; i++) {
          final page = store.pageFile(doc, i);
          if (await page.exists()) {
            await encoder.addFile(page, 'docs/${doc.id}/${doc.pages[i]}');
          }
        }
      }
    } finally {
      await encoder.close();
      await index.delete();
    }
    return zip;
  }

  // Only these entries are ever written to disk, so a crafted zip can't place
  // files outside the restore folder.
  static final _pagePath = RegExp(r'^docs/([A-Za-z0-9_-]+)/([A-Za-z0-9_.-]+\.jpg)$');

  /// Restores documents from a backup zip. Documents already on the device
  /// are kept as they are. Returns (added, skipped).
  Future<(int, int)> restore(File zip) async {
    final tmp = Directory('${store.tempDir.path}/restore_${DateTime.now().microsecondsSinceEpoch}');
    await tmp.create(recursive: true);
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      var hasIndex = false;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        String? target;
        if (name == indexName) {
          target = '${tmp.path}/$indexName';
          hasIndex = true;
        } else {
          final m = _pagePath.firstMatch(name);
          if (m == null || m.group(2)!.contains('..')) continue;
          target = '${tmp.path}/docs/${m.group(1)}/${m.group(2)}';
        }
        final bytes = entry.readBytes();
        if (bytes == null) continue;
        final out = File(target);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(bytes);
      }
      if (!hasIndex) {
        throw const FormatException('This file is not a ScanCraft backup (library.json missing).');
      }
      return await store.importBackup(tmp);
    } finally {
      await input.close();
      await tmp.delete(recursive: true);
    }
  }
}
