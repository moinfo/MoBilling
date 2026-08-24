import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the Sanctum bearer token in the platform keystore.
///
/// Sanctum's personal access tokens do not expire on their own and there is no
/// refresh-token flow — a leaked token is valid until it is revoked
/// server-side. That makes the Keychain / EncryptedSharedPreferences the only
/// appropriate home for it; the web app's `localStorage` equivalent
/// (SharedPreferences) is world-readable on a rooted device.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'mobilling.auth.token';
  static const _userTypeKey = 'mobilling.auth.user_type';

  /// Cached so the Dio interceptor can stay off the platform channel on every
  /// request — keystore reads are cheap but not free, and they are async.
  String? _cachedToken;
  bool _loaded = false;

  Future<String?> read() async {
    if (_loaded) return _cachedToken;
    _cachedToken = await _storage.read(key: _tokenKey);
    _loaded = true;
    return _cachedToken;
  }

  /// Synchronous view of the cache. Null before [read] has run once, so it is
  /// only safe where a prior [read] is guaranteed.
  String? get cached => _cachedToken;

  bool get hasToken => _cachedToken != null && _cachedToken!.isNotEmpty;

  /// [userType] is the `user_type` the login response returned — 'client' or
  /// 'tenant'. Stored so a restarted app can route to the right shell before
  /// any network call resolves.
  Future<void> save(String token, {required String userType}) async {
    _cachedToken = token;
    _loaded = true;
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userTypeKey, value: userType);
  }

  Future<String?> readUserType() => _storage.read(key: _userTypeKey);

  static const _biometricKey = 'mobilling.auth.biometric_lock';

  /// Whether the stored token may only be used after a biometric check.
  /// Survives sign-out? No — [clear] removes it with the token, because the
  /// preference is about *this* session's credential, not the device.
  Future<bool> readBiometricLock() async =>
      await _storage.read(key: _biometricKey) == '1';

  Future<void> setBiometricLock(bool enabled) =>
      _storage.write(key: _biometricKey, value: enabled ? '1' : '0');

  Future<void> clear() async {
    _cachedToken = null;
    _loaded = true;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userTypeKey);
    await _storage.delete(key: _biometricKey);
  }
}
