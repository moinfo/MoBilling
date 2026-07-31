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
        final moneyTiles = <Widget>[
          if (d.totalReceivable != null)
            StatTile(
                label: 'Invoiced (this month)',
                value: Formatting.amount(d.totalReceivable)),
          if (d.totalReceived != null)
            StatTile(
                label: 'Collected',
                value: Formatting.amount(d.totalReceived),
                emphasis: status.settled),
          if (d.outstanding != null)
            StatTile(
                label: 'Outstanding',
                value: Formatting.amount(d.outstanding),
                emphasis: (d.outstanding ?? 0) > 0 ? status.overdue : null),
          if (d.overdueInvoices != null)
            StatTile(
                label: 'Overdue invoices',
                value: '${d.overdueInvoices}',
                emphasis:
                    (d.overdueInvoices ?? 0) > 0 ? status.attention : null),
          if (d.totalClients != null)
            StatTile(label: 'Clients', value: '${d.totalClients}'),
          if (d.smsBalance != null)
            StatTile(label: 'SMS balance', value: '${d.smsBalance}'),
        ];

        return RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (moneyTiles.isNotEmpty)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Spacing.sm,
                  crossAxisSpacing: Spacing.sm,
                  childAspectRatio: 1.9,
                  children: moneyTiles,
                )
              else
                const StateMessage(
                  icon: Icons.lock_outline,
                  title: 'No dashboard metrics available',
                  message:
                      'Your role does not include any dashboard permissions.',
                ),
              if (d.monthlyRevenue.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Text('Last 6 months', style: theme.textTheme.titleSmall),
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
                Text('Recent invoices', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (final (i, inv) in d.recentInvoices.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(inv.clientName ?? inv.documentNumber),
                          subtitle: Text([
                            inv.documentNumber,
                            if (inv.date != null) Formatting.date(inv.date),
                          ].join(' · ')),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Formatting.currency(inv.total),
                                  style: theme.textTheme.labelLarge),
                              StatusChip(inv.status, dense: true),
                            ],
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
        );
      },
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
