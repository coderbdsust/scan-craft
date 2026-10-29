import 'dart:io';

import 'scan_document.dart';

/// In-memory batch of pages captured during one scan, before they are saved
/// to the library. Pages survive navigation between camera -> crop screens.
///
/// A session either creates a new document, appends to [targetDocId], or
/// (when [replacePageIndex] is set) replaces one page of [targetDocId].
class ScanSession {
  ScanSession._();
  static final ScanSession instance = ScanSession._();

  final List<File> pages = [];

  String kind = DocumentKind.document;
  String? targetDocId;
  int? replacePageIndex;

  int get pageCount => pages.length;

  void addPage(File file) {
    pages.add(file);
  }

  void removeAt(int index) {
    if (index >= 0 && index < pages.length) {
      final f = pages.removeAt(index);
      _deleteQuietly(f);
    }
  }

  File? get lastPage => pages.isEmpty ? null : pages.last;

  /// Starts a fresh session. Pending page files are temporary copies, so they
  /// are deleted.
  void start({String kind = DocumentKind.document, String? targetDocId, int? replacePageIndex}) {
    clear();
    this.kind = kind;
    this.targetDocId = targetDocId;
    this.replacePageIndex = replacePageIndex;
  }

  void clear() {
    for (final page in pages) {
      _deleteQuietly(page);
    }
    pages.clear();
    kind = DocumentKind.document;
    targetDocId = null;
    replacePageIndex = null;
  }

  static void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // Ignore cleanup failures.
    }
  }
}
