import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/scan_document.dart';
import '../../models/scan_session.dart';
import '../../services/auth_service.dart';
import '../../services/document_store.dart';
import '../../services/export_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_actions.dart';
import '../camera/camera_viewfinder_screen.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({super.key});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final store = DocumentStore.instance;
  late final ExportService _exporter = ExportService(store);
  final _notesController = TextEditingController();
  Timer? _notesDebounce;

  String? _docId;
  bool mgmtExpanded = true;
  bool _reordering = false;
  String? _busy; // label of a running export, null when idle

  ScanDocument? get _doc => _docId == null ? null : store.byId(_docId!);

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_docId == null) {
      _docId = ModalRoute.of(context)?.settings.arguments as String?;
      _notesController.text = _doc?.notes ?? '';
    }
  }

  @override
  void dispose() {
    _flushNotes();
    store.removeListener(_onStoreChanged);
    _notesController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onNotesChanged(String value) {
    _notesDebounce?.cancel();
    _notesDebounce = Timer(const Duration(milliseconds: 600), _flushNotes);
  }

  void _flushNotes() {
    _notesDebounce?.cancel();
    final id = _docId;
    if (id != null) store.setNotes(id, _notesController.text);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _rename(ScanDocument doc) async {
    final name = await showTextInputDialog(context, title: 'Rename document', initial: doc.name);
    if (name != null) await store.rename(doc.id, name);
  }

  Future<void> _move(ScanDocument doc) async {
    final picked = await showFolderPicker(context, current: doc.folderId);
    if (picked != null) await store.moveToFolder(doc.id, picked.folderId);
  }

  Future<void> _delete(ScanDocument doc) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete document?',
      message: '"${doc.name}" and its ${doc.pageCount} page(s) will be removed from this device.',
    );
    if (!ok || !mounted) return;
    Navigator.pop(context);
    await store.deleteDocument(doc.id);
  }

  Future<void> _runExport(String label, Future<void> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _sharePdf(ScanDocument doc) => _runExport('Building PDF…', () async {
        final file = await _exporter.exportPdf(doc);
        await _exporter.share([file], subject: doc.name);
      });

  Future<void> _shareJpgs(ScanDocument doc) => _runExport('Exporting images…', () async {
        final files = await _exporter.exportJpgs(doc);
        await _exporter.share(files, subject: doc.name);
      });

  Future<void> _toggleLock(ScanDocument doc, bool value) async {
    final error = await AuthService.authenticate(
        value ? 'Confirm to lock "${doc.name}"' : 'Confirm to unlock "${doc.name}"');
    if (!mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
    await store.setLocked(doc.id, value);
  }

  Future<void> _addPages(ScanDocument doc) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scan with camera'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Import from photos'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    ScanSession.instance.start(kind: doc.kind, targetDocId: doc.id);
    if (source == 'camera') {
      Navigator.pushNamed(context, '/camera', arguments: ScanMode.batch);
      return;
    }
    final picked = await ImagePicker().pickMultiImage(imageQuality: 95);
    if (picked.isEmpty || !mounted) return;
    for (final f in picked) {
      ScanSession.instance.addPage(File(f.path));
    }
    Navigator.pushNamed(context, '/crop');
  }

  Future<void> _editPage(ScanDocument doc, int index) async {
    // The editor works on a temporary copy; the saved page is replaced on Save.
    await store.tempDir.create(recursive: true);
    final copy = await store
        .pageFile(doc, index)
        .copy('${store.tempDir.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg');
    ScanSession.instance
      ..start(kind: doc.kind, targetDocId: doc.id, replacePageIndex: index)
      ..addPage(copy);
    if (mounted) Navigator.pushNamed(context, '/crop');
  }

  Future<void> _deletePage(ScanDocument doc, int index) async {
    if (doc.pageCount == 1) {
      await _delete(doc);
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Remove page ${index + 1}?',
      message: 'This page will be permanently removed from the document.',
      confirmLabel: 'Remove',
    );
    if (ok) await store.removePage(doc.id, index);
  }

  Future<void> _pageMenu(ScanDocument doc, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('View full size'),
              onTap: () => Navigator.pop(ctx, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('Crop & clean'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.error),
              title: const Text('Remove page', style: TextStyle(color: AppTheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'view':
        _viewPage(doc, index);
      case 'edit':
        await _editPage(doc, index);
      case 'delete':
        await _deletePage(doc, index);
    }
  }

  void _viewPage(ScanDocument doc, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Page ${index + 1} of ${doc.pageCount}'),
          ),
          body: InteractiveViewer(
            maxScale: 6,
            child: Center(child: Image.file(store.pageFile(doc, index))),
          ),
        ),
      ),
    );
  }

  Future<void> _addTag(ScanDocument doc) async {
    final tag = await showTextInputDialog(context, title: 'Add tag', hint: 'e.g. tax, 2025', confirmLabel: 'Add');
    if (tag != null) await store.addTag(doc.id, tag);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This document no longer exists.')),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.slate900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.document_scanner, color: AppTheme.primaryGreen, size: 18),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Document Inspection',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.slate600),
            onSelected: (v) {
              switch (v) {
                case 'rename':
                  _rename(doc);
                case 'move':
                  _move(doc);
                case 'add':
                  _addPages(doc);
                case 'delete':
                  _delete(doc);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder')),
              PopupMenuItem(value: 'add', child: Text('Add pages')),
              PopupMenuItem(value: 'delete', child: Text('Delete document', style: TextStyle(color: AppTheme.error))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildOfflineBanner(),
                  const SizedBox(height: 12),
                  _buildHeader(doc),
                  const SizedBox(height: 12),
                  _buildPages(doc),
                  const SizedBox(height: 12),
                  _buildOrganization(doc),
                  const SizedBox(height: 12),
                  _buildManagement(doc),
                  const SizedBox(height: 12),
                  _buildActions(doc),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (_busy != null)
            Positioned.fill(
              child: Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primaryGreen),
                      const SizedBox(height: 16),
                      Text(_busy!, style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.successGreen.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.successBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.successBorder,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user, color: AppTheme.primaryGreen, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '100% Offline Compatible',
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.successText,
                  ),
                ),
                Text(
                  'Saved to Device Storage • Zero Cloud Transmission',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.successText.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'LOCAL ONLY',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ScanDocument doc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.successGreen,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.successBorder),
            ),
            child: Icon(doc.kind == DocumentKind.idCard ? Icons.badge : Icons.description,
                color: AppTheme.primaryGreen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _rename(doc),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      doc.name,
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 18, color: AppTheme.slate400),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: doc.starred ? 'Unstar' : 'Star',
            icon: Icon(doc.starred ? Icons.star : Icons.star_border,
                color: doc.starred ? const Color(0xFFF59E0B) : AppTheme.slate500),
            onPressed: () => store.setStarred(doc.id, !doc.starred),
          ),
          IconButton(
            tooltip: 'Share as PDF',
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => _sharePdf(doc),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPages(ScanDocument doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Scanned Sheets',
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.slate900,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.successBorder.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pluralize(doc.pageCount, 'Page'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successText,
                    ),
                  ),
                ),
              ],
            ),
            if (doc.pageCount > 1)
              TextButton.icon(
                onPressed: () => setState(() => _reordering = !_reordering),
                icon: Icon(_reordering ? Icons.check : Icons.swap_vert, size: 16),
                label: Text(_reordering ? 'Done' : 'Reorder'),
              ),
          ],
        ),
        if (_reordering)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Long-press and drag a page to move it.',
                style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 222,
          child: _reordering
              ? ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: doc.pageCount,
                  onReorderItem: (from, to) => store.reorderPages(doc.id, from, to),
                  itemBuilder: (context, i) => Padding(
                    key: ValueKey(doc.pages[i]),
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildPageThumbnail(doc, i),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < doc.pageCount; i++) ...[
                      GestureDetector(
                        onTap: () => _pageMenu(doc, i),
                        child: _buildPageThumbnail(doc, i),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: () => _addPages(doc),
                      child: Container(
                        width: 128,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.slate300, style: BorderStyle.solid),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.slate100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_photo_alternate, color: AppTheme.primaryGreen),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '+ Page',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate800,
                              ),
                            ),
                            Text(
                              'Camera / Files',
                              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildOrganization(ScanDocument doc) {
    final folder = store.folderById(doc.folderId);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.successBorder,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(folder == null ? Icons.folder_off_outlined : Icons.folder, color: AppTheme.primaryGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOLDER DESTINATION',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: AppTheme.slate500,
                        ),
                      ),
                      Text(
                        folder?.name ?? 'Unfiled',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate900,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _move(doc),
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Move'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate100),
            ),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildMetaItem(Icons.calendar_today, 'Created', formatDate(doc.createdAt)),
                _buildMetaItem(Icons.storage, 'File Weight', formatBytes(store.documentBytes(doc))),
                _buildMetaItem(Icons.auto_stories, 'Pages', '${doc.pageCount} Scanned'),
                _buildMetaItem(Icons.photo_size_select_large, 'Density', '${doc.dpi} DPI'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CLASSIFICATION TAGS',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppTheme.slate500,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.offline_bolt, size: 13, color: AppTheme.primaryGreen),
                      const SizedBox(width: 4),
                      Text(
                        'Local Tags',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in doc.tags) _buildTag(doc, t),
                  ActionChip(
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14),
                        SizedBox(width: 4),
                        Text('Add Tag'),
                      ],
                    ),
                    onPressed: () => _addTag(doc),
                    backgroundColor: AppTheme.successGreen,
                    side: BorderSide(color: AppTheme.successBorder),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManagement(ScanDocument doc) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: const Border(
                bottom: BorderSide(color: AppTheme.slate200),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.successBorder,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, color: AppTheme.primaryGreen, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Export Quality',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate900,
                        ),
                      ),
                      Text(
                        'Applied to PDF & JPG exports • originals are kept',
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(mgmtExpanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.slate400),
                  onPressed: () => setState(() => mgmtExpanded = !mgmtExpanded),
                ),
              ],
            ),
          ),
          if (mgmtExpanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Scan Resolution (DPI)',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate700,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.successBorder),
                            ),
                            child: Text(
                              '${doc.dpi} DPI',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final (dpi, desc) in [(150, 'Compact'), (300, 'Standard'), (600, 'Max Quality')]) ...[
                            Expanded(
                              child: GestureDetector(
                                onTap: () => store.setDpi(doc.id, dpi),
                                child: _buildDPIOption('$dpi DPI', desc, doc.dpi == dpi),
                              ),
                            ),
                            if (dpi != 600) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: AppTheme.slate100),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Color Profile Mode',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final (profile, icon) in [
                            (ColorProfile.blackWhite, Icons.contrast),
                            (ColorProfile.color, Icons.palette),
                            (ColorProfile.grayscale, Icons.filter_b_and_w),
                          ]) ...[
                            Expanded(
                              child: GestureDetector(
                                onTap: () => store.setColorProfile(doc.id, profile),
                                child: _buildColorOption(icon, ColorProfile.label(profile), doc.colorProfile == profile),
                              ),
                            ),
                            if (profile != ColorProfile.grayscale) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: AppTheme.slate100),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Document Notes',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate700,
                            ),
                          ),
                          Text(
                            'Stored on this device',
                            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _notesController,
                        onChanged: _onNotesChanged,
                        onTapOutside: (_) {
                          FocusScope.of(context).unfocus();
                          _flushNotes();
                        },
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Add notes...',
                          hintStyle: TextStyle(color: AppTheme.slate400),
                          filled: true,
                          fillColor: AppTheme.slate50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.slate200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.slate200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.primaryGreen),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(ScanDocument doc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _sharePdf(doc),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareJpgs(doc),
                  icon: const Icon(Icons.image, color: AppTheme.tertiary),
                  label: const Text('Export JPG'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppTheme.slate100,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/sign', arguments: doc.id),
                  icon: Icon(doc.signed ? Icons.verified : Icons.draw, color: AppTheme.secondary),
                  label: Text(doc.signed ? 'Sign Again' : 'Sign Document'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppTheme.slate100,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.successBorder,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fingerprint, color: AppTheme.primaryGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biometric Lock',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slate900,
                        ),
                      ),
                      Text(
                        'Require Face ID, fingerprint or device PIN to open',
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: doc.locked,
                  onChanged: (val) => _toggleLock(doc, val),
                  activeThumbColor: AppTheme.primaryGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageThumbnail(ScanDocument doc, int index) {
    return Container(
      width: 128,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                height: 180,
                decoration: const BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: PageThumb(file: store.pageFile(doc, index), iconSize: 40),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Text(
                    'P. ${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
              ),
              if (!_reordering)
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _deletePage(doc, index),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppTheme.errorContainer,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: AppTheme.onErrorContainer, size: 14),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _reordering ? 'Drag to move' : 'Tap for options',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.slate700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(_reordering ? Icons.drag_indicator : Icons.more_horiz, size: 16, color: AppTheme.slate400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.slate400),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: AppTheme.slate500),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.slate800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTag(ScanDocument doc, String tag) {
    return Chip(
      label: Text(tag),
      deleteIcon: const Icon(Icons.cancel, size: 14),
      onDeleted: () => store.removeTag(doc.id, tag),
      backgroundColor: AppTheme.slate100,
      side: BorderSide(color: AppTheme.slate200),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppTheme.slate800,
      ),
      deleteIconColor: AppTheme.slate400,
    );
  }

  Widget _buildDPIOption(String dpi, String desc, bool selected) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.successGreen.withValues(alpha: 0.7) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? AppTheme.primaryGreen : AppTheme.slate200, width: selected ? 2 : 1),
      ),
      child: Column(
        children: [
          Text(
            dpi,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? AppTheme.primaryGreen : AppTheme.slate700,
            ),
          ),
          Text(
            desc,
            style: TextStyle(
              fontSize: 9,
              color: selected ? AppTheme.successText : AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorOption(IconData icon, String label, bool selected) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.successGreen.withValues(alpha: 0.7) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? AppTheme.primaryGreen : AppTheme.slate200, width: selected ? 2 : 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: selected ? AppTheme.primaryGreen : AppTheme.slate500),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? AppTheme.primaryGreen : AppTheme.slate700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
