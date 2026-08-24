import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../providers.dart';

/// Cold-start screen: restores the stored session, and — when the server
/// cannot be reached to validate it — offers retry or a fresh sign-in
/// instead of guessing which shell the token belongs to.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionControllerProvider).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final offline = session.status == SessionStatus.offline;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 56),
              const SizedBox(height: Spacing.md),
              Text(AppConfig.appName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Spacing.xl),
              if (!offline)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Could not reach the server',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  session.restoreError ??
                      'Your sign-in could not be checked. Connect and try '
                          'again, or sign in afresh.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  onPressed: () =>
                      ref.read(sessionControllerProvider).restore(),
                ),
                const SizedBox(height: Spacing.xs),
                TextButton(
                  onPressed: () =>
                      ref.read(sessionControllerProvider).forgetStoredSession(),
                  child: const Text('Sign in with a different account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
