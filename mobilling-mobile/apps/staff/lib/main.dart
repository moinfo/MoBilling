import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'config/app_config.dart';
import 'config/theme_mode.dart';
import 'firebase_options.dart';
import 'navigation/app_chrome.dart';
import 'providers.dart';
import 'router.dart';

/// Handles a push arriving while the app is backgrounded or terminated.
///
/// Must be a top-level (or static) function: the platform spawns a fresh,
/// isolated Dart isolate to run it, with no access to the app's state or
/// widget tree — there's nothing running yet to hand the message to.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only Android has a google-services.json / DefaultFirebaseOptions entry so
  // far — iOS/APNs setup is deferred. Skipping Firebase entirely there (rather
  // than letting DefaultFirebaseOptions.currentPlatform throw) keeps the app
  // launching normally on a platform push simply isn't wired up for yet.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(pushDeepLinkWiringProvider);

    ref.listen(sessionControllerProvider, (_, session) {
      Formatting.setTenantCurrency(session.tenant?.currency);
    });

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      // Outside the navigator, so the bottom bar persists across pushes.
      builder: (context, child) => AppChrome(child: child ?? const SizedBox()),
    );
  }
}
