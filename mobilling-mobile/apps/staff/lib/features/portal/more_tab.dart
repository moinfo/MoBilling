import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import 'portal_routes.dart';

/// Everything that doesn't earn a bottom-nav slot: payment history, the
/// statement, account management and sign-out. A body inside the portal
/// shell — the masthead belongs to the shell.
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(currentUserProvider);
    final name = user?.name.trim() ?? '';

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Who's signed in — tap through to the profile.
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurface,
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: Type.display(16, color: scheme.onSurface),
              ),
            ),
            title: Text(
              name.isEmpty ? '—' : name,
              style: theme.textTheme.titleSmall,
            ),
            subtitle: Text(
              (user?.email ?? user?.phone ?? '').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
            ),
            onTap: () => context.push(PortalRoutes.profile),
          ),
        ),
        const SizedBox(height: Spacing.lg),

        const SectionHeader('Billing'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              _Link(
                icon: Icons.payments_outlined,
                label: 'Payment history',
                onTap: () => context.push(PortalRoutes.payments),
              ),
              const Divider(height: 1),
              _Link(
                icon: Icons.account_balance_outlined,
                label: 'Account statement',
                onTap: () => context.push(PortalRoutes.statement),
              ),
              const Divider(height: 1),
              _Link(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Account credit',
                onTap: () => context.push(PortalRoutes.credit),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),

        const SectionHeader('Services'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              _Link(
                icon: Icons.storefront_outlined,
                label: 'Order new services',
                onTap: () => context.push(PortalRoutes.store),
              ),
              const Divider(height: 1),
              _Link(
                icon: Icons.language_outlined,
                label: 'Register or transfer a domain',
                onTap: () => context.push(PortalRoutes.domainSearch),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.lg),

        const SectionHeader('Your account'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              _Link(
                icon: Icons.person_outline,
                label: 'My profile',
                onTap: () => context.push(PortalRoutes.profile),
              ),
              if (user?.isPortalAdmin ?? false) ...[
                const Divider(height: 1),
                _Link(
                  icon: Icons.group_outlined,
                  label: 'Portal users',
                  onTap: () => context.push(PortalRoutes.portalUsers),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Sign out', style: TextStyle(color: scheme.error)),
                onTap: () => ref.read(sessionControllerProvider).logout(),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

/// One destination row: a quiet icon, the label, and a chevron.
class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.onSurfaceVariant),
      title: Text(label),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
