import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/theme_mode.dart';
import '../../navigation/shell.dart';
import '../../providers.dart';

/// Who is signed in, and the way out.
///
/// Opened from the masthead's account tile in every shell. Sign-out lives
/// here rather than on the top bar because it is the one action on the
/// screen that throws work away; a tap that costs a sheet first is the
/// right price for it.
class AccountSheet extends ConsumerWidget {
  const AccountSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => const AccountSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
    final tenant = session.tenant;

    final contact = user?.email ?? user?.phone;
    final role = switch (user) {
      null => null,
      AuthUser(userType: UserType.client, isPortalAdmin: true) =>
        'Portal administrator',
      AuthUser(userType: UserType.client) => 'Portal user',
      AuthUser(isSuperAdmin: true) => 'Platform administrator',
      AuthUser(:final role?) => StatusColors.label(role),
      _ => 'Staff',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tenant != null) ...[
              Text(
                tenant.name.toUpperCase(),
                style: Type.mono(
                  10.5,
                  tracking: 0.08,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
            ],
            Text(
              user?.name ?? 'Signed in',
              style: Type.display(24, color: scheme.onSurface),
            ),
            if (role != null || contact != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                [?role, ?contact].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Text('Appearance', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            const AppearanceControl(),
            // Two-factor lives behind this: the phone is the device most
            // likely to be lost, so checking and revoking the second factor
            // has to be reachable from it. `/auth/2fa/*` is `auth:sanctum`
            // only — any signed-in tenant user, staff or super admin, may
            // manage their own factor. (The portal shell is its own
            // follow-up: `security_screen.dart` assumes a staff session.)
            if (session.session.shell != AppShell.portal) ...[
              const SizedBox(height: Spacing.lg),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Security'),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/security');
                },
              ),
            ],
            // A super admin who is currently signed in as a tenant — the
            // web's orange "Viewing: {tenant}" bar has no room to exist on a
            // masthead this short, so the way back lives here instead. Above
            // Sign out and in the theme's ordinary colour: this restores
            // your own session, it doesn't end one.
            if (session.isImpersonating) ...[
              const SizedBox(height: Spacing.lg),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(
                  'Back to ${session.preImpersonationName ?? 'your account'}',
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(sessionControllerProvider).exitImpersonation();
                },
              ),
            ],
            const SizedBox(height: Spacing.lg),
            OutlinedButton.icon(
              icon: Icon(Icons.logout_rounded, size: 18, color: scheme.error),
              label: Text('Sign out', style: TextStyle(color: scheme.error)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(sessionControllerProvider).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
