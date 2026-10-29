import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around the platform biometric / device-credential prompt.
class AuthService {
  AuthService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Returns null on success, otherwise a message suitable for a snackbar.
  static Future<String?> authenticate(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) {
        return 'Set up a screen lock or biometrics on this device first.';
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? null : 'Authentication cancelled.';
    } on LocalAuthException catch (e) {
      return 'Authentication unavailable: ${e.description ?? e.code.name}';
    } on PlatformException catch (e) {
      return 'Authentication unavailable: ${e.message ?? e.code}';
    }
  }
}
