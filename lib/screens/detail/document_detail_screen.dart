import 'dart:io';

import 'package:flutter/material.dart';
import '../../models/scan_session.dart';
import '../../theme/app_theme.dart';

class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({super.key});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  bool biometricEnabled = true;
  bool mgmtExpanded = true;
  String filename = 'Invoice_2025_AcmeCorp';
  
  @override
  Widget build(BuildContext context) {
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
                color: AppTheme.primaryGreen.withOpacity(0.1),
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
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppTheme.slate600),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: NetworkImage(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuC0RnlwTmE9N95W0v8HjEKdkvMZ2grAkq9nztgjeF6VpBt7kkNhNLHgjL3bOQ4-XENObET6ZG4FUgbVY4kzyYx_9tHasN_waaDsmLpT1wyheq1OypGyFOJKNYFvkQYjWRkWTpvXh4tKbg2RWOf6E1wgEOnq_3nsiL6zQUfdOS9i45lxuZ0z0pvV5_U2OFN3e6VexNObWoWJys8s5kniBU-m-YVu40nKb7_w6dyKOQY',
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Offline banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withOpacity(0.9),
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
                              color: AppTheme.successText.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withOpacity(0.1),
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
              ),
              const SizedBox(height: 12),
              // Document header
              Container(
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
                      child: const Icon(Icons.description, color: AppTheme.primaryGreen),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              filename,
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slate900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '.pdf',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.slate400,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18, color: AppTheme.slate400),
                            onPressed: () {},
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.star_border, color: AppTheme.slate500),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: () {},
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Pages
              Column(
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
                              color: AppTheme.successBorder.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${ScanSession.instance.pageCount} Pages',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.successText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.swap_vert, size: 16),
                        label: const Text('Reorder'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < ScanSession.instance.pages.length; i++) ...[
                          _buildPageThumbnail(
                            'P. ${i + 1}',
                            'Captured Page ${i + 1}',
                            imageFile: ScanSession.instance.pages[i],
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          width: 128,
                          height: 192,
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
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Organization
              Container(
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
                            child: const Icon(Icons.folder, color: AppTheme.primaryGreen),
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
                                  'Tax & Invoices / 2025 Q4',
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
                            onPressed: () {},
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
                          _buildMetaItem(Icons.calendar_today, 'Created', 'Oct 24, 2025'),
                          _buildMetaItem(Icons.storage, 'File Weight', '2.4 MB'),
                          _buildMetaItem(Icons.auto_stories, 'Pages', '${ScanSession.instance.pageCount} Scanned'),
                          _buildMetaItem(Icons.photo_size_select_large, 'Density', '300 DPI (Archival)'),
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
                            _buildTag('#tax'),
                            _buildTag('#expenses'),
                            _buildTag('#2025'),
                            ActionChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add, size: 14),
                                  const SizedBox(width: 4),
                                  const Text('Add Tag'),
                                ],
                              ),
                              onPressed: () {},
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
              ),
              const SizedBox(height: 12),
              // Page management
              Container(
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
                                  'Page Management & Quality',
                                  style: TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                                Text(
                                  'Optical profile • Offline compression engine',
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
                                        '300 DPI Archival',
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
                                    Expanded(child: _buildDPIOption('150 DPI', 'Compact', false)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildDPIOption('300 DPI', 'Standard', true)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildDPIOption('600 DPI', 'Lossless', false)),
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
                                    Expanded(child: _buildColorOption(Icons.contrast, 'B&W Doc', false)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildColorOption(Icons.palette, 'True Color', true)),
                                    const SizedBox(width: 6),
                                    Expanded(child: _buildColorOption(Icons.filter_b_and_w, 'Grayscale', false)),
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
                                      'Document Notes (Encrypted Locally)',
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.slate700,
                                      ),
                                    ),
                                    Text(
                                      'Offline Memo',
                                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText: 'Add confidential notes...',
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
                                  controller: TextEditingController(text: 'Standard Q4 Acme Corp hardware & licensing disbursement invoice. Matched to PO #4920.'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Actions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.slate200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Export Archival PDF'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {},
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
                            onPressed: () {},
                            icon: const Icon(Icons.draw, color: AppTheme.secondary),
                            label: const Text('Sign Document'),
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
                                  'Lock with FaceID',
                                  style: TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.slate900,
                                  ),
                                ),
                                Text(
                                  'Encrypt and require biometrics',
                                  style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: biometricEnabled,
                            onChanged: (val) => setState(() => biometricEnabled = val),
                            activeColor: AppTheme.primaryGreen,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageThumbnail(String page, String name, {File? imageFile}) {
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
                height: 160,
                decoration: const BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: imageFile != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        child: Image.file(
                          imageFile,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.description, color: AppTheme.slate400, size: 40),
                      ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: Text(
                    page,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: AppTheme.onErrorContainer, size: 12),
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
                    name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.slate700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.drag_indicator, size: 16, color: AppTheme.slate400),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: AppTheme.slate500),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTag(String tag) {
    return Chip(
      label: Text(tag),
      deleteIcon: const Icon(Icons.cancel, size: 14),
      onDeleted: () {},
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
        color: selected ? AppTheme.successGreen.withOpacity(0.7) : Colors.white,
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
        color: selected ? AppTheme.successGreen.withOpacity(0.7) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? AppTheme.primaryGreen : AppTheme.slate200, width: selected ? 2 : 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: selected ? AppTheme.primaryGreen : AppTheme.slate500),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? AppTheme.primaryGreen : AppTheme.slate700,
            ),
          ),
        ],
      ),
    );
  }
}
