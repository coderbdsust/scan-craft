import 'dart:convert';
import 'dart:io';

import '../../models/scan_document.dart';
import '../document_store.dart';
import '../export_service.dart';
import 'cloud_drive.dart';

/// Outcome of one sync run, for status display and tests.
class SyncReport {
  int uploaded = 0;
  int downloaded = 0;
  int deletedRemote = 0;
  int deletedLocal = 0;

  @override
  String toString() =>
      'uploaded $uploaded, downloaded $downloaded, deleted $deletedRemote remote / $deletedLocal local';
}

/// Two-way sync between the local library and a cloud folder.
///
/// Layout: `ScanCraft/<document name>/` holding `meta.json`, one JPEG per page
/// (named as on the device) and optionally a `<name>.pdf` copy for reading.
///
/// Rules:
/// * a document changed on one side only is copied to the other side;
/// * changed on both sides: the newest `modifiedAt` wins;
/// * deleted here: trashed in the cloud; deleted in the cloud and unchanged
///   here: deleted here;
/// * locked documents never leave the device (an existing cloud copy is
///   trashed when a document gets locked).
class DriveSyncEngine {
  DriveSyncEngine({required this.store, required this.cloud, ExportService? exporter})
      : exporter = exporter ?? ExportService(store);

  final DocumentStore store;
  final CloudDrive cloud;
  final ExportService exporter;

  static const rootFolderName = 'ScanCraft';
  static const metaName = 'meta.json';

  Future<SyncReport> run() async {
    final report = SyncReport();

    // 1. Root folder. If it had to be recreated (e.g. deleted in Drive), the
    // old ids mean nothing: treat everything as never uploaded instead of as
    // "deleted remotely".
    final knownRoot = store.driveRootFolderId;
    final root = await cloud.ensureRootFolder(rootFolderName, knownId: knownRoot);
    if (root != knownRoot) {
      if (knownRoot != null) _forgetRemoteState();
      store.driveRootFolderId = root;
      await store.saveSyncState();
    }

    // 2. Deletions made on this device.
    for (final folderId in store.pendingRemoteDeletes.toList()) {
      await cloud.trash(folderId);
      store.pendingRemoteDeletes.remove(folderId);
      report.deletedRemote++;
    }
    await store.saveSyncState();

    // 3. Reconcile.
    final remote = {for (final r in await cloud.listDocFolders(root)) r.docId: r};
    final everUploaded = store.documents.where((d) => d.sync.folderId != null).length;
    if (remote.isEmpty && everUploaded > 0) {
      // Nothing left in the cloud although we uploaded before: most likely
      // the folder was emptied by hand. Re-upload rather than wipe the device.
      _forgetRemoteState();
    }

    for (final doc in store.documents.toList()) {
      final r = remote.remove(doc.id);

      if (doc.locked) {
        final folderId = doc.sync.folderId ?? r?.folderId;
        if (folderId != null) {
          await cloud.trash(folderId);
          report.deletedRemote++;
        }
        doc.sync.reset();
        await store.saveSyncState();
        continue;
      }

      if (r == null) {
        if (doc.sync.folderId != null && !doc.hasUnsyncedChanges) {
          await store.removeFromRemote(doc.id); // deleted on another device
          report.deletedLocal++;
        } else {
          doc.sync.reset();
          await _push(doc, root);
          report.uploaded++;
        }
        continue;
      }

      doc.sync.folderId = r.folderId;
      final localChanged = doc.hasUnsyncedChanges;
      final remoteChanged = r.modifiedAt != doc.sync.syncedModifiedAt;
      if (localChanged && remoteChanged) {
        final remoteNewer = r.modifiedAt != null && r.modifiedAt!.isAfter(doc.modifiedAt);
        if (remoteNewer) {
          await _pull(r, existing: doc);
          report.downloaded++;
        } else {
          await _push(doc, root);
          report.uploaded++;
        }
      } else if (localChanged) {
        await _push(doc, root);
        report.uploaded++;
      } else if (remoteChanged) {
        await _pull(r, existing: doc);
        report.downloaded++;
      }
    }

    // 4. Documents that only exist in the cloud.
    for (final r in remote.values) {
      if (r.modifiedAt == null) continue; // upload still in progress elsewhere
      await _pull(r);
      report.downloaded++;
    }

    store.lastSyncAt = DateTime.now();
    await store.saveSyncState();
    return report;
  }

  void _forgetRemoteState() {
    for (final d in store.documents) {
      d.sync.reset();
    }
  }

  Future<void> _push(ScanDocument doc, String root) async {
    final sync = doc.sync;
    final folderId = sync.folderId ??= await cloud.createDocFolder(root, docId: doc.id, name: doc.name);

    // Page names are unique per content, so existing uploads never change.
    final wanted = doc.pages.toSet();
    for (final name in sync.pageFileIds.keys.toList()) {
      if (!wanted.contains(name)) {
        await cloud.trash(sync.pageFileIds.remove(name)!);
      }
    }
    for (var i = 0; i < doc.pages.length; i++) {
      final name = doc.pages[i];
      if (sync.pageFileIds.containsKey(name)) continue;
      final bytes = await store.pageFile(doc, i).readAsBytes();
      sync.pageFileIds[name] = await cloud.putFile(folderId, name, bytes, mimeType: 'image/jpeg');
      await store.saveSyncState(); // resume from here if interrupted
    }

    final folderName = store.folderById(doc.folderId)?.name;
    final meta = utf8.encode(jsonEncode(doc.toRemoteMeta(folderName: folderName)));
    sync.metaFileId = await cloud.putFile(folderId, metaName, meta,
        mimeType: 'application/json', fileId: sync.metaFileId);

    if (store.settings.syncPdfCopies && doc.pages.isNotEmpty) {
      final pdf = await exporter.exportPdf(doc);
      sync.pdfFileId = await cloud.putFile(
          folderId, '${ExportService.safeFileName(doc.name)}.pdf', await pdf.readAsBytes(),
          mimeType: 'application/pdf', fileId: sync.pdfFileId);
    } else if (sync.pdfFileId != null) {
      await cloud.trash(sync.pdfFileId!);
      sync.pdfFileId = null;
    }

    await cloud.commitDocFolder(folderId, name: doc.name, modifiedAt: doc.modifiedAt);
    sync.syncedModifiedAt = doc.modifiedAt;
    await store.saveSyncState();
  }

  Future<void> _pull(RemoteDocFolder r, {ScanDocument? existing}) async {
    final files = await cloud.listFiles(r.folderId);
    final metaId = files[metaName];
    if (metaId == null) return; // incomplete folder
    final meta = jsonDecode(utf8.decode(await cloud.download(metaId))) as Map<String, dynamic>;
    // The folder's commit time is authoritative for change detection.
    if (r.modifiedAt != null) meta['modifiedAt'] = r.modifiedAt!.toIso8601String();
    final pageNames = (meta['pages'] as List).cast<String>();

    // Pages already on the device (same name = same content) are not
    // downloaded again.
    final tmp = Directory('${store.tempDir.path}/pull_${DateTime.now().microsecondsSinceEpoch}');
    await tmp.create(recursive: true);
    try {
      final downloaded = <String, File>{};
      final local = existing?.pages.toSet() ?? const <String>{};
      for (final name in pageNames) {
        if (local.contains(name)) continue;
        final id = files[name];
        if (id == null) continue;
        final f = File('${tmp.path}/$name');
        await f.writeAsBytes(await cloud.download(id));
        downloaded[name] = f;
      }
      String? pdfId;
      for (final e in files.entries) {
        if (e.key.toLowerCase().endsWith('.pdf')) pdfId = e.value;
      }
      await store.upsertFromRemote(
        meta,
        downloaded,
        sync: DocSyncInfo(
          folderId: r.folderId,
          pageFileIds: {for (final n in pageNames) if (files[n] != null) n: files[n]!},
          metaFileId: metaId,
          pdfFileId: pdfId,
        ),
      );
    } finally {
      await tmp.delete(recursive: true);
    }
  }
}
