import 'package:flutter/foundation.dart';

/// Build-time configuration.
///
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000/api
abstract final class AppConfig {
  static const String _configured = String.fromEnvironment('API_BASE_URL');

  /// Where the API lives.
  ///
  /// The fallback is platform-aware because the two simulators disagree about
  /// how to reach the host machine: an Android emulator sees it as 10.0.2.2,
  /// an iOS simulator shares the host's own localhost. A single hardcoded
  /// default is therefore wrong on one of them — and wrong silently, since it
  /// surfaces only as "No internet connection" on a screen that looks fine.
  static String get apiBaseUrl {
    if (_configured.isNotEmpty) return _configured;
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000/api'
        : 'http://localhost:8000/api';
  }

  /// One app, three shells — so the name is the product, not one audience.
  static const String appName = 'MoBilling';
}
