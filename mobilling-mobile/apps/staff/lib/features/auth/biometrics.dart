import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Device biometrics (Face ID, Touch ID, Android fingerprint/face) behind a
/// small surface the sign-in screen can reason about.
class Biometrics {
  Biometrics([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device has hardware *and* an enrolled biometric. A phone
  /// with a sensor but nothing enrolled would prompt for a passcode instead,
  /// which is not what "sign in with fingerprint" promises.
  Future<bool> get available async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// What to call the control: "Face ID" on a Face ID iPhone, "fingerprint"
  /// elsewhere. Falls back to the generic word when unknown.
  Future<String> get label async {
    try {
      final kinds = await _auth.getAvailableBiometrics();
      if (kinds.contains(BiometricType.face) &&
          !kinds.contains(BiometricType.fingerprint)) {
        return 'Face ID';
      }
      return 'fingerprint';
    } on PlatformException {
      return 'fingerprint';
    }
  }

  /// Show the system prompt. False on cancel, lockout or failure — the
  /// caller keeps the password path open, so there is nothing to recover.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

final Provider<Biometrics> biometricsProvider =
    Provider<Biometrics>((ref) => Biometrics());
