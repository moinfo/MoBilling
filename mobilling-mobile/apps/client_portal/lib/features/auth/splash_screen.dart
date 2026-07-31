import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../providers.dart';

/// Shown while a stored token is restored and validated against `/auth/me`.
///
/// Kicking the restore off here rather than in `main()` keeps startup
/// synchronous: the first frame paints immediately and the network round-trip
/// happens behind this screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred past the first frame — restore() notifies listeners, and
    // go_router's redirect must not run mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionControllerProvider).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: Spacing.md),
            Text(AppConfig.appName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: Spacing.xl),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
