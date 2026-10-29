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
      } catch (e) {
        debugPrint('ScanCraft: could not read library index: $e');
      }
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final data = jsonEncode({
      'version': 1,
      'documents': _documents.map((d) => d.toJson()).toList(),
      'folders': _folders.map((f) => f.toJson()).toList(),
      'settings': settings.toJson(),
    });
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(_indexFile.path);
  }

  Future<void> _commit() async {
    await _save();
    notifyListeners();
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

  Future<void> _touch(ScanDocument doc) async {
    doc.updatedAt = DateTime.now();
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
    await _commit();
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
    await _commit();
  }

  Future<void> removeTag(String id, String tag) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.tags.remove(tag);
    await _commit();
  }

  Future<void> setNotes(String id, String notes) async {
    final doc = byId(id);
    if (doc == null || doc.notes == notes) return;
    doc.notes = notes;
    await _commit();
  }

  Future<void> setDpi(String id, int dpi) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.dpi = dpi;
    await _commit();
  }

  Future<void> setColorProfile(String id, String profile) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.colorProfile = profile;
    await _commit();
  }

  Future<void> setLocked(String id, bool locked) async {
    final doc = byId(id);
    if (doc == null) return;
    doc.locked = locked;
    await _commit();
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
    await _commit();
  }

  /// Removes the folder; its documents become unfiled.
  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    for (final d in _documents) {
      if (d.folderId == id) d.folderId = null;
    }
    await _commit();
  }

  // ---------------------------------------------------------------------------
  // Storage & settings
  // ---------------------------------------------------------------------------

  int documentBytes(ScanDocument doc) {
    var total = 0;
    for (final f in pageFiles(doc)) {
      try {
        total += f.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  int folderBytes(String folderId) =>
      documentsIn(folderId).fold(0, (sum, d) => sum + documentBytes(d));

  int get scansBytes => _documents.fold(0, (sum, d) => sum + documentBytes(d));

  int get exportsBytes => _dirBytes(exportsDir);

  static int _dirBytes(Directory dir) {
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final e in dir.listSync(recursive: true)) {
      if (e is File) {
        try {
          total += e.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Called after files are written to [exportsDir] so usage figures refresh.
  void exportsChanged() => notifyListeners();

  Future<void> clearExports() async {
    if (await exportsDir.exists()) await exportsDir.delete(recursive: true);
    notifyListeners();
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await _commit();
  }

  /// Deletes every document, folder and export. Settings are kept.
  Future<void> deleteAll() async {
    _documents.clear();
    _folders.clear();
    for (final dir in [Directory('${_root.path}/docs'), exportsDir, tempDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await _commit();
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
