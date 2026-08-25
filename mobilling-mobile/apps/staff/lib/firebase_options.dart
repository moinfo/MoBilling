import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase configuration for this app, by platform.
///
/// Hand-written from the `google-services.json` downloaded in the Firebase
/// console for `mobilling-bbf3c` / `tz.co.mobilling.staff` (Android only —
/// iOS/APNs setup is deferred). Re-run `flutterfire configure` instead of
/// editing this by hand once iOS is added; it regenerates this exact shape.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for '
          '$defaultTargetPlatform — only Android is set up so far.',
        );
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyC3eKQ9NjEewLv0aXYrn0VJWJo6YYuKkkY',
    appId: '1:254728203733:android:09032b73f7690f8b67615c',
    messagingSenderId: '254728203733',
    projectId: 'mobilling-bbf3c',
    storageBucket: 'mobilling-bbf3c.firebasestorage.app',
  );
}
