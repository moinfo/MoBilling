import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Staff dashboard: this month's money, counts, recent invoices.
///
/// Null metrics mean the backend withheld them (per-field dashboard.*
/// permissions) — those cards are simply not rendered.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final theme = Theme.of(context);
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
              emphasis:
                  (d.overdueInvoices ?? 0) > 0 ? status.attention : null,
            ),
          if (d.totalClients != null)
            StatRailItem(label: 'Clients', value: Formatting.integer(d.totalClients)),
          if (d.smsBalance != null)
            StatRailItem(label: 'SMS', value: Formatting.integer(d.smsBalance)),
        ];

        if (money.isEmpty && counts.isEmpty) {
          return const StateMessage(
            icon: Icons.lock_outline,
            title: 'No dashboard metrics available',
            message: 'Your role does not include any dashboard permissions.',
          );
        }

        final hero = money.isEmpty ? null : money.first;
        final rest = money.skip(1).toList();

        return RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (money.isNotEmpty) ...[
                const SectionHeader('This month'),
                const SizedBox(height: Spacing.sm),
              ],
              if (hero != null) ...[
                _HeroFigure(
                  label: hero.label,
                  amount: hero.amount,
                  tone: hero.tone ?? theme.colorScheme.onSurface,
                ),
                const SizedBox(height: Spacing.sm),
              ],
              if (rest.isNotEmpty) ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Spacing.sm,
                  crossAxisSpacing: Spacing.sm,
                  childAspectRatio: 1.9,
                  children: [
                    for (final m in rest)
                      StatTile.money(
                        label: m.label,
                        amount: m.amount,
                        emphasis: m.tone,
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
              ],
              if (counts.isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                const SectionHeader('All time'),
                const SizedBox(height: Spacing.sm),
                StatRail(items: counts),
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
                      for (final (i, inv) in d.recentInvoices.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(inv.clientName ?? inv.documentNumber),
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
              const SizedBox(height: Spacing.xl),
            ],
          ),
        );
      },
    );
  }
}

/// The single figure a dashboard leads with.
///
/// Same shape as the client portal's balance card on purpose: staff and
/// clients are looking at two sides of the same money, and the app should not
/// invent a second visual language for the second audience.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({
    required this.label,
    required this.amount,
    required this.tone,
  });

  final String label;
  final Object? amount;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              label.toUpperCase(),
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
              child: Money(amount, scale: MoneyScale.display, color: tone),
            ),
          ],
        ),
      ),
    );
  }
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.xs),
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
                        Text(p.month,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
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
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: Spacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}
