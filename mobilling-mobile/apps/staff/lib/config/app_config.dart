import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000/api
abstract final class AppConfig {
  static const String _configured = String.fromEnvironment('API_BASE_URL');

  /// Where MoBilling is actually hosted — the same host the web app's
  /// `DEFAULT_HOSTS` treats as home (`mobilling-ui/src/branding.ts`). Every
  /// release build talks to this unless `API_BASE_URL` overrides it.
  static const String _productionBaseUrl = 'https://mobilling.co.tz/api';

  /// Where the API lives.
  ///
  /// A release build (what actually ships to a phone) always defaults to
  /// production — there is no dev server on the other end of a device in
  /// someone's pocket. Debug and profile builds keep the emulator-aware
  /// localhost fallback: the two simulators disagree about how to reach the
  /// host machine, an Android emulator sees it as 10.0.2.2, an iOS simulator
  /// shares the host's own localhost, and a single hardcoded default would be
  /// wrong on one of them — silently, since it surfaces only as "could not
  /// reach the server" on a screen that looks fine.
  static String get apiBaseUrl {
    if (_configured.isNotEmpty) return _configured;
    if (kReleaseMode) return _productionBaseUrl;
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000/api'
        : 'http://localhost:8000/api';
  }

  /// One app, three shells — so the name is the product, not one audience.
  static const String appName = 'MoBilling';
}
