import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/document_store.dart';
import 'theme/app_theme.dart';
import 'screens/home/documents_library_screen.dart';
import 'screens/camera/camera_viewfinder_screen.dart';
import 'screens/crop/crop_clean_editor_screen.dart';
import 'screens/detail/document_detail_screen.dart';
import 'screens/qr/qr_scanner_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/sign/sign_document_screen.dart';
import 'screens/storage/storage_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Scans are stored as files on the device, which browsers don't provide.
  if (kIsWeb) {
    runApp(const _StartupErrorApp(
      'ScanCraft runs on Android and iOS.\n\nRun it on a phone or emulator: flutter run -d <device>',
    ));
    return;
  }
  try {
    await DocumentStore.instance.init();
  } catch (e) {
    runApp(_StartupErrorApp('Could not open the on-device library.\n\n$e'));
    return;
  }
  runApp(const ScanCraftApp());
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 48, color: AppTheme.primaryGreen),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        '/sign': (context) => const SignDocumentScreen(),
        '/qr': (context) => const QrScannerScreen(),
        '/storage': (context) => const StorageScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
