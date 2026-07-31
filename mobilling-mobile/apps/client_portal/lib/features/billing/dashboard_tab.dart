import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// The client-area home: balance, counters, recent activity.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your dashboard',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(dashboardProvider),
      ),
      data: (dash) => RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _BalanceCard(dash: dash),
            const SizedBox(height: Spacing.md),
            _CounterGrid(dash: dash),
            if (dash.recentInvoices.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              const _SectionHeader('Recent invoices'),
              const SizedBox(height: Spacing.sm),
              ...dash.recentInvoices.map((inv) => Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: InvoiceRow(invoice: inv),
                  )),
            ],
            if (dash.recentPayments.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              const _SectionHeader('Recent payments'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Column(
                  children: [
                    for (final (i, p) in dash.recentPayments.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      _PaymentTile(payment: p),
                    ],
                  ],
                ),
              ),
            ],
            if (dash.upcomingSubscriptions.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              const _SectionHeader('Upcoming renewals'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Column(
                  children: [
                    for (final (i, sub)
                        in dash.upcomingSubscriptions.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(sub.service ?? sub.label ?? 'Service'),
                        subtitle: Text([
                          if (sub.schedule != null) sub.schedule!,
                          if (sub.nextInvoiceDate != null)
                            'next ${Formatting.date(sub.nextInvoiceDate)}',
                        ].join(' · ')),
                        trailing: Text(
                          Formatting.currency(sub.price * sub.quantity),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.dash});

  final PortalDashboard dash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final owes = dash.totalBalance > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance due',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              Formatting.currency(dash.totalBalance),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: owes ? status.overdue : status.settled,
              ),
            ),
            if (dash.overdueCount > 0) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: status.overdue),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    dash.overdueCount == 1
                        ? '1 invoice overdue'
                        : '${dash.overdueCount} invoices overdue',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: status.overdue),
                  ),
                ],
              ),
            ],
            if (dash.creditBalance > 0) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Account credit: ${Formatting.currency(dash.creditBalance)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CounterGrid extends StatelessWidget {
  const _CounterGrid({required this.dash});

  final PortalDashboard dash;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      StatTile(
        label: 'Services',
        value: '${dash.servicesCount}',
        icon: Icons.dns_outlined,
      ),
      StatTile(
        label: 'Domains',
        value: '${dash.domainsCount}',
        icon: Icons.language_outlined,
      ),
      StatTile(
        label: 'Unpaid invoices',
        value: '${dash.unpaidInvoicesCount}',
        icon: Icons.receipt_long_outlined,
        emphasis: dash.unpaidInvoicesCount > 0
            ? context.statusColors.attention
            : null,
      ),
      StatTile(
        label: 'Open tickets',
        value: '${dash.ticketsCount}',
        icon: Icons.support_agent_outlined,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.sm,
      crossAxisSpacing: Spacing.sm,
      childAspectRatio: 1.9,
      children: tiles,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleSmall);
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final PaymentSummary payment;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    return ListTile(
      dense: true,
      leading: Icon(Icons.arrow_downward_rounded, color: status.settled),
      title: Text(payment.documentNumber ?? payment.reference ?? 'Payment'),
      subtitle: Text([
        Formatting.date(payment.paymentDate),
        if (payment.paymentMethod != null) payment.paymentMethod!,
      ].join(' · ')),
      trailing: Text(
        Formatting.currency(payment.amount),
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: status.settled),
      ),
    );
  }
}

/// Shared invoice row — used by the dashboard and the invoices tab.
class InvoiceRow extends StatelessWidget {
  const InvoiceRow({super.key, required this.invoice});

  final InvoiceSummary invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unpaid = invoice.balance > 0;

    return Card(
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(Routes.invoicePath(invoice.id)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invoice.documentNumber,
                        style: theme.textTheme.titleSmall),
                    if (invoice.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        invoice.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: Spacing.xs),
                    Text(
                      unpaid
                          ? Formatting.dueDescription(invoice.dueDate)
                          : Formatting.date(invoice.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: unpaid &&
                                (Formatting.daysUntil(invoice.dueDate) ?? 1) < 0
                            ? context.statusColors.overdue
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatting.currency(unpaid ? invoice.balance : invoice.total),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Spacing.xs),
                  StatusChip(invoice.status, dense: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
