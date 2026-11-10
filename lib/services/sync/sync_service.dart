import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../document_store.dart';
import 'cloud_drive.dart';
import 'drive_sync_engine.dart';
import 'google_account.dart';

enum SyncStatus { off, idle, syncing, waitingForWifi, needsSignIn, error }

/// Decides when to sync and exposes progress to the UI.
///
/// Sync runs while the app is open: on launch and resume, a few seconds after
/// local edits, every 15 minutes, and on "Sync now". Nothing is uploaded
/// unless the user turned sync on.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService._();
  static final SyncService instance = SyncService._();

  final DocumentStore _store = DocumentStore.instance;
  final GoogleAccount _account = GoogleAccount.instance;

  SyncStatus status = SyncStatus.off;
  String? message; // last error or summary
  bool _running = false;
  bool _started = false;
  Timer? _debounce;
  Timer? _periodic;

  bool get enabled => _store.settings.syncEnabled;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_onStoreChanged);
    _periodic = Timer.periodic(const Duration(minutes: 15), (_) => syncNow());
    _setStatus(enabled ? SyncStatus.idle : SyncStatus.off);
    unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  /// Local edits schedule a push, but only when there is something to send;
  /// this also keeps sync's own bookkeeping saves from re-triggering it.
  void _onStoreChanged() {
    if (!enabled || _running || !_hasLocalWork()) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), syncNow);
  }

  bool _hasLocalWork() =>
      _store.pendingRemoteDeletes.isNotEmpty ||
      _store.documents.any((d) => d.locked ? d.sync.folderId != null : d.hasUnsyncedChanges);

  Future<void> syncNow() async {
    if (_running) return;
    if (!enabled) {
      _setStatus(SyncStatus.off);
      return;
    }
    if (_store.settings.syncWifiOnly) {
      final net = await Connectivity().checkConnectivity();
      final unmetered = net.contains(ConnectivityResult.wifi) || net.contains(ConnectivityResult.ethernet);
      if (!unmetered) {
        _setStatus(SyncStatus.waitingForWifi);
        return;
      }
    }
    _running = true;
    _setStatus(SyncStatus.syncing);
    try {
      final api = await _account.driveApi();
      if (api == null) {
        _setStatus(SyncStatus.needsSignIn, 'Reconnect Google Drive in Settings.');
        return;
      }
      final report = await DriveSyncEngine(store: _store, cloud: GoogleDriveCloud(api)).run();
      _setStatus(SyncStatus.idle, 'Last sync: $report');
    } catch (e) {
      _setStatus(SyncStatus.error, 'Sync failed: $e');
    } finally {
      _running = false;
    }
    // Edits made while syncing are picked up right away.
    if (enabled && _hasLocalWork()) _onStoreChanged();
  }

  /// Interactive: signs in, turns sync on and runs the first sync.
  Future<void> connect() async {
    final email = await _account.connect();
    await _store.updateSettings((s) {
      s.driveAccount = email;
      s.syncEnabled = true;
    });
    await syncNow();
  }

  /// Turns sync off and forgets the Drive link. Documents stay on the device
  /// and the files already in Drive are left untouched.
  Future<void> disconnect() async {
    _debounce?.cancel();
    await _account.disconnect();
    for (final d in _store.documents) {
      d.sync.reset();
    }
    _store.driveRootFolderId = null;
    _store.pendingRemoteDeletes.clear();
    await _store.updateSettings((s) {
      s.driveAccount = null;
      s.syncEnabled = false;
    });
    _setStatus(SyncStatus.off);
  }

  void _setStatus(SyncStatus s, [String? msg]) {
    status = s;
    if (msg != null || s == SyncStatus.off) message = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
