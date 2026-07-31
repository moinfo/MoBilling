/// Build-time configuration for the staff app.
///
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000/api
abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  static const String appName = 'MoBilling Staff';
}
