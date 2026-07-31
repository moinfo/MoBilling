/// Build-time configuration.
///
/// Supplied with `--dart-define`, so the API host is baked into each build
/// rather than read at runtime:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
///
/// The default targets the Android emulator's host loopback (10.0.2.2). On an
/// iOS simulator use http://localhost:8000/api; on a physical device use your
/// machine's LAN address.
abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  /// Shown on the sign-in screen before any tenant is known. After login the
  /// app re-brands from the tenant on the session — the mobile build is a
  /// single MoBilling-branded app, so there is no pre-login tenant to resolve.
  static const String appName = 'MoBilling';

  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
