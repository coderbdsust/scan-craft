import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/scan_document.dart';
import '../../models/scan_session.dart';
import '../../services/document_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/document_actions.dart';
import '../camera/camera_viewfinder_screen.dart';

enum _SortMode { newest, oldest, name, size }

class DocumentsLibraryScreen extends StatefulWidget {
  const DocumentsLibraryScreen({super.key});

  @override
  State<DocumentsLibraryScreen> createState() => _DocumentsLibraryScreenState();
}

class _DocumentsLibraryScreenState extends State<DocumentsLibraryScreen> {
  final store = DocumentStore.instance;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  String selectedFilter = 'all';
  String? _folderFilter;
  bool _showAllFolders = false;
  bool _gridView = false;
  _SortMode _sort = _SortMode.newest;

  static const _folderStyles = [
    (Icons.folder, AppTheme.successGreen, AppTheme.successBorder, AppTheme.primaryGreen),
    (Icons.folder, Color(0x4D99EFE5), Color(0x4D006A63), AppTheme.secondary),
    (Icons.folder, Color(0x1A006194), Color(0x4D006194), AppTheme.tertiary),
  ];

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (_folderFilter != null && store.folderById(_folderFilter) == null) _folderFilter = null;
    if (mounted) setState(() {});
  }

  List<ScanDocument> get _visibleDocuments {
    final q = _searchController.text.trim().toLowerCase();
    final docs = store.documents.where((d) {
      if (_folderFilter != null && d.folderId != _folderFilter) return false;
      switch (selectedFilter) {
        case 'starred':
          if (!d.starred) return false;
        case 'id-cards':
          if (d.kind != DocumentKind.idCard) return false;
        case 'books':
          if (d.kind != DocumentKind.book) return false;
        case 'locked':
          if (!d.locked) return false;
      }
      if (q.isEmpty) return true;
      if (d.name.toLowerCase().contains(q)) return true;
      // Locked documents only match on their name.
      if (d.locked) return false;
      return d.tags.any((t) => t.contains(q)) ||
          d.notes.toLowerCase().contains(q) ||
          (store.folderById(d.folderId)?.name.toLowerCase().contains(q) ?? false);
    }).toList();
    switch (_sort) {
      case _SortMode.newest:
        break; // store order
      case _SortMode.oldest:
        docs.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case _SortMode.name:
        docs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _SortMode.size:
        docs.sort((a, b) => store.documentBytes(b).compareTo(store.documentBytes(a)));
    }
    return docs;
  }

  String get _sortLabel => switch (_sort) {
        _SortMode.newest => 'Sorted by newest',
        _SortMode.oldest => 'Sorted by oldest',
        _SortMode.name => 'Sorted by name',
        _SortMode.size => 'Sorted by size',
      };

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<_SortMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, label) in [
              (_SortMode.newest, 'Newest first'),
              (_SortMode.oldest, 'Oldest first'),
              (_SortMode.name, 'Name (A–Z)'),
              (_SortMode.size, 'Largest first'),
            ])
              ListTile(
                title: Text(label),
                trailing: _sort == mode ? const Icon(Icons.check, color: AppTheme.primaryGreen) : null,
                onTap: () => Navigator.pop(ctx, mode),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  Future<void> _importFiles() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 95);
    if (picked.isEmpty || !mounted) return;
    ScanSession.instance.start();
    for (final f in picked) {
      ScanSession.instance.addPage(File(f.path));
    }
    Navigator.pushNamed(context, '/crop');
  }

  void _openCamera([String mode = ScanMode.batch]) {
    ScanSession.instance.start();
    Navigator.pushNamed(context, '/camera', arguments: mode);
  }

  Future<void> _newFolder() async {
    final name = await showTextInputDialog(context, title: 'New folder', hint: 'Folder name', confirmLabel: 'Create');
    if (name != null) await store.createFolder(name);
  }

  Future<void> _folderMenu(DocFolder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename folder'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.error),
              title: const Text('Delete folder', style: TextStyle(color: AppTheme.error)),
              subtitle: const Text('Documents inside are kept'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await showTextInputDialog(context, title: 'Rename folder', initial: folder.name);
      if (name != null) await store.renameFolder(folder.id, name);
    } else {
      final ok = await showConfirmDialog(
        context,
        title: 'Delete folder?',
        message: '"${folder.name}" will be removed. Its documents stay in your library.',
      );
      if (ok) await store.deleteFolder(folder.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _visibleDocuments;
    final folders = store.folders;
    final shownFolders = _showAllFolders ? folders : folders.take(4).toList();
    final activeFolder = store.folderById(_folderFilter);
    final scans = store.scansBytes;
    final exports = store.exportsBytes;
    final totalPages = store.documents.fold<int>(0, (s, d) => s + d.pageCount);

    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.2)),
            ),
            child: const Icon(
              Icons.document_scanner,
              color: AppTheme.primaryGreen,
              size: 22,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ScanCraft',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.slate900,
              ),
            ),
            Text(
              'OFFLINE VAULT',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search, color: AppTheme.slate600),
            onPressed: () => _searchFocus.requestFocus(),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, color: AppTheme.slate600),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search documents, tags, names...',
                    hintStyle: TextStyle(color: AppTheme.slate400),
                    prefixIcon: Icon(Icons.search, color: AppTheme.slate400),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, color: AppTheme.slate400),
                            onPressed: _searchController.clear,
                          )
                        : IconButton(
                            tooltip: 'Sort',
                            icon: Icon(Icons.tune, color: AppTheme.slate400),
                            onPressed: _pickSort,
                          ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', Icons.folder_open, 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Starred', Icons.star, 'starred'),
                    const SizedBox(width: 8),
                    _buildFilterChip('ID Cards', Icons.badge, 'id-cards'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Books', Icons.menu_book, 'books'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Locked', Icons.lock, 'locked'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildVaultCard(scans, exports, totalPages),
              const SizedBox(height: 24),
              // Directories
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Directories',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slate900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Text(
                          pluralize(folders.length, 'Folder'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (folders.length > 4)
                    TextButton(
                      onPressed: () => setState(() => _showAllFolders = !_showAllFolders),
                      child: Row(
                        children: [
                          Text(_showAllFolders ? 'Show Less' : 'View All'),
                          Icon(_showAllFolders ? Icons.expand_less : Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (folders.isEmpty)
                Text(
                  'No folders yet. Create one to organise your scans.',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                )
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: [
                    for (var i = 0; i < shownFolders.length; i++) _buildFolderCard(shownFolders[i], i),
                  ],
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _newFolder,
                icon: const Icon(Icons.create_new_folder),
                label: const Text('New Folder'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: BorderSide(color: AppTheme.slate300, style: BorderStyle.solid),
                ),
              ),
              const SizedBox(height: 24),
              // Recent scans
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeFolder != null ? activeFolder.name : 'Recent Scans',
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slate900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$_sortLabel • ${pluralize(docs.length, 'document')}',
                          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.slate100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Row(
                      children: [
                        _viewToggle(Icons.format_list_bulleted, !_gridView, () => setState(() => _gridView = false)),
                        _viewToggle(Icons.grid_view, _gridView, () => setState(() => _gridView = true)),
                      ],
                    ),
                  ),
                ],
              ),
              if (activeFolder != null) ...[
                const SizedBox(height: 8),
                InputChip(
                  avatar: const Icon(Icons.folder, size: 16, color: AppTheme.primaryGreen),
                  label: Text('In ${activeFolder.name}'),
                  onDeleted: () => setState(() => _folderFilter = null),
                ),
              ],
              const SizedBox(height: 12),
              if (docs.isEmpty)
                _buildEmptyState()
              else if (_gridView)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                  children: [for (final d in docs) _buildDocumentTile(d)],
                )
              else
                for (final d in docs) ...[
                  _buildDocumentItem(d),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 80),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.slate200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _importFiles,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Import File'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.slate700,
                    ),
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: AppTheme.slate200,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openCamera(ScanMode.single),
                    icon: const Icon(Icons.photo_camera, size: 20),
                    label: const Text('Quick Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: AppTheme.primaryGreen,
        unselectedItemColor: AppTheme.slate500,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          switch (index) {
            case 1:
              _openCamera(ScanMode.batch);
            case 2:
              _openCamera(ScanMode.single);
            case 3:
              Navigator.pushNamed(context, '/storage');
            case 4:
              Navigator.pushNamed(context, '/settings');
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'Documents',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_none),
            label: 'Batch',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_camera, size: 28),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.phonelink_lock),
            label: 'Storage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _viewToggle(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: active
            ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))
            : null,
        child: Icon(icon, size: 18, color: active ? AppTheme.primaryGreen : AppTheme.slate400),
      ),
    );
  }

  Widget _buildVaultCard(int scans, int exports, int totalPages) {
    final total = scans + exports;
    final scansFraction = total == 0 ? 0.0 : scans / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.successGreen,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successBorder),
                ),
                child: const Icon(
                  Icons.phonelink_lock,
                  color: AppTheme.primaryGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Offline Local Vault',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.slate900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successBorder.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'OFFLINE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.successText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '100% Offline • Zero Cloud Sync • Stored on this device',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/storage'),
                child: Row(
                  children: [
                    Text('Manage'),
                    Icon(Icons.chevron_right, size: 14),
                  ],
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
              border: Border.all(color: AppTheme.slate100),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                        children: [
                          TextSpan(
                            text: formatBytes(total),
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.slate900),
                          ),
                          const TextSpan(text: ' used in Local Vault'),
                        ],
                      ),
                    ),
                    Text(
                      '${pluralize(store.documents.length, 'doc')} • ${pluralize(totalPages, 'page')}',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: scansFraction,
                    minHeight: 10,
                    backgroundColor: total == 0 ? AppTheme.slate200 : AppTheme.tertiary,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(child: _legend(AppTheme.primaryGreen, 'Scanned Docs (${formatBytes(scans)})')),
                    const SizedBox(width: 12),
                    Flexible(child: _legend(AppTheme.tertiary, 'Exports (${formatBytes(exports)})')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 10, color: AppTheme.slate500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final filtered = _searchController.text.isNotEmpty || selectedFilter != 'all' || _folderFilter != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        children: [
          Icon(filtered ? Icons.search_off : Icons.document_scanner_outlined, size: 40, color: AppTheme.slate400),
          const SizedBox(height: 8),
          Text(
            filtered ? 'No matching documents' : 'No scans yet',
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            filtered ? 'Try a different search or filter.' : 'Tap Quick Scan or Import File to add your first document.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, String filter) {
    final isSelected = selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = filter;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryGreen : AppTheme.slate200),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppTheme.slate600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderCard(DocFolder folder, int index) {
    final (icon, bgColor, borderColor, iconColor) = _folderStyles[index % _folderStyles.length];
    final count = store.documentsIn(folder.id).length;
    final selected = _folderFilter == folder.id;
    return GestureDetector(
      onTap: () => setState(() => _folderFilter = selected ? null : folder.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryGreen : AppTheme.slate200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                GestureDetector(
                  onTap: () => _folderMenu(folder),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.more_vert, color: AppTheme.slate400, size: 18),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.name,
                  style: TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slate900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${pluralize(count, 'file')} • ${formatBytes(store.folderBytes(folder.id))}',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(ScanDocument d) {
    final parts = <String>[
      store.folderById(d.folderId)?.name ?? 'Unfiled',
      if (d.kind == DocumentKind.idCard) 'ID Card',
      if (d.kind == DocumentKind.book) 'Book',
      if (d.signed) 'Signed',
      if (!d.locked) ...d.tags.take(2),
    ];
    return parts.join(' • ');
  }

  Widget _buildDocumentItem(ScanDocument d) {
    final first = d.pages.isEmpty ? null : store.pageFile(d, 0);
    return GestureDetector(
      onTap: () => openDocument(context, d),
      onLongPress: () => showDocumentMenu(context, d),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: PageThumb(file: first, locked: d.locked),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (d.starred) ...[
                        const Icon(Icons.star, size: 16, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          d.name,
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slate900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => showDocumentMenu(context, d),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.more_vert, color: AppTheme.slate400, size: 20),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _subtitle(d),
                    style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${pluralize(d.pageCount, 'Page')} • ${formatBytes(store.documentBytes(d))} • ${formatRelative(d.updatedAt)}',
                          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(child: _badge(d)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(ScanDocument d) {
    final locked = d.locked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: locked ? AppTheme.tertiary.withValues(alpha: 0.1) : AppTheme.successGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: locked ? AppTheme.tertiary.withValues(alpha: 0.3) : AppTheme.successBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock : Icons.density_large,
            size: 12,
            color: locked ? AppTheme.tertiary : AppTheme.primaryGreen,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              locked ? 'Locked' : '${d.dpi} DPI',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: locked ? AppTheme.tertiary : AppTheme.primaryGreen,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTile(ScanDocument d) {
    final first = d.pages.isEmpty ? null : store.pageFile(d, 0);
    return GestureDetector(
      onTap: () => openDocument(context, d),
      onLongPress: () => showDocumentMenu(context, d),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppTheme.slate100,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                        child: PageThumb(file: first, locked: d.locked, iconSize: 36),
                      ),
                    ),
                  ),
                  if (d.starred)
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: Icon(Icons.star, size: 18, color: Color(0xFFF59E0B)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.slate900,
                          ),
                        ),
                        Text(
                          '${pluralize(d.pageCount, 'page')} • ${formatRelative(d.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => showDocumentMenu(context, d),
                    child: Icon(Icons.more_vert, color: AppTheme.slate400, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
