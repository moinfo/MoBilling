import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../staff_self/staff_self_providers.dart';

/// Staff dashboard: this month's money, counts, recent invoices.
///
/// Null metrics mean the backend withheld them (per-field dashboard.*
/// permissions) — those cards are simply not rendered.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final status = context.statusColors;

    return dashboard.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the dashboard',
        message: error is ApiException ? error.message : null,
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(dashboardProvider),
      ),
      data: (d) {
        // The API scopes these three to the selected month, and scopes the
        // counters below to all time. Leaving both unlabelled produced a
        // dashboard that read "Outstanding 0.00" beside "572 overdue" — the
        // figures were right and the screen was still wrong. The two section
        // headers are the fix: they carry the scoping the numbers cannot.
        //
        // "Outstanding" is also not what the API returns. It is this month's
        // invoiced minus this month's receipts, which is a gap, not a
        // receivables balance, so it is named for what it is.
        final money = [
          if (d.totalReceived != null)
            (label: 'Collected', amount: d.totalReceived, tone: status.settled),
          if (d.totalReceivable != null)
            (label: 'Invoiced', amount: d.totalReceivable, tone: null),
          if (d.outstanding != null)
            (
              label: 'Gap',
              amount: d.outstanding,
              tone: (d.outstanding ?? 0) > 0 ? status.attention : null,
            ),
        ];

        // Counts, which are small integers and do not deserve a card each.
        final counts = [
          if (d.overdueInvoices != null)
            StatRailItem(
              label: 'Overdue',
              value: Formatting.integer(d.overdueInvoices),
              emphasis: (d.overdueInvoices ?? 0) > 0 ? status.attention : null,
            ),
          if (d.overdueBills != null)
            StatRailItem(
              label: 'Bills due',
              value: Formatting.integer(d.overdueBills),
              emphasis: (d.overdueBills ?? 0) > 0 ? status.overdue : null,
            ),
          if (d.totalClients != null)
            StatRailItem(
              label: 'Clients',
              value: Formatting.integer(d.totalClients),
            ),
          if (d.smsBalance != null)
            StatRailItem(label: 'SMS', value: Formatting.integer(d.smsBalance)),
          if (d.whatsappContacts != null)
            StatRailItem(
              label: 'WhatsApp',
              value: Formatting.integer(d.whatsappContacts),
            ),
          if (d.fieldVisits != null)
            StatRailItem(
              label: 'Prospects',
              value: Formatting.integer(d.fieldVisits),
            ),
        ];

        if (money.isEmpty && counts.isEmpty) {
          return const StateMessage(
            icon: Icons.lock_outline,
            title: 'No dashboard metrics available',
            message: 'Your role does not include any dashboard permissions.',
          );
        }

        // The money panel continues the masthead's ink, and the first paper
        // card rides up over its bottom edge — the sign-in screen's device,
        // reused so the app's front door and its first screen are one idea.
        final hero = money.isEmpty ? null : money.first;
        final overlap = hero != null;

        return RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: Spacing.xl - (overlap ? _MoneyPanel.overlap : 0),
            ),
            children: [
              if (hero != null)
                _MoneyPanel(
                  label: hero.label,
                  amount: hero.amount,
                  strip: [
                    for (final m in money.skip(1))
                      (
                        label: m.label,
                        value: Formatting.compact(m.amount),
                        tone: m.tone == null
                            ? null
                            : StatusColors.dark.attention,
                      ),
                    if (d.totalReceivable != null &&
                        d.totalReceived != null &&
                        (d.totalReceivable ?? 0) > 0)
                      (
                        label: 'Collected',
                        value:
                            '${((d.totalReceived! / d.totalReceivable!) * 100).clamp(0, 999).round()}%',
                        tone: null,
                      ),
                  ],
                ),
              // Layout keeps the panel's extra bottom padding; the paint
              // moves up by the overlap, and the list's bottom padding gives
              // the same amount back.
              Transform.translate(
                offset: Offset(0, overlap ? -_MoneyPanel.overlap : 0),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.md,
                    overlap ? 0 : Spacing.md,
                    Spacing.md,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Riding over the ink, the card needs no eyebrow — it
                      // carries its own TODAY label.
                      if (overlap)
                        const _RaisedFirst(child: _AttendanceCard())
                      else ...[
                        const SectionHeader('My attendance'),
                        const SizedBox(height: Spacing.sm),
                        const _AttendanceCard(),
                      ],
                      if (counts.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('All time'),
                        const SizedBox(height: Spacing.sm),
                        StatRail(items: counts),
                      ],
                      // Personal, not company-wide: the one block about the reader.
                      if (d.penalties != null &&
                          d.penalties!.countThisMonth > 0) ...[
                        const SizedBox(height: Spacing.md),
                        const SectionHeader('My deductions'),
                        const SizedBox(height: Spacing.sm),
                        _DeductionsCard(penalties: d.penalties!),
                      ],
                      if (d.hosting != null) ...[
                        const SizedBox(height: Spacing.md),
                        const SectionHeader('Hosting & domains'),
                        const SizedBox(height: Spacing.sm),
                        _HostingRail(stats: d.hosting!),
                        if (d.hosting!.expiringDomains.isNotEmpty) ...[
                          const SizedBox(height: Spacing.sm),
                          _ExpiringDomains(domains: d.hosting!.expiringDomains),
                        ],
                      ],
                      if (d.statutory != null || d.subscriptions != null) ...[
                        const SizedBox(height: Spacing.md),
                        const SectionHeader('Obligations & subscriptions'),
                        const SizedBox(height: Spacing.sm),
                        if (d.statutory != null)
                          StatRail(
                            items: [
                              StatRailItem(
                                label: 'Overdue',
                                value: Formatting.integer(d.statutory!.overdue),
                                emphasis: d.statutory!.overdue > 0
                                    ? status.overdue
                                    : null,
                              ),
                              StatRailItem(
                                label: 'Due soon',
                                value: Formatting.integer(d.statutory!.dueSoon),
                                emphasis: d.statutory!.dueSoon > 0
                                    ? status.attention
                                    : null,
                              ),
                              StatRailItem(
                                label: 'Active',
                                value: Formatting.integer(
                                  d.statutory!.totalActive,
                                ),
                              ),
                            ],
                          ),
                        if (d.subscriptions != null) ...[
                          const SizedBox(height: Spacing.sm),
                          StatRail(
                            items: [
                              StatRailItem(
                                label: 'Active',
                                value: Formatting.integer(
                                  d.subscriptions!.active,
                                ),
                                emphasis: status.settled,
                              ),
                              StatRailItem(
                                label: 'Pending',
                                value: Formatting.integer(
                                  d.subscriptions!.pending,
                                ),
                                emphasis: d.subscriptions!.pending > 0
                                    ? status.attention
                                    : null,
                              ),
                              StatRailItem(
                                label: 'Cancelled',
                                value: Formatting.integer(
                                  d.subscriptions!.cancelled,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      if (d.monthlyRevenue.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Last 6 months'),
                        const SizedBox(height: Spacing.sm),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: _RevenueBars(points: d.monthlyRevenue),
                          ),
                        ),
                      ],
                      if (d.recentInvoices.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Recent invoices'),
                        const SizedBox(height: Spacing.sm),
                        Card(
                          child: Column(
                            children: [
                              for (final (i, inv)
                                  in d.recentInvoices.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    inv.clientName ?? inv.documentNumber,
                                  ),
                                  // Status moves down here beside the reference, so
                                  // the trailing column is amounts only and reads as
                                  // one aligned column of money.
                                  subtitle: Row(
                                    children: [
                                      StatusChip(inv.status, dense: true),
                                      const SizedBox(width: Spacing.sm),
                                      Flexible(
                                        child: Text(
                                          [
                                            inv.documentNumber,
                                            if (inv.date != null)
                                              Formatting.date(inv.date),
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Money(inv.total),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (d.urgentObligations.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Urgent obligations'),
                        const SizedBox(height: Spacing.sm),
                        _ObligationList(items: d.urgentObligations),
                      ],
                      if (d.upcomingBills.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Upcoming bills'),
                        const SizedBox(height: Spacing.sm),
                        _BillList(items: d.upcomingBills),
                      ],
                      if (d.upcomingRenewals.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Upcoming renewals'),
                        const SizedBox(height: Spacing.sm),
                        _RenewalList(items: d.upcomingRenewals),
                      ],
                      if (d.topClients.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('Top clients'),
                        const SizedBox(height: Spacing.sm),
                        _TopClients(items: d.topClients),
                      ],
                      if (d.systemRecords != null &&
                          d.systemRecords!.systems.isNotEmpty) ...[
                        const SizedBox(height: Spacing.lg),
                        const SectionHeader('System records'),
                        const SizedBox(height: Spacing.sm),
                        _NamedTotals(
                          items: d.systemRecords!.systems,
                          total: d.systemRecords!.total,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One figure in the money panel's strip.
typedef _StripFigure = ({String label, String value, Color? tone});

/// This month's money, on ink.
///
/// The sign-in panel's composition, filled with the one figure this screen
/// is about: eyebrow pill, a display-face figure in white, and the handoff's
/// translucent stat strip beneath it for the figures that explain it. The
/// blue glow is left to the masthead above and only the green one is drawn
/// here, so the two panels read as a single surface with one light source.
///
/// Everything on it is scoped to the month — the strip must never carry an
/// all-time count, which is how the old layout ended up reading
/// "Outstanding 0.00" beside "572 overdue".
class _MoneyPanel extends StatelessWidget {
  const _MoneyPanel({
    required this.label,
    required this.amount,
    required this.strip,
  });

  final String label;
  final Object? amount;
  final List<_StripFigure> strip;

  /// How far the first paper card rides up over the panel's bottom edge.
  static const double overlap = 28;

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());

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
          Reveal(child: EyebrowPill('This month · $month')),
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

/// Minimal paired-bar chart — invoiced vs collected per month. Avoids a
/// charting dependency for one visual; swap for a real chart lib if the
/// staff app grows more analytics.
class _RevenueBars extends StatelessWidget {
  const _RevenueBars({required this.points});

  final List<MonthlyRevenuePoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final max = points
        .expand((p) => [p.invoiced, p.collected])
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _bar(p.invoiced, max, theme.colorScheme.primary),
                            const SizedBox(width: 3),
                            _bar(p.collected, max, status.settled),
                          ],
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          p.month,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend(context, theme.colorScheme.primary, 'Invoiced'),
            const SizedBox(width: Spacing.md),
            _legend(context, status.settled, 'Collected'),
          ],
        ),
      ],
    );
  }

  Widget _bar(double value, double max, Color color) => Container(
    width: 10,
    height: max <= 0 ? 2 : (value / max * 96).clamp(2, 96),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
    ),
  );

  Widget _legend(BuildContext context, Color color, String label) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// This month's report deductions, broken down by report type.
class _DeductionsCard extends StatelessWidget {
  const _DeductionsCard({required this.penalties});

  final StaffPenalties penalties;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Money(
              penalties.monthTotal,
              scale: MoneyScale.headline,
              color: status.overdue,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              '${penalties.countThisMonth} '
              '${penalties.countThisMonth == 1 ? 'deduction' : 'deductions'}'
              '${penalties.monthLabel.isEmpty ? '' : ' · ${penalties.monthLabel}'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final t in penalties.byType.where((t) => t.count > 0)) ...[
              const Divider(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${StatusColors.label(t.reportType)} · ${t.count}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Money(t.total, scale: MoneyScale.dense, showCode: false),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hosting and domain counts. Each half appears only if the role may see it —
/// the endpoint sends a `can` map rather than omitting the whole block.
class _HostingRail extends StatelessWidget {
  const _HostingRail({required this.stats});

  final HostingDomainsStats stats;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return Column(
      children: [
        StatRail(
          items: [
            if (stats.canHosting) ...[
              StatRailItem(
                label: 'Hosting',
                value: Formatting.integer(stats.hostingActive),
              ),
              StatRailItem(
                label: 'Suspended',
                value: Formatting.integer(stats.hostingSuspended),
                emphasis: stats.hostingSuspended > 0 ? status.attention : null,
              ),
            ],
            if (stats.canDomains) ...[
              StatRailItem(
                label: 'Domains',
                value: Formatting.integer(stats.domainsActive),
              ),
              StatRailItem(
                label: 'Expiring',
                value: Formatting.integer(stats.domainsExpiringSoon),
                emphasis: stats.domainsExpiringSoon > 0 ? status.overdue : null,
              ),
            ],
            if (stats.canTickets)
              StatRailItem(
                label: 'Tickets',
                value: Formatting.integer(stats.openTickets),
                emphasis: stats.openTickets > 0 ? status.pending : null,
              ),
          ],
        ),
        if (stats.registrarCredit != null) ...[
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Registrar credit',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Money(stats.registrarCredit, scale: MoneyScale.row),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Domains about to lapse, worst first. Auto-renew is called out because an
/// expiring domain with it off is the one that actually needs a human.
class _ExpiringDomains extends StatelessWidget {
  const _ExpiringDomains({required this.domains});

  final List<ExpiringDomain> domains;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Column(
        children: [
          for (final (i, d) in domains.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(d.name, style: theme.textTheme.titleSmall),
              subtitle: Text(
                [
                  if (d.clientName != null) d.clientName!,
                  if (!d.autoRenew) 'auto-renew off',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                switch (d.daysLeft) {
                  null => Formatting.date(d.expiresAt),
                  final n when n < 0 => 'Expired',
                  0 => 'Today',
                  final n => '${n}d',
                },
                style: theme.textTheme.labelMedium?.copyWith(
                  color: (d.daysLeft ?? 1) <= 0
                      ? status.overdue
                      : status.attention,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ObligationList extends StatelessWidget {
  const _ObligationList({required this.items});

  final List<UrgentObligation> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Column(
        children: [
          for (final (i, o) in items.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(o.name, style: theme.textTheme.titleSmall),
              subtitle: Text(
                [
                  if (o.cycle != null) o.cycle!,
                  Formatting.dueDescription(o.nextDueDate),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: (o.daysRemaining ?? 1) < 0
                      ? status.overdue
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Money(o.amount),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillList extends StatelessWidget {
  const _BillList({required this.items});

  final List<UpcomingBill> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (final (i, b) in items.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(
                b.name,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(Formatting.dueDescription(b.dueDate)),
              trailing: Money(b.amount),
            ),
          ],
        ],
      ),
    );
  }
}

class _RenewalList extends StatelessWidget {
  const _RenewalList({required this.items});

  final List<UpcomingRenewal> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (final (i, r) in items.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(
                r.clientName ?? '—',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (r.productName != null) r.productName!,
                  if (r.label != null) r.label!,
                  Formatting.date(r.nextBillDate),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Money(r.price),
            ),
          ],
        ],
      ),
    );
  }
}

/// Invoiced against collected per client, as a paired bar. The bar is scaled
/// to the largest client so the comparison that matters — how much of each
/// client's billing has actually come in — is the one you can see.
class _TopClients extends StatelessWidget {
  const _TopClients({required this.items});

  final List<TopClient> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final max = items.fold<double>(0, (a, c) => c.total > a ? c.total : a);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in items) ...[
              Text(
                c.name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Spacing.xs),
              _Bar(
                fraction: max <= 0 ? 0 : c.total / max,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 3),
              _Bar(
                fraction: max <= 0 ? 0 : c.paid / max,
                color: status.settled,
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Money(c.total, scale: MoneyScale.dense, showCode: false),
                  Money(
                    c.paid,
                    scale: MoneyScale.dense,
                    showCode: false,
                    color: status.settled,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
            ],
            Row(
              children: [
                _Legend(color: theme.colorScheme.primary, label: 'Invoiced'),
                const SizedBox(width: Spacing.md),
                _Legend(color: status.settled, label: 'Collected'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(
      value: fraction.clamp(0, 1),
      minHeight: 6,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      valueColor: AlwaysStoppedAnimation(color),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: Spacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _NamedTotals extends StatelessWidget {
  const _NamedTotals({required this.items, required this.total});

  final List<NamedTotal> items;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          for (final (i, n) in items.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(n.name, style: theme.textTheme.bodyMedium),
              subtitle: n.detail == null ? null : Text(n.detail!),
              trailing: Money(n.total),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Money(total),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's check-in state and the month at a glance.
///
/// Fed by /attendance/mine, which carries no permission gate — every staff
/// member checks themselves in — so this is the one card on the dashboard
/// that is always about the reader rather than the business.
///
/// It renders nothing while loading or on error: a supplementary card has no
/// business putting a retry block above the figures people came for, and the
/// full screen behind "Full report" can report its own failures.
class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(myAttendanceProvider)
        .maybeWhen(
          data: (a) => _card(context, ref, a),
          orElse: () => const SizedBox.shrink(),
        );
  }

  Widget _card(BuildContext context, WidgetRef ref, MyAttendance a) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final today = a.today;

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
                    'TODAY · ${Formatting.date(DateTime.now()).toUpperCase()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (today == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      'Not marked yet',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  StatusChip(today.chipStatus, dense: true),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Clock(
                    icon: Icons.login_rounded,
                    time: today?.checkInAt,
                    target: a.settings.checkInTime,
                    label: 'in',
                  ),
                ),
                Expanded(
                  child: _Clock(
                    icon: Icons.logout_rounded,
                    time: today?.checkOutAt,
                    target: a.settings.checkOutTime,
                    label: 'out',
                  ),
                ),
              ],
            ),
            if (a.monthRecords.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _MonthStrip(records: a.monthRecords),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm + 2,
                runSpacing: Spacing.xs,
                children: [
                  _Legend(color: status.settled, label: 'On time'),
                  _Legend(color: status.attention, label: 'Late'),
                  _Legend(color: status.pending, label: 'Excused'),
                  _Legend(color: status.overdue, label: 'Absent'),
                ],
              ),
            ],
            const Divider(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.presentDays} '
                    '${a.presentDays == 1 ? 'day' : 'days'} present'
                    '${a.monthLabel.isEmpty ? '' : ' · ${a.monthLabel}'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                // Only worth the space when the tenant actually docks pay.
                if (a.settings.penaltiesEnabled && a.deductionTotal > 0) ...[
                  Money(
                    a.deductionTotal,
                    scale: MoneyScale.dense,
                    color: status.overdue,
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
                TextButton(
                  onPressed: () => context.push('/attendance'),
                  child: const Text('Full report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of the in/out pair. Shows the recorded time, or the target it is
/// measured against while the day is still open.
class _Clock extends StatelessWidget {
  const _Clock({
    required this.icon,
    required this.label,
    this.time,
    this.target,
  });

  final IconData icon;
  final String label;
  final String? time;
  final String? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = time != null && time!.isNotEmpty;

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: marked
              ? theme.colorScheme.onSurface
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: Spacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              marked ? time! : '—',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: Type.figures,
                color: marked
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
              ),
            ),
            Text(
              target == null ? label : '$label · target $target',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The month as one mark per day, so a pattern of lateness is visible without
/// reading a table. Days with no record render as a faint tick rather than as
/// absence — the server decides what counts as absent, not the strip.
class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.records});

  final List<AttendanceDay> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final now = DateTime.now();
    final days = DateTime(now.year, now.month + 1, 0).day;
    final byDay = <int, AttendanceDay>{
      for (final r in records)
        if (r.date != null) r.date!.day: r,
    };

    Color colorFor(AttendanceDay? r) {
      if (r == null) return theme.colorScheme.outlineVariant;
      if (r.isExcused) return status.pending;
      if (r.absent) return status.overdue;
      if (r.late || r.leftEarly || r.noCheckout) return status.attention;
      return status.settled;
    }

    return Row(
      children: [
        for (var day = 1; day <= days; day++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '$day: ${byDay[day]?.summary ?? 'no record'}',
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    color: colorFor(byDay[day]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
