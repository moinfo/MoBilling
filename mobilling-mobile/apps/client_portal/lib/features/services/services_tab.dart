import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Services hub: subscriptions, hosting accounts and domains, switched by a
/// segmented control.
class ServicesTab extends ConsumerStatefulWidget {
  const ServicesTab({super.key});

  @override
  ConsumerState<ServicesTab> createState() => _ServicesTabState();
}

enum _Section { subscriptions, hosting, domains }

class _ServicesTabState extends ConsumerState<ServicesTab> {
  _Section _section = _Section.subscriptions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: SegmentedButton<_Section>(
            segments: const [
              ButtonSegment(
                  value: _Section.subscriptions, label: Text('Services')),
              ButtonSegment(value: _Section.hosting, label: Text('Hosting')),
              ButtonSegment(value: _Section.domains, label: Text('Domains')),
            ],
            selected: {_section},
            onSelectionChanged: (s) => setState(() => _section = s.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: switch (_section) {
            _Section.subscriptions => const _SubscriptionsList(),
            _Section.hosting => const _HostingList(),
            _Section.domains => const _DomainsList(),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

class _SubscriptionsList extends ConsumerWidget {
  const _SubscriptionsList();

  Future<void> _generateInvoice(
      BuildContext context, WidgetRef ref, ClientSubscription sub) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final invoice = await ref
          .read(portalServiceProvider)
          .generateSubscriptionInvoice(sub.id);
      ref.invalidate(dashboardProvider);
      messenger.showSnackBar(SnackBar(
          content:
              Text(invoice.message ?? 'Invoice ${invoice.documentNumber} created.')));
      router.push(Routes.invoicePath(invoice.documentId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subscriptionsProvider);
    final theme = Theme.of(context);

    return subs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load services',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(subscriptionsProvider),
      ),
      data: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.dns_outlined,
              title: 'No services yet',
              message: 'Services you subscribe to will appear here.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(subscriptionsProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final sub = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sub.productName ?? 'Service',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              StatusChip(sub.status, dense: true),
                            ],
                          ),
                          if (sub.label != null) ...[
                            const SizedBox(height: 2),
                            Text(sub.label!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ],
                          const SizedBox(height: Spacing.xs),
                          Text(
                            [
                              Formatting.currency(sub.price * sub.quantity),
                              if (sub.billingCycle != null &&
                                  sub.billingCycle != 'once')
                                sub.billingCycle!.replaceAll('_', ' '),
                              if (sub.nextInvoiceDate != null)
                                'next ${Formatting.date(sub.nextInvoiceDate)}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: Spacing.sm),
                          Row(
                            children: [
                              if (sub.status == 'active' &&
                                  sub.billingCycle != 'once')
                                TextButton(
                                  onPressed: () =>
                                      _generateInvoice(context, ref, sub),
                                  child: const Text('Generate invoice'),
                                ),
                              if (sub.hostingAccountId != null)
                                TextButton(
                                  onPressed: () => context.push(
                                      Routes.hostingPath(
                                          sub.hostingAccountId!)),
                                  child: const Text('Manage hosting'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hosting
// ---------------------------------------------------------------------------

class _HostingList extends ConsumerWidget {
  const _HostingList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(hostingProvider);
    final theme = Theme.of(context);

    return accounts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load hosting',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(hostingProvider),
      ),
      data: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.storage_outlined,
              title: 'No hosting accounts',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(hostingProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final a = items[index];
                  return Card(
                    child: ListTile(
                      title: Text(a.domain ?? a.cpanelUsername ?? '—'),
                      subtitle: Text([
                        if (a.package != null) a.package!,
                        if (a.diskUsed != null && a.diskLimit != null)
                          '${a.diskUsed} / ${a.diskLimit}',
                        if (a.expiresAt != null)
                          'renews ${Formatting.date(a.expiresAt)}',
                      ].join(' · '),
                          style: theme.textTheme.bodySmall),
                      trailing: StatusChip(a.status, dense: true),
                      onTap: () => context.push(Routes.hostingPath(a.id)),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Domains
// ---------------------------------------------------------------------------

class _DomainsList extends ConsumerWidget {
  const _DomainsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domains = ref.watch(domainsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return domains.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load domains',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(domainsProvider),
      ),
      data: (list) => list.domains.isEmpty
          ? const StateMessage(
              icon: Icons.language_outlined,
              title: 'No domains yet',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(domainsProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  if (list.stats.expiringSoon > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(Spacing.md),
                      decoration: BoxDecoration(
                        color: status.attention.withValues(alpha: 0.12),
                        borderRadius: Radii.card,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: status.attention),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              list.stats.expiringSoon == 1
                                  ? '1 domain expires within 45 days'
                                  : '${list.stats.expiringSoon} domains expire within 45 days',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                  ],
                  for (final d in list.domains) ...[
                    Card(
                      child: ListTile(
                        title: Text(d.name),
                        subtitle: Text(
                          [
                            if (d.expiresAt != null)
                              'expires ${Formatting.date(d.expiresAt)}',
                            if (d.autoRenew) 'auto-renew',
                            if (d.sslValid == false) 'SSL invalid',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: d.expiringSoon
                                ? status.attention
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: StatusChip(d.status, dense: true),
                        onTap: () => context.push(Routes.domainPath(d.id)),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                  ],
                ],
              ),
            ),
    );
  }
}
