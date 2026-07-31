# Enabling push notifications

The backend is **already live**: device-token registration endpoints and an
FCM channel on the three client-facing events (invoice issued, payment
receipt, ticket reply). Pushes silently no-op until both halves below are
configured, so nothing breaks in the meantime.

## 1. Firebase project (one-time)

1. Create a project at <https://console.firebase.google.com>.
2. Add an **Android app** (package `tz.co.mobilling.client_portal`) and an
   **iOS app** (bundle `tz.co.mobilling.clientPortal`).
3. Project settings → Service accounts → **Generate new private key** — this
   JSON file is for the *server*.

## 2. API server

```bash
# .env
FCM_CREDENTIALS=/var/www/secrets/mobilling-fcm.json
```

Place the service-account JSON at that path (outside the web root, mode 600).
That's all — `FcmService` handles OAuth and dead-token pruning itself.

## 3. Flutter app

```bash
dart pub global activate flutterfire_cli
cd apps/client_portal
flutterfire configure        # pick the Firebase project; writes config files
flutter pub add firebase_core firebase_messaging
```

Then replace `NoopPushRegistration` in
`lib/features/push/push_registration.dart` with:

```dart
class FirebasePushRegistration implements PushRegistration {
  @override
  Future<void> registerAfterLogin(PortalService portal) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    Future<void> send(String? token) async {
      if (token == null) return;
      await portal.registerDeviceToken(token,
          platform: Platform.isIOS ? 'ios' : 'android');
    }

    await send(await messaging.getToken());
    messaging.onTokenRefresh.listen(send);
  }

  @override
  Future<void> unregisterBeforeLogout(PortalService portal) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await portal.unregisterDeviceToken(token);
  }
}
```

and swap the instance used in `session` wiring. iOS additionally needs the
Push Notifications capability + APNs key uploaded to Firebase (Xcode →
Signing & Capabilities → + Capability → Push Notifications).

## What gets pushed

| Event | Title | Deep-link data |
|---|---|---|
| Invoice issued | `Invoice INV-…` | `{type: invoice, document_id}` |
| Payment received | `Payment received — thank you!` | `{type: payment, document_id}` |
| Ticket reply / closed | `New reply — TKT-…` | `{type: ticket, ticket_id}` |

Tokens are pruned automatically when FCM reports a device as UNREGISTERED.
