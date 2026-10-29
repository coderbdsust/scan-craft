import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home/documents_library_screen.dart';
import 'screens/camera/camera_viewfinder_screen.dart';
import 'screens/crop/crop_clean_editor_screen.dart';
import 'screens/detail/document_detail_screen.dart';

void main() {
  runApp(const ScanCraftApp());
}

class ScanCraftApp extends StatelessWidget {
  const ScanCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScanCraft',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const DocumentsLibraryScreen(),
        '/camera': (context) => const CameraViewfinderScreen(),
        '/crop': (context) => const CropCleanEditorScreen(),
        '/detail': (context) => const DocumentDetailScreen(),
      },
    );
  }
}
