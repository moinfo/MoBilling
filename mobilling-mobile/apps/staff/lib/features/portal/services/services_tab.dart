import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Services hub: subscriptions, hosting accounts and domains, switched by a
/// segmented control. A tab body inside the portal shell — the masthead is
/// the shell's, so the only chrome here is the quiet filter row.
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
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.xs,
          ),
          child: SegmentedButton<_Section>(
            segments: const [
              ButtonSegment(
                value: _Section.subscriptions,
                label: Text('Services'),
              ),
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

/// The mono metadata line under a list title: `label · cycle · date`,
/// upper-cased because it names rather than says.
class _MetaLine extends StatelessWidget {
  const _MetaLine(this.parts, {this.color});

  final List<String> parts;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      parts.join(' · ').toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A date as the trailing figure of a row, in the mono face so a column of
/// them lines up; coloured only when the date itself is the news.
class _TrailingDate extends StatelessWidget {
  const _TrailingDate(this.date, {this.color});

  final DateTime? date;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      Formatting.date(date).toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

class _SubscriptionsList extends ConsumerWidget {
  const _SubscriptionsList();

  Future<void> _generateInvoice(
    BuildContext context,
    WidgetRef ref,
    ClientSubscription sub,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final invoice = await ref
          .read(portalServiceProvider)
          .generateSubscriptionInvoice(sub.id);
      ref.invalidate(portalDashboardProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            invoice.message ?? 'Invoice ${invoice.documentNumber} created.',
          ),
        ),
      );
      router.push(PortalRoutes.invoicePath(invoice.documentId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(portalSubscriptionsProvider);
    final theme = Theme.of(context);

    return subs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load services',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(portalSubscriptionsProvider),
      ),
      data: (items) => items.isEmpty
          ? StateMessage(
              icon: Icons.dns_outlined,
              title: 'No services yet',
              message: 'Services you subscribe to will appear here.',
              actionLabel: 'Order a service',
              onAction: () => context.push(PortalRoutes.store),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(portalSubscriptionsProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  const SectionHeader('Your services'),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, sub) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              sub.productName ?? 'Service',
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: Spacing.xs),
                              child: Row(
                                children: [
                                  StatusChip(sub.status, dense: true),
                                  const SizedBox(width: Spacing.sm),
                                  Flexible(
                                    child: _MetaLine([
                                      if (sub.label != null) sub.label!,
                                      if (sub.billingCycle != null &&
                                          sub.billingCycle != 'once')
                                        sub.billingCycle!.replaceAll('_', ' '),
                                      if (sub.nextInvoiceDate != null)
                                        'next ${Formatting.date(sub.nextInvoiceDate)}',
                                    ]),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Money(sub.price * sub.quantity),
                          ),
                          if (sub.status == 'active' &&
                                  sub.billingCycle != 'once' ||
                              sub.hostingAccountId != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Spacing.sm,
                                0,
                                Spacing.sm,
                                Spacing.xs,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
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
                                        PortalRoutes.hostingPath(
                                          sub.hostingAccountId!,
                                        ),
                                      ),
                                      child: const Text('Manage hosting'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
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
    final accounts = ref.watch(portalHostingProvider);
    final theme = Theme.of(context);

    return accounts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load hosting',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(portalHostingProvider),
      ),
      data: (items) => items.isEmpty
          ? StateMessage(
              icon: Icons.storage_outlined,
              title: 'No hosting accounts',
              message: 'Hosting you order will appear here.',
              actionLabel: 'Order hosting',
              onAction: () => context.push(PortalRoutes.store),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(portalHostingProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  const SectionHeader('Hosting accounts'),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, a) in items.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              a.domain ?? a.cpanelUsername ?? '—',
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: Spacing.xs),
                              child: Row(
                                children: [
                                  StatusChip(a.status, dense: true),
                                  const SizedBox(width: Spacing.sm),
                                  Flexible(
                                    child: _MetaLine([
                                      if (a.package != null) a.package!,
                                      if (a.diskUsed != null &&
                                          a.diskLimit != null)
                                        '${a.diskUsed} / ${a.diskLimit}',
                                      if (a.expiresAt != null) 'renews',
                                    ]),
                                  ),
                                ],
                              ),
                            ),
                            trailing: a.expiresAt == null
                                ? Icon(
                                    Icons.chevron_right,
                                    color: theme.colorScheme.outline,
                                  )
                                : _TrailingDate(a.expiresAt),
                            onTap: () =>
                                context.push(PortalRoutes.hostingPath(a.id)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
    final domains = ref.watch(portalDomainsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return domains.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load domains',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(portalDomainsProvider),
      ),
      data: (list) => list.domains.isEmpty
          ? StateMessage(
              icon: Icons.language_outlined,
              title: 'No domains yet',
              message: 'Domains you register or transfer will appear here.',
              actionLabel: 'Get a domain',
              onAction: () => context.push(PortalRoutes.domainSearch),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(portalDomainsProvider.future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  // The counts as one strip. "Expiring" is the only figure
                  // that ever needs a colour: it means within 45 days, and
                  // it is the one a domain owner should act on.
                  StatRail(
                    items: [
                      StatRailItem(
                        label: 'Active',
                        value: Formatting.integer(list.stats.active),
                      ),
                      StatRailItem(
                        label: 'Expiring',
                        value: Formatting.integer(list.stats.expiringSoon),
                        emphasis: list.stats.expiringSoon > 0
                            ? status.attention
                            : null,
                      ),
                      StatRailItem(
                        label: 'Expired',
                        value: Formatting.integer(list.stats.expired),
                        emphasis: list.stats.expired > 0
                            ? status.overdue
                            : null,
                      ),
                      StatRailItem(
                        label: 'Pending',
                        value: Formatting.integer(list.stats.pending),
                      ),
                    ],
                  ),
                  if (list.stats.expiringSoon > 0) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      list.stats.expiringSoon == 1
                          ? '1 domain expires within 45 days.'
                          : '${list.stats.expiringSoon} domains expire within 45 days.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.attention,
                      ),
                    ),
                  ],
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('Your domains'),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, d) in list.domains.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              d.name,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: Spacing.xs),
                              child: Row(
                                children: [
                                  StatusChip(d.status, dense: true),
                                  const SizedBox(width: Spacing.sm),
                                  Flexible(
                                    child: _MetaLine(
                                      [
                                        if (d.expiresAt != null) 'expires',
                                        if (d.autoRenew) 'auto-renew',
                                        if (d.sslValid == false) 'SSL invalid',
                                      ],
                                      color: d.sslValid == false
                                          ? status.overdue
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: d.expiresAt == null
                                ? Icon(
                                    Icons.chevron_right,
                                    color: theme.colorScheme.outline,
                                  )
                                : _TrailingDate(
                                    d.expiresAt,
                                    color: d.expiringSoon
                                        ? status.attention
                                        : null,
                                  ),
                            onTap: () =>
                                context.push(PortalRoutes.domainPath(d.id)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
