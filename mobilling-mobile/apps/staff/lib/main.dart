import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'config/app_config.dart';
import 'config/theme_mode.dart';
import 'navigation/app_chrome.dart';
import 'providers.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: StaffApp()));
}

class StaffApp extends ConsumerWidget {
  const StaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

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
