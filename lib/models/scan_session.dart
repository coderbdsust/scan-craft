import 'dart:io';

/// In-memory session for pages captured during a scan batch.
/// Pages survive navigation between camera -> crop -> detail screens.
class ScanSession {
  ScanSession._();
  static final ScanSession instance = ScanSession._();

  final List<File> pages = [];

  int get pageCount => pages.length;

  void addPage(File file) {
    pages.add(file);
  }

  void removeAt(int index) {
    if (index >= 0 && index < pages.length) {
      pages.removeAt(index);
    }
  }

  File? get lastPage => pages.isEmpty ? null : pages.last;

  void clear() {
    for (final page in pages) {
      try {
        if (page.existsSync()) page.deleteSync();
      } catch (_) {
        // Ignore cleanup failures.
      }
    }
    pages.clear();
  }
}
