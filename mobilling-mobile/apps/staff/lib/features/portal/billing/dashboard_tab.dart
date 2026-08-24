import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';
import '../portal_routes.dart';

/// The client-area home: balance, counters, recent activity.
///
/// Mirrors the staff dashboard's composition: the masthead's ink continues
/// into a money panel carrying the one figure a client opens the app for —
/// their balance — and the first paper card rides up over the panel's bottom
/// edge, the sign-in screen's device.
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
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(portalDashboardProvider),
      ),
      data: (dash) => RefreshIndicator(
        onRefresh: () => ref.refresh(portalDashboardProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Layout keeps the panel's extra bottom padding; the paint moves
          // up by the overlap, and the list's bottom padding gives the same
          // amount back.
          padding: const EdgeInsets.only(
            bottom: Spacing.xl - _MoneyPanel.overlap,
          ),
          children: [
            _BalancePanel(dash: dash),
            Transform.translate(
              offset: const Offset(0, -_MoneyPanel.overlap),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  0,
                  Spacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RaisedFirst(child: _CounterRail(dash: dash)),
                    if (dash.recentInvoices.isNotEmpty) ...[
                      const SizedBox(height: Spacing.lg),
                      const SectionHeader('Recent invoices'),
                      const SizedBox(height: Spacing.sm),
                      Card(
                        child: Column(
                          children: [
                            for (final (i, inv)
                                in dash.recentInvoices.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              InvoiceRow(invoice: inv),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (dash.recentPayments.isNotEmpty) ...[
                      const SizedBox(height: Spacing.lg),
                      const SectionHeader('Recent payments'),
                      const SizedBox(height: Spacing.sm),
                      Card(
                        child: Column(
                          children: [
                            for (final (i, p)
                                in dash.recentPayments.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _PaymentTile(payment: p),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (dash.upcomingSubscriptions.isNotEmpty) ...[
                      const SizedBox(height: Spacing.lg),
                      const SectionHeader('Upcoming renewals'),
                      const SizedBox(height: Spacing.sm),
                      Card(
                        child: Column(
                          children: [
                            for (final (i, sub)
                                in dash.upcomingSubscriptions.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _RenewalTile(subscription: sub),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decides what the money panel says about the account, then hands the
/// figures to [_MoneyPanel].
class _BalancePanel extends ConsumerWidget {
  const _BalancePanel({required this.dash});

  final PortalDashboard dash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Figures on ink use the dark palette whatever the app's theme is.
    const status = StatusColors.dark;

    final balance = dash.totalBalance;
    final inCredit = balance < 0;
    final owes = balance > 0;
    final hasOverdue = dash.overdueCount > 0;
    final toPay = dash.unpaidInvoicesCount;

    // The pill answers "is anything wrong with this account?", which is a
    // different question from "is the balance positive". A client can be in
    // credit overall and still have invoices past due, and the panel has to
    // be able to say both without contradicting itself.
    final (String pill, Color dot) = hasOverdue
        ? (
            dash.overdueCount == 1
                ? '1 invoice overdue'
                : '${Formatting.integer(dash.overdueCount)} invoices overdue',
            status.overdue,
          )
        : toPay > 0
        ? (
            toPay == 1
                ? '1 invoice to pay'
                : '${Formatting.integer(toPay)} invoices to pay',
            status.attention,
          )
        : ('Nothing outstanding', status.settled);

    return _MoneyPanel(
      pill: pill,
      pillDot: dot,
      // "N invoices overdue" is the sentence every client tries to tap.
      onPillTap: hasOverdue || toPay > 0
          ? () =>
                ref.read(portalTabProvider.notifier).state = PortalTab.invoices
          : null,
      label: inCredit
          ? 'In credit'
          : (owes || hasOverdue)
          ? 'Balance due'
          : 'Balance',
      // A negative balance is credit, not a debt of minus one million. Show
      // it as the positive quantity it is and let the label carry the sign.
      amount: inCredit ? -balance : balance,
      strip: [
        (
          label: 'Unpaid',
          value: Formatting.integer(toPay),
          tone: toPay > 0 ? status.attention : null,
        ),
        (
          label: 'Overdue',
          value: Formatting.integer(dash.overdueCount),
          tone: hasOverdue ? status.overdue : null,
        ),
        (
          label: 'Credit',
          value: Formatting.compact(dash.creditBalance),
          tone: dash.creditBalance > 0 ? status.settled : null,
        ),
      ],
    );
  }
}

/// One figure in the money panel's strip.
typedef _StripFigure = ({String label, String value, Color? tone});

/// The account's money, on ink.
///
/// The sign-in panel's composition, filled with the one figure this screen
/// is about: eyebrow pill, a display-face figure in white, and the handoff's
/// translucent stat strip beneath it for the figures that explain it. The
/// blue glow is left to the masthead above and only the green one is drawn
/// here, so the two panels read as a single surface with one light source.
class _MoneyPanel extends StatelessWidget {
  const _MoneyPanel({
    required this.pill,
    required this.pillDot,
    required this.label,
    required this.amount,
    required this.strip,
    this.onPillTap,
  });

  final String pill;
  final Color pillDot;
  final VoidCallback? onPillTap;
  final String label;
  final Object? amount;
  final List<_StripFigure> strip;

  /// How far the first paper card rides up over the panel's bottom edge.
  static const double overlap = 28;

  @override
  Widget build(BuildContext context) {
    return InkPanel(
      rule: false,
      blueGlow: false,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg + overlap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Reveal(
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: onPillTap,
                borderRadius: BorderRadius.circular(999),
                child: EyebrowPill(pill, dotColor: pillDot),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Reveal(
            delay: const Duration(milliseconds: 80),
            child: Text(
              label.toUpperCase(),
              style: Type.mono(10.5, tracking: 0.08, color: InkPanel.mutedText),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Reveal(
            delay: const Duration(milliseconds: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(
                amount,
                scale: MoneyScale.display,
                display: true,
                color: Colors.white,
              ),
            ),
          ),
          if (strip.isNotEmpty) ...[
            const SizedBox(height: Spacing.lg),
            Reveal(
              delay: const Duration(milliseconds: 200),
              child: _StatStrip(figures: strip),
            ),
          ],
        ],
      ),
    );
  }
}

/// The handoff's floating stat strip: translucent card, figures in the
/// display face, Plex Mono labels, hairline dividers between columns.
class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.figures});

  final List<_StripFigure> figures;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.md,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.cardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (final (i, f) in figures.indexed) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  indent: 2,
                  endIndent: 2,
                  color: Colors.white.withValues(alpha: 0.14),
                ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        f.value,
                        style: Type.display(
                          22,
                          color: f.tone ?? Colors.white,
                        ).copyWith(fontFeatures: Type.figures),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      f.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.mono(
                        9.5,
                        tracking: 0.08,
                        color: InkPanel.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The first paper card, raised over the ink with the sign-in card's soft
/// ink shadow so the overlap reads as depth rather than as a misalignment.
class _RaisedFirst extends StatelessWidget {
  const _RaisedFirst({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: Radii.card,
      boxShadow: [
        BoxShadow(
          color: Brand.ink.withValues(alpha: 0.28),
          blurRadius: 44,
          offset: const Offset(0, 24),
          spreadRadius: -30,
        ),
      ],
    ),
    child: child,
  );
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
          emphasis: dash.unpaidInvoicesCount > 0 ? status.attention : null,
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
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(
        payment.documentNumber ?? payment.reference ?? 'Payment',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        [
          Formatting.date(payment.paymentDate),
          if (payment.paymentMethod != null) payment.paymentMethod!,
        ].join(' · ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Money(payment.amount, color: status.settled),
    );
  }
}

class _RenewalTile extends StatelessWidget {
  const _RenewalTile({required this.subscription});

  final UpcomingSubscription subscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = subscription;

    return ListTile(
      dense: true,
      title: Text(
        sub.service ?? sub.label ?? 'Service',
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (sub.schedule != null) sub.schedule!,
          if (sub.nextInvoiceDate != null)
            'next ${Formatting.date(sub.nextInvoiceDate)}',
        ].join(' · ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Money(sub.price * sub.quantity),
    );
  }
}

/// Shared invoice row — used by the dashboard and the invoices tab.
///
/// A row, not a card: the caller decides whether it sits in a shared card
/// with dividers (the dashboard) or in a card of its own (the paged list).
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

    return InkWell(
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
                  Text(invoice.documentNumber, style: theme.textTheme.titleSmall),
                  if (invoice.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      invoice.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
                          (unpaid
                                  ? Formatting.dueDescription(invoice.dueDate)
                                  : Formatting.date(invoice.date))
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: late
                                ? status.overdue
                                : theme.colorScheme.onSurfaceVariant,
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
    );
  }
}
