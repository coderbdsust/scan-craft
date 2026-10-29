import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/scan_session.dart';
import '../../theme/app_theme.dart';

class DocumentsLibraryScreen extends StatefulWidget {
  const DocumentsLibraryScreen({super.key});

  @override
  State<DocumentsLibraryScreen> createState() => _DocumentsLibraryScreenState();
}

class _DocumentsLibraryScreenState extends State<DocumentsLibraryScreen> {
  String selectedFilter = 'all';
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
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
            icon: const Icon(Icons.search, color: AppTheme.slate600),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuC0RnlwTmE9N95W0v8HjEKdkvMZ2grAkq9nztgjeF6VpBt7kkNhNLHgjL3bOQ4-XENObET6ZG4FUgbVY4kzyYx_9tHasN_waaDsmLpT1wyheq1OypGyFOJKNYFvkQYjWRkWTpvXh4tKbg2RWOf6E1wgEOnq_3nsiL6zQUfdOS9i45lxuZ0z0pvV5_U2OFN3e6VexNObWoWJys8s5kniBU-m-YVu40nKb7_w6dyKOQY',
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  decoration: InputDecoration(
                    hintText: 'Search documents, tags, names...',
                    hintStyle: TextStyle(color: AppTheme.slate400),
                    prefixIcon: Icon(Icons.search, color: AppTheme.slate400),
                    suffixIcon: Icon(Icons.tune, color: AppTheme.slate400),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
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
                    _buildFilterChip('PDFs', Icons.picture_as_pdf, 'pdf'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Images', Icons.image, 'images'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Starred', Icons.star, 'starred'),
                    const SizedBox(width: 8),
                    _buildFilterChip('ID Cards', Icons.badge, 'id-cards'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Offline vault card
              Container(
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
                                      color: AppTheme.successBorder.withOpacity(0.5),
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
                                '100% Offline • Zero Cloud Sync • On-Device Encrypted',
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
                          onPressed: () {},
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
                                      text: '4.2 GB',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.slate900),
                                    ),
                                    const TextSpan(text: ' used in Local Vault'),
                                  ],
                                ),
                              ),
                              Text(
                                '128 GB On-Device',
                                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: 0.28,
                              minHeight: 10,
                              backgroundColor: AppTheme.slate200,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryGreen,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Scanned Docs (3.2 GB)',
                                        style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: AppTheme.tertiary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Secure Archives (1.0 GB)',
                                        style: TextStyle(fontSize: 10, color: AppTheme.slate500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
                          '4 Vaults',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () {},
                    child: Row(
                      children: [
                        Text('View All'),
                        Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _buildFolderCard('Work Contracts', Icons.folder, AppTheme.successGreen, AppTheme.successBorder, AppTheme.primaryGreen, '8 files • 24.8 MB'),
                  _buildFolderCard('Tax & Invoices', Icons.receipt_long, AppTheme.secondaryContainer.withOpacity(0.3), AppTheme.secondary.withOpacity(0.3), AppTheme.secondary, '14 files • 56.1 MB'),
                  _buildFolderCard('Identity & Passports', Icons.lock, AppTheme.tertiary.withOpacity(0.1), AppTheme.tertiary.withOpacity(0.3), AppTheme.tertiary, '4 files • Locked Vault'),
                  _buildFolderCard('Medical Records', Icons.health_and_safety, AppTheme.successGreen, AppTheme.successBorder, AppTheme.primaryGreen, '6 files • 18.2 MB'),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {},
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Scans',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.slate900,
                        ),
                      ),
                      Text(
                        'Sorted by newest',
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.slate100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(Icons.format_list_bulleted, size: 18, color: AppTheme.primaryGreen),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.grid_view, size: 18, color: AppTheme.slate400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildDocumentItem('Master Services Agreement 2024', 'Legal • Acme Corp • Signed', '3 Pages • 1.4 MB • Today, 10:42 AM', '300 DPI • PDF'),
              const SizedBox(height: 8),
              _buildDocumentItem('AWS Cloud Server Invoice #8821', 'Tax & Expenses • USD \$342.50', '1 Page • 420 KB • Yesterday', 'Clean Scan'),
              const SizedBox(height: 8),
              _buildDocumentItem('Diagnostic Summary & Vitals', 'Medical Records • Dr. Jensen', '2 Pages • 2.1 MB • May 12', '300 DPI • Color'),
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
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.slate200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final List<XFile> picked = await picker.pickMultiImage(
                        imageQuality: 90,
                      );
                      if (picked.isNotEmpty && context.mounted) {
                        for (final f in picked) {
                          ScanSession.instance.addPage(File(f.path));
                        }
                        if (!mounted) return;
                        Navigator.pushNamed(context, '/crop');
                      }
                    },
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
                    onPressed: () => Navigator.pushNamed(context, '/camera'),
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
          // Center camera item opens the viewfinder
          if (index == 2) {
            Navigator.pushNamed(context, '/camera');
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
            label: '',
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

  Widget _buildFolderCard(String title, IconData icon, Color bgColor, Color borderColor, Color iconColor, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
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
              Icon(Icons.more_vert, color: AppTheme.slate400, size: 18),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
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
                subtitle,
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentItem(String title, String subtitle, String meta, String badge) {
    return Container(
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
            child: const Icon(Icons.description, color: AppTheme.slate400),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
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
                    Icon(Icons.more_vert, color: AppTheme.slate400, size: 20),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.successBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              badge.contains('DPI') ? Icons.density_large : Icons.verified,
                              size: 12,
                              color: AppTheme.primaryGreen,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                badge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryGreen,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
}
