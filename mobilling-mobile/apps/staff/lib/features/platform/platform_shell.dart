import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../navigation/admin_menu.dart';
import '../../providers.dart';
import '../auth/session_expired_sheet.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'platform_providers.dart';

/// The platform super-admin home: totals, then the menu.
///
/// A super admin has no tenant, so there is no bottom bar to scope — the
/// whole shell is a dashboard plus a list of platform areas.
class PlatformHomeScreen extends ConsumerStatefulWidget {
  const PlatformHomeScreen({super.key});

  @override
  ConsumerState<PlatformHomeScreen> createState() =>
      _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends ConsumerState<PlatformHomeScreen> {
  bool _promptOpen = false;

  Future<void> _promptReauthentication() async {
    if (_promptOpen) return;
    _promptOpen = true;
    try {
      await SessionExpiredSheet.show(context);
    } finally {
      _promptOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(platformDashboardProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    ref.listen<SessionStatus>(sessionStatusProvider, (previous, next) {
      if (next == SessionStatus.expired) _promptReauthentication();
    });

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform', style: theme.textTheme.titleMedium),
            Text(user?.name ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(sessionControllerProvider).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(platformDashboardProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            dashboard.maybeWhen(
              data: (d) => Column(
                children: [
                  if (d.pendingPurchases > 0)
                    Container(
                      padding: const EdgeInsets.all(Spacing.md),
                      margin: const EdgeInsets.only(bottom: Spacing.md),
                      decoration: BoxDecoration(
                        color: status.attention.withValues(alpha: 0.12),
                        borderRadius: Radii.card,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.pending_actions_outlined,
                              size: 18, color: status.attention),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              '${d.pendingPurchases} SMS purchase${d.pendingPurchases == 1 ? '' : 's'} awaiting confirmation',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.push(AdminRoutes.smsPurchases),
                            child: const Text('Review'),
                          ),
                        ],
                      ),
                    ),
                  // The platform's own money leads, with its own SMS stock
                  // as the secondary line — the same shape as the client
                  // portal's balance card, because it answers the same kind
                  // of question about the operator's account.
                  Builder(builder: (context) {
                    // Zero is not "healthy", it is just zero — tinting an
                    // empty month green reads as a result rather than an
                    // absence of one.
                    final earning = d.totalSmsRevenue > 0;
                    final tone = earning
                        ? status.settled
                        : theme.colorScheme.onSurfaceVariant;
                    return Card(
                    color: Color.alphaBlend(
                      tone.withValues(alpha: 0.06),
                      theme.colorScheme.surface,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SMS REVENUE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: Type.eyebrowTracking,
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Money(
                              d.totalSmsRevenue,
                              scale: MoneyScale.display,
                              color: earning ? status.settled : null,
                            ),
                          ),
                          if (d.masterSmsBalance != null) ...[
                            const SizedBox(height: Spacing.sm),
                            Row(
                              children: [
                                Text(
                                  'Master SMS balance',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: Spacing.sm),
                                Text(
                                  Formatting.integer(d.masterSmsBalance),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: Type.figures,
                                    // Running the platform's own SMS stock
                                    // dry stops every tenant's messaging, so
                                    // it says so before it happens.
                                    color: (d.masterSmsBalance ?? 0) < 1000
                                        ? status.overdue
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                  }),
                  const SizedBox(height: Spacing.sm),
                  StatRail(
                    items: [
                      StatRailItem(
                        label: 'Tenants',
                        value: '${Formatting.integer(d.activeTenants)}/'
                            '${Formatting.integer(d.totalTenants)}',
                      ),
                      StatRailItem(label: 'Users', value: Formatting.integer(d.totalUsers)),
                      StatRailItem(
                        label: 'SMS sold',
                        value: Formatting.integer(d.totalSmsSold),
                      ),
                      StatRailItem(
                        label: 'Enabled',
                        value: Formatting.integer(d.smsEnabledTenants),
                      ),
                    ],
                  ),
                ],
              ),
              orElse: () => const Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Manage'),
            const SizedBox(height: Spacing.sm),
            Card(
              child: Column(
                children: [
                  for (final (i, entry) in adminMenu.indexed)
                    // Skip the dashboard itself — we're on it.
                    if (entry.path != AdminRoutes.home) ...[
                      if (i > 1) const Divider(height: 1),
                      ListTile(
                        leading: Icon(entry.icon),
                        title: Text(entry.label),
                        subtitle: entry.subtitle == null
                            ? null
                            : Text(entry.subtitle!,
                                style: theme.textTheme.bodySmall),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(entry.path),
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// A simple list screen used by the reference-data areas (plans, currencies,
/// SMS packages, permissions, role templates) — each is a short list where
/// the interesting content is the row itself.
class PlatformListScaffold<T> extends ConsumerWidget {
  const PlatformListScaffold({
    super.key,
    required this.title,
    required this.value,
    required this.itemBuilder,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    this.footnote,
    this.floatingActionButton,
  });

  final String title;
  final AsyncValue<List<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final VoidCallback onRetry;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? footnote;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: floatingActionButton,
      body: CrmAsyncView(
        value: value,
        errorTitle: 'Could not load $title',
        onRetry: onRetry,
        builder: (items) => items.isEmpty
            ? StateMessage(icon: emptyIcon, title: emptyTitle)
            : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: itemBuilder(context, item),
                    ),
                  if (footnote != null) ...[
                    const SizedBox(height: Spacing.md),
                    Text(
                      footnote!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Spacing.xl),
                ],
              ),
      ),
    );
  }
}
