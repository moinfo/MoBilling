import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// The client-area home: balance, counters, recent activity.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(portalDashboardProvider);

    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load your dashboard',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(portalDashboardProvider),
      ),
      data: (dash) => RefreshIndicator(
        onRefresh: () => ref.refresh(portalDashboardProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _BalanceCard(dash: dash),
            const SizedBox(height: Spacing.md),
            _CounterRail(dash: dash),
            if (dash.recentInvoices.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Recent invoices'),
              const SizedBox(height: Spacing.sm),
              ...dash.recentInvoices.map((inv) => Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: InvoiceRow(invoice: inv),
                  )),
            ],
            if (dash.recentPayments.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              const SectionHeader('Recent payments'),
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
              const SectionHeader('Upcoming renewals'),
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
                        trailing: Money(sub.price * sub.quantity),
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

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.dash});

  final PortalDashboard dash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final balance = dash.totalBalance;
    final inCredit = balance < 0;
    final owes = balance > 0;
    final hasOverdue = dash.overdueCount > 0;

    // The tint answers "is anything wrong with this account?", which is a
    // different question from "is the balance positive". A client can be in
    // credit overall and still have invoices past due, and the card has to be
    // able to say both without contradicting itself.
    final tone = hasOverdue
        ? status.overdue
        : owes
            ? status.attention
            : status.settled;

    // A negative balance is credit, not a debt of minus one million. Show it
    // as the positive quantity it is and let the label carry the sign.
    final figure = inCredit ? -balance : balance;

    // The tint sits directly behind the figure, so it has to agree with the
    // figure — a pink card under a green number reads as a mistake. The
    // account-level warning is carried by the action line instead, which is
    // where it can actually be acted on.
    final figureTone = inCredit ? status.settled : tone;
    final settledUp = !owes && !hasOverdue && dash.unpaidInvoicesCount == 0;

    return Card(
      color: Color.alphaBlend(
        figureTone.withValues(alpha: 0.06),
        theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inCredit
                  ? 'IN CREDIT'
                  : (owes || hasOverdue)
                      ? 'BALANCE DUE'
                      : 'BALANCE',
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
                figure,
                scale: MoneyScale.display,
                color: figureTone,
              ),
            ),
            if (settledUp) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Nothing outstanding.',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: status.settled),
              ),
            ],
            if (hasOverdue)
              _BalanceAction(
                icon: Icons.warning_amber_rounded,
                color: status.overdue,
                label: dash.overdueCount == 1
                    ? '1 invoice overdue'
                    : '${dash.overdueCount} invoices overdue',
                onTap: () => ref.read(portalTabProvider.notifier).state =
                    PortalTab.invoices,
              )
            else if (dash.unpaidInvoicesCount > 0)
              _BalanceAction(
                icon: Icons.schedule_outlined,
                color: status.attention,
                label: dash.unpaidInvoicesCount == 1
                    ? '1 invoice to pay'
                    : '${dash.unpaidInvoicesCount} invoices to pay',
                onTap: () => ref.read(portalTabProvider.notifier).state =
                    PortalTab.invoices,
              ),
            if (dash.creditBalance > 0) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Text(
                    'Wallet credit',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Money(
                    dash.creditBalance,
                    scale: MoneyScale.dense,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one line on the balance card that goes somewhere. Styled as a control,
/// not as prose, because "6 invoices overdue" is the sentence every client
/// tries to tap.
class _BalanceAction extends StatelessWidget {
  const _BalanceAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _CounterRail extends ConsumerWidget {
  const _CounterRail({required this.dash});

  final PortalDashboard dash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = context.statusColors;
    void go(int tab) => ref.read(portalTabProvider.notifier).state = tab;

    return StatRail(
      items: [
        StatRailItem(
          label: 'Services',
          value: Formatting.integer(dash.servicesCount),
          onTap: () => go(PortalTab.services),
        ),
        StatRailItem(
          label: 'Domains',
          value: Formatting.integer(dash.domainsCount),
          onTap: () => go(PortalTab.services),
        ),
        StatRailItem(
          label: 'Unpaid',
          value: Formatting.integer(dash.unpaidInvoicesCount),
          emphasis:
              dash.unpaidInvoicesCount > 0 ? status.attention : null,
          onTap: () => go(PortalTab.invoices),
        ),
        StatRailItem(
          label: 'Tickets',
          value: Formatting.integer(dash.ticketsCount),
          emphasis: dash.ticketsCount > 0 ? status.pending : null,
          onTap: () => go(PortalTab.support),
        ),
      ],
    );
  }
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
      trailing: Money(payment.amount, color: status.settled),
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
    final status = context.statusColors;
    final unpaid = invoice.balance > 0;
    final late = unpaid && (Formatting.daysUntil(invoice.dueDate) ?? 1) < 0;

    // "Overdue by 5 days" already says everything a status chip reading
    // "Sent" or "Overdue" would, and says it more precisely. The chip earns
    // its place only where the due line cannot stand in for it — a settled
    // invoice, or one that has been part-paid.
    final String? chipStatus = unpaid
        ? (invoice.status.toLowerCase() == 'partial' ? invoice.status : null)
        : invoice.status;

    return Card(
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(PortalRoutes.invoicePath(invoice.id)),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                    Row(
                      children: [
                        if (chipStatus != null) ...[
                          StatusChip(chipStatus, dense: true),
                          const SizedBox(width: Spacing.sm),
                        ],
                        Flexible(
                          child: Text(
                            unpaid
                                ? Formatting.dueDescription(invoice.dueDate)
                                : Formatting.date(invoice.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: late
                                  ? status.overdue
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight:
                                  late ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              // Nothing but the amount on the right, so the figures form a
              // single column down the list. That column is the reason the
              // readout uses tabular figures at all.
              //
              // Left in ink even when the invoice is late: the due line
              // already says so, and colouring the amount too turns a list of
              // overdue invoices into a wall of orange where nothing stands
              // out. The state is a property of the date, not of the sum.
              Money(unpaid ? invoice.balance : invoice.total),
            ],
          ),
        ),
      ),
    );
  }
}
