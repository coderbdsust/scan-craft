import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scan_document.dart';

/// On-device library of documents and folders, persisted as JSON next to the
/// page images. Nothing here touches the network.
class DocumentStore extends ChangeNotifier {
  DocumentStore._();
  static final DocumentStore instance = DocumentStore._();

  late Directory _root;
  final List<ScanDocument> _documents = [];
  final List<DocFolder> _folders = [];
  AppSettings settings = AppSettings();
  bool _ready = false;

  // File sizes are cached and refreshed asynchronously, so screens never stat
  // files on the UI thread while building.
  // Google Drive sync state shared by all documents.
  String? driveRootFolderId;
  final Set<String> pendingRemoteDeletes = {}; // Drive folder ids to trash
  DateTime? lastSyncAt;

  final Map<String, int> _docBytes = {};
  int _exportsBytes = 0;
  int _sizeGen = 0;

  bool get isReady => _ready;
  Directory get root => _root;
  Directory get exportsDir => Directory('${_root.path}/exports');
  Directory get tempDir => Directory('${_root.path}/tmp');
  File get _indexFile => File('${_root.path}/library.json');

  /// Loads the library. [root] overrides the storage folder (used by tests).
  Future<void> init({Directory? root}) async {
    _root = root ?? Directory('${(await getApplicationDocumentsDirectory()).path}/scancraft');
    await _root.create(recursive: true);
    _documents.clear();
    _folders.clear();
    settings = AppSettings();
    driveRootFolderId = null;
    pendingRemoteDeletes.clear();
    lastSyncAt = null;
    if (await _indexFile.exists()) {
      try {
        final json = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
        for (final d in (json['documents'] as List? ?? const [])) {
          _documents.add(ScanDocument.fromJson(d as Map<String, dynamic>));
        }
        for (final f in (json['folders'] as List? ?? const [])) {
          _folders.add(DocFolder.fromJson(f as Map<String, dynamic>));
        }
        if (json['settings'] != null) {
          settings = AppSettings.fromJson(json['settings'] as Map<String, dynamic>);
        }
        final sync = json['sync'] as Map<String, dynamic>?;
        if (sync != null) {
          driveRootFolderId = sync['rootFolderId'] as String?;
          pendingRemoteDeletes.addAll((sync['pendingDeletes'] as List? ?? const []).cast<String>());
          final last = sync['lastSyncAt'] as String?;
          lastSyncAt = last == null ? null : DateTime.parse(last);
        }
      } catch (e) {
        debugPrint('ScanCraft: could not read library index: $e');
      }
    }
    _ready = true;
    _docBytes.clear();
    _exportsBytes = 0;
    notifyListeners();
    await refreshSizes();
  }

  /// The library index (documents, folders, settings) as JSON.
  String exportIndexJson() => jsonEncode({
        'version': 1,
        'documents': _documents.map((d) => d.toJson()).toList(),
        'folders': _folders.map((f) => f.toJson()).toList(),
        'settings': settings.toJson(),
      });

  Future<void> _save() async {
<<<<<<< Updated upstream
    final data = exportIndexJson();
=======
    final data = jsonEncode({
      'version': 1,
      'documents': _documents.map((d) => d.toJson()).toList(),
      'folders': _folders.map((f) => f.toJson()).toList(),
      'settings': settings.toJson(),
      'sync': {
        'rootFolderId': driveRootFolderId,
        'pendingDeletes': pendingRemoteDeletes.toList(),
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      },
    });
>>>>>>> Stashed changes
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(_indexFile.path);
  }

  Future<void> _commit() async {
    await _save();
    notifyListeners();
    unawaited(refreshSizes());
  }

  static final _rand = math.Random();
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  // ---------------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------------

  /// Newest first.
  List<ScanDocument> get documents =>
      List.unmodifiable(_documents.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  ScanDocument? byId(String id) {
    for (final d in _documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  Directory docDir(ScanDocument doc) => Directory('${_root.path}/docs/${doc.id}');

  File pageFile(ScanDocument doc, int index) => File('${docDir(doc).path}/${doc.pages[index]}');

  List<File> pageFiles(ScanDocument doc) =>
      [for (var i = 0; i < doc.pages.length; i++) pageFile(doc, i)];

  Future<String> _importPage(ScanDocument doc, File source) async {
    final dir = docDir(doc);
    await dir.create(recursive: true);
    final name = 'p_${_newId()}.jpg';
    await source.copy('${dir.path}/$name');
    return name;
  }

  Future<ScanDocument> createDocument(List<File> pages, {String kind = DocumentKind.document, String? name}) async {
    final now = DateTime.now();
    final doc = ScanDocument(
      id: _newId(),
      name: name ?? _defaultName(kind, now),
      createdAt: now,
      updatedAt: now,
      pages: [],
      dpi: settings.defaultDpi,
      colorProfile: settings.defaultColorProfile,
      kind: kind,
    );
    for (final p in pages) {
      doc.pages.add(await _importPage(doc, p));
    }
    _documents.add(doc);
    await _commit();
    return doc;
  }

  static String _defaultName(String kind, DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}';
    switch (kind) {
      case DocumentKind.idCard:
        return 'ID Card $stamp';
      case DocumentKind.book:
        return 'Book Scan $stamp';
      default:
        return 'Scan $stamp';
    }
  }

  /// Content change: moves the document to the top of "recent" and marks it
  /// for sync.
  Future<void> _touch(ScanDocument doc) async {
    final now = DateTime.now();
    doc.updatedAt = now;
    doc.modifiedAt = now;
    await _commit();
  }

  /// Metadata change (star, tags, notes...): marks it for sync only.
  Future<void> _modified(ScanDocument doc) async {
    doc.modifiedAt = DateTime.now();
    await _commit();
  }

  Future<void> addPages(String id, List<File> files) async {
    final doc = byId(id);
    if (doc == null) return;
    for (final f in files) {
      doc.pages.add(await _importPage(doc, f));
    }
    await _touch(doc);
  }

  Future<void> replacePage(String id, int index, File file) async {
    final doc = byId(id);
    if (doc == null || index < 0 || index >= doc.pages.length) return;
    final old = pageFile(doc, index);
    doc.pages[index] = await _importPage(doc, file);
    await _deleteQuietly(old);
    await _touch(doc);
  }

  Future<void> removePage(String id, int index) async {
    final doc = byId(id);
    if (doc == null || index < 0 || index >= doc.pages.length) return;
    final old = pageFile(doc, index);
    doc.pages.removeAt(index);
    await _deleteQuietly(old);
    await _touch(doc);
  }

  /// Moves a page; [newIndex] is its final position after removal.
  Future<void> reorderPages(String id, int oldIndex, int newIndex) async {
    final doc = byId(id);
    if (doc == null) return;
    final page = doc.pages.removeAt(oldIndex);
    doc.pages.insert(newIndex, page);
    await _touch(doc);
  }

  Future<void> rename(String id, String name) async {
    final doc = byId(id);
    final trimmed = name.trim();
    if (doc == null || trimmed.isEmpty) return;
    doc.name = trimmed;
    await _touch(doc);
  }

  Future<void> setStarred(String id, bool value) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.starred = value;
    await _modified(doc);
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.folderId = folderId;
    await _touch(doc);
  }

  Future<void> addTag(String id, String tag) async {
    final doc = byId(id);
    var t = tag.trim().replaceAll(RegExp(r'\s+'), '-').toLowerCase();
    if (doc == null || t.isEmpty) return;
    if (!t.startsWith('#')) t = '#$t';
    if (doc.tags.contains(t)) return;
    doc.tags.add(t);
    await _modified(doc);
  }

  Future<void> removeTag(String id, String tag) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.tags.remove(tag);
    await _modified(doc);
  }

  Future<void> setNotes(String id, String notes) async {
    final doc = byId(id);
    if (doc == null || doc.notes == notes) return;
    doc.notes = notes;
    await _modified(doc);
  }

  Future<void> setDpi(String id, int dpi) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.dpi = dpi;
    await _modified(doc);
  }

  Future<void> setColorProfile(String id, String profile) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.colorProfile = profile;
    await _modified(doc);
  }

  Future<void> setLocked(String id, bool locked) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.locked = locked;
    await _modified(doc);
  }

  Future<void> markSigned(String id) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.signed = true;
    await _touch(doc);
  }

  Future<void> deleteDocument(String id) async {
    final doc = byId(id);
    if (doc == null) return;
    _documents.remove(doc);
    // Remember to remove the Drive copy too on the next sync.
    final remote = doc.sync.folderId;
    if (remote != null) pendingRemoteDeletes.add(remote);
    final dir = docDir(doc);
    if (await dir.exists()) await dir.delete(recursive: true);
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  List<DocFolder> get folders =>
      List.unmodifiable(_folders.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  DocFolder? folderById(String? id) {
    if (id == null) return null;
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  List<ScanDocument> documentsIn(String folderId) =>
      documents.where((d) => d.folderId == folderId).toList();

  Future<DocFolder?> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final folder = DocFolder(id: _newId(), name: trimmed, createdAt: DateTime.now());
    _folders.add(folder);
    await _commit();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final folder = folderById(id);
    if (folder == null || name.trim().isEmpty) return;
    folder.name = name.trim();
    // Folder names travel with each document's metadata.
    final now = DateTime.now();
    for (final d in _documents) {
      if (d.folderId == id) d.modifiedAt = now;
    }
    await _commit();
  }

  /// Removes the folder; its documents become unfiled.
  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    final now = DateTime.now();
    for (final d in _documents) {
      if (d.folderId == id) {
        d.folderId = null;
        d.modifiedAt = now;
      }
    }
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Storage & settings
  // ---------------------------------------------------------------------------

  /// Cached size of a document's pages (0 until the first refresh finishes).
  int documentBytes(ScanDocument doc) => _docBytes[doc.id] ?? 0;

  int folderBytes(String folderId) =>
      documentsIn(folderId).fold(0, (sum, d) => sum + documentBytes(d));

  int get scansBytes => _documents.fold(0, (sum, d) => sum + documentBytes(d));

  int get exportsBytes => _exportsBytes;

  /// Re-measures every document and the exports folder with async file I/O,
  /// then notifies listeners if anything changed. Overlapping calls are
  /// collapsed: only the latest one publishes its result.
  Future<void> refreshSizes() async {
    final gen = ++_sizeGen;
    final docs = _documents.toList();
    final sizes = <String, int>{};
    for (final d in docs) {
      var total = 0;
      for (final f in pageFiles(d)) {
        try {
          total += await f.length();
        } catch (_) {}
      }
      sizes[d.id] = total;
    }
    final exports = await _dirBytes(exportsDir);
    if (gen != _sizeGen) return; // a newer refresh is running
    final changed = exports != _exportsBytes ||
        sizes.length != _docBytes.length ||
        sizes.entries.any((e) => _docBytes[e.key] != e.value);
    _docBytes
      ..clear()
      ..addAll(sizes);
    _exportsBytes = exports;
    if (changed) notifyListeners();
  }

  static Future<int> _dirBytes(Directory dir) async {
    var total = 0;
    try {
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } on FileSystemException catch (_) {
      // The folder was removed while being measured (e.g. "Clear exports").
    }
    return total;
  }

  /// Called after files are written to [exportsDir] so usage figures refresh.
  void exportsChanged() => unawaited(refreshSizes());

  Future<void> clearExports() async {
    if (await exportsDir.exists()) await exportsDir.delete(recursive: true);
    await refreshSizes();
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await _commit();
  }

  /// Deletes every document, folder and export. Settings are kept.
  Future<void> deleteAll() async {
    for (final d in _documents) {
      final remote = d.sync.folderId;
      if (remote != null) pendingRemoteDeletes.add(remote);
    }
    _documents.clear();
    _folders.clear();
    for (final dir in [Directory('${_root.path}/docs'), exportsDir, tempDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await _commit();
  }

<<<<<<< Updated upstream
  /// Merges a restored backup into the library. [root] holds the backup's
  /// `library.json` and `docs/<id>/` page folders. Documents that already
  /// exist here (same id) are kept as they are; folders are matched by name.
  /// Returns (added, skipped).
  Future<(int, int)> importBackup(Directory root) async {
    final json = jsonDecode(await File('${root.path}/library.json').readAsString()) as Map<String, dynamic>;
    final folderIdMap = <String, String>{};
    for (final f in (json['folders'] as List? ?? const [])) {
      final folder = DocFolder.fromJson(f as Map<String, dynamic>);
      final existing = _folders.where((x) => x.name == folder.name).firstOrNull;
      if (existing != null) {
        folderIdMap[folder.id] = existing.id;
      } else {
        final created = DocFolder(id: _newId(), name: folder.name, createdAt: folder.createdAt);
        _folders.add(created);
        folderIdMap[folder.id] = created.id;
      }
    }
    var added = 0, skipped = 0;
    for (final d in (json['documents'] as List? ?? const [])) {
      final doc = ScanDocument.fromJson(d as Map<String, dynamic>);
      if (byId(doc.id) != null) {
        skipped++;
        continue;
      }
      final src = Directory('${root.path}/docs/${doc.id}');
      final dir = docDir(doc);
      await dir.create(recursive: true);
      final present = <String>[];
      for (final name in doc.pages) {
        final f = File('${src.path}/$name');
        if (await f.exists()) {
          await f.copy('${dir.path}/$name');
          present.add(name);
        }
      }
      if (present.isEmpty) {
        await dir.delete(recursive: true);
        skipped++;
        continue;
      }
      doc.pages
        ..clear()
        ..addAll(present);
      doc.folderId = folderIdMap[doc.folderId];
      _documents.add(doc);
      added++;
    }
    await _commit();
    return (added, skipped);
=======
  // ---------------------------------------------------------------------------
  // Sync hooks (used by DriveSyncEngine)
  // ---------------------------------------------------------------------------

  /// Persists sync bookkeeping without counting as a user change.
  Future<void> saveSyncState() => _commit();

  DocFolder? folderByName(String name) {
    for (final f in _folders) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// Creates or replaces a document from its Drive copy. Page files keep the
  /// names listed in [meta] so Drive file ids map 1:1 across devices.
  Future<ScanDocument> upsertFromRemote(
    Map<String, dynamic> meta,
    Map<String, File> pageFiles, {
    required DocSyncInfo sync,
  }) async {
    final id = meta['id'] as String;
    final pageNames = (meta['pages'] as List).cast<String>();
    final existing = byId(id);
    final folderName = meta['folderName'] as String?;
    String? folderId;
    if (folderName != null && folderName.isNotEmpty) {
      folderId = (folderByName(folderName) ??
              await () async {
                final f = DocFolder(id: _newId(), name: folderName, createdAt: DateTime.now());
                _folders.add(f);
                return f;
              }())
          .id;
    }
    final modifiedAt = DateTime.parse(meta['modifiedAt'] as String);
    final doc = ScanDocument(
      id: id,
      name: meta['name'] as String,
      createdAt: DateTime.parse(meta['createdAt'] as String),
      updatedAt: DateTime.parse(meta['updatedAt'] as String),
      modifiedAt: modifiedAt,
      pages: List.of(pageNames),
      folderId: folderId,
      tags: (meta['tags'] as List? ?? const []).cast<String>().toList(),
      starred: meta['starred'] as bool? ?? false,
      notes: meta['notes'] as String? ?? '',
      dpi: meta['dpi'] as int? ?? 300,
      colorProfile: meta['colorProfile'] as String? ?? ColorProfile.color,
      signed: meta['signed'] as bool? ?? false,
      kind: meta['kind'] as String? ?? DocumentKind.document,
      sync: sync..syncedModifiedAt = modifiedAt,
    );
    final dir = docDir(doc);
    await dir.create(recursive: true);
    for (final name in pageNames) {
      final src = pageFiles[name];
      if (src != null) await src.copy('${dir.path}/$name');
    }
    if (existing != null) {
      // Drop pages that no longer exist remotely.
      for (final old in existing.pages) {
        if (!pageNames.contains(old)) await _deleteQuietly(File('${dir.path}/$old'));
      }
      _documents.remove(existing);
    }
    _documents.add(doc);
    await _commit();
    return doc;
  }

  /// Removes a document that was deleted on another device (no tombstone).
  Future<void> removeFromRemote(String id) async {
    final doc = byId(id);
    if (doc == null) return;
    _documents.remove(doc);
    final dir = docDir(doc);
    if (await dir.exists()) await dir.delete(recursive: true);
    await _commit();
>>>>>>> Stashed changes
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
