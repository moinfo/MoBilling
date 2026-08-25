import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

/// Requests notification permission, mints an FCM token, and keeps the
/// server's copy current for as long as this instance lives (which is the
/// app's lifetime — see `pushRegistrationProvider`).
///
/// `POST/DELETE /device-tokens` is `auth:sanctum`-only — it works the same
/// for a portal client, a staff member, or an impersonated super admin —
/// which is why [PushRegistration] takes [AuthService] rather than a
/// shell-specific service.
class FirebasePushRegistration implements PushRegistration {
  FirebasePushRegistration();

  StreamSubscription<String>? _refreshSub;
  String? _registeredToken;

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  @override
  Future<void> registerAfterLogin(AuthService auth) async {
    final messaging = FirebaseMessaging.instance;

    // iOS asks the user; Android (<13) is silently granted and 13+ is
    // covered by the manifest's POST_NOTIFICATIONS permission plus this same
    // call, which the plugin routes to the platform-appropriate prompt.
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push permission denied — device will not receive pushes.');
      return;
    }

    // A fresh listener per login would leak one every time a device stays
    // signed in across multiple accounts; drop any subscription from a prior
    // session before starting a new one.
    await _refreshSub?.cancel();
    _refreshSub = messaging.onTokenRefresh.listen((token) {
      _registeredToken = token;
      unawaited(auth.registerDeviceToken(token, platform: _platform));
    });

    final token = await messaging.getToken();
    if (token == null) return;
    _registeredToken = token;
    await auth.registerDeviceToken(token, platform: _platform);
  }

  @override
  Future<void> unregisterBeforeLogout(AuthService auth) async {
    await _refreshSub?.cancel();
    _refreshSub = null;

    final token = _registeredToken ?? await FirebaseMessaging.instance.getToken();
    _registeredToken = null;
    if (token == null) return;
    await auth.unregisterDeviceToken(token);
  }
}
