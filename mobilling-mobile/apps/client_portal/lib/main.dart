import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'config/app_config.dart';
import 'providers.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: ClientPortalApp()));
}

class ClientPortalApp extends ConsumerWidget {
  const ClientPortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Currency is a tenant setting, so re-apply it whenever the session's
    // tenant changes — one build serves clients of a TZS tenant and a KES
    // tenant alike.
    ref.listen(sessionControllerProvider, (_, session) {
      Formatting.setTenantCurrency(session.tenant?.currency);
    });

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
