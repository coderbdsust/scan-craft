import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

/// Google account connection for Drive sync.
///
/// OAuth client ids come from the build, so nothing secret lives in the
/// repository: pass `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` (the web
/// client id) and, for iOS, `--dart-define=GOOGLE_IOS_CLIENT_ID=...`.
/// See README "Google Drive sync setup".
class GoogleAccount {
  GoogleAccount._();
  static final GoogleAccount instance = GoogleAccount._();

  static const scopes = [drive.DriveApi.driveFileScope];
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  bool _initialized = false;
  GoogleSignInAccount? _account;

  /// Whether this build has the OAuth ids needed for sign-in.
  bool get isConfigured =>
      Platform.isIOS ? _iosClientId.isNotEmpty || _serverClientId.isNotEmpty : _serverClientId.isNotEmpty;

  String? get email => _account?.email;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && _iosClientId.isNotEmpty ? _iosClientId : null,
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
    _initialized = true;
  }

  /// Interactive sign-in plus Drive permission. Must be called from a user
  /// action. Returns the account email.
  Future<String> connect() async {
    await _init();
    final account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    await account.authorizationClient.authorizeScopes(scopes);
    _account = account;
    return account.email;
  }

  /// A Drive client without any UI, or null when the user has to reconnect
  /// (signed out, permission revoked, or tokens unavailable).
  Future<drive.DriveApi?> driveApi() async {
    await _init();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    final account = _account;
    if (account == null) return null;
    final authz = await account.authorizationClient.authorizationForScopes(scopes);
    if (authz == null) return null;
    return drive.DriveApi(authz.authClient(scopes: scopes));
  }

  Future<void> disconnect() async {
    await _init();
    try {
      await GoogleSignIn.instance.disconnect(); // also revokes Drive access
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
    _account = null;
  }
}
