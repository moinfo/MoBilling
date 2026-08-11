import 'package:flutter/foundation.dart';
import 'package:mobilling_api/mobilling_api.dart';

/// Device push-token lifecycle.
///
/// The backend side is fully live: `POST/DELETE /portal/device-tokens` and an
/// FCM channel on invoice / receipt / ticket-reply notifications. What this
/// build lacks is Firebase itself — `firebase_messaging` cannot even compile
/// without per-app config files (google-services.json / GoogleService-Info
/// .plist) that must come from your Firebase project. Hence this seam.
///
/// To turn push on:
///   1. `dart pub global activate flutterfire_cli`
///   2. `flutterfire configure` inside apps/client_portal (creates the
///      Firebase config files and firebase_options.dart)
///   3. Add `firebase_core` + `firebase_messaging` to pubspec.yaml
///   4. Replace [NoopPushRegistration] with an implementation that requests
///      permission, reads `FirebaseMessaging.instance.getToken()`, forwards
///      it to [PortalService.registerDeviceToken], and re-registers on
///      `onTokenRefresh`.
///   5. Set FCM_CREDENTIALS on the API server to the service-account JSON.
///
/// See PUSH_SETUP.md at the repo root for the full walkthrough.
abstract class PushRegistration {
  Future<void> registerAfterLogin(PortalService portal);
  Future<void> unregisterBeforeLogout(PortalService portal);
}

/// Placeholder used until Firebase is configured — logs instead of pushing.
class NoopPushRegistration implements PushRegistration {
  const NoopPushRegistration();

  @override
  Future<void> registerAfterLogin(PortalService portal) async {
    debugPrint('Push disabled: Firebase not configured (see PUSH_SETUP.md).');
  }

  @override
  Future<void> unregisterBeforeLogout(PortalService portal) async {}
}
