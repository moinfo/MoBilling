import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Everything that doesn't earn a bottom-nav slot: payment history, the
/// statement, account management and sign-out.
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Who's signed in — tap through to the profile.
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                (user?.name.isNotEmpty ?? false)
                    ? user!.name[0].toUpperCase()
                    : '?',
              ),
            ),
            title: Text(user?.name ?? '—'),
            subtitle: Text(user?.email ?? user?.phone ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.profile),
          ),
        ),
        const SizedBox(height: Spacing.md),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Account credit'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.credit),
              ),
              if (user?.isPortalAdmin ?? false) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Portal users'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.portalUsers),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Order new services'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.store),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: const Text('Register or transfer a domain'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.domainSearch),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Payment history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.payments),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Account statement'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.statement),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),

        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => ref.read(sessionControllerProvider).logout(),
          ),
        ),
      ],
    );
  }
}
