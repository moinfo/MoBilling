import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'crm_providers.dart';
import 'crm_ui.dart';

/// Debt collection: what is owed, how old it is, and who to ring today.
///
/// The backend exposes a single dashboard endpoint — there is no collection
/// list or log-outcome route. Acting on a row therefore means scheduling a
/// *follow-up*, which is the tap-through offered on each invoice.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

enum _View { today, overdue, upcoming }

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  _View _view = _View.today;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(collectionDashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Collection')),
      body: CrmAsyncView(
        value: dashboard,
        errorTitle: 'Could not load collection',
        onRetry: () => ref.invalidate(collectionDashboardProvider),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(collectionDashboardProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _SummaryGrid(summary: data.summary),
              const SizedBox(height: Spacing.md),
              _AgeingBar(aging: data.aging),
              const SizedBox(height: Spacing.lg),
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                      value: _View.today,
                      label: Text('Today (${data.todayDue.length})')),
                  ButtonSegment(
                      value: _View.overdue,
                      label: Text('Overdue (${data.overdue.length})')),
                  ButtonSegment(
                      value: _View.upcoming,
                      label: Text('Soon (${data.upcoming.length})')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: Spacing.md),
              ..._buildList(context, data),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildList(BuildContext context, CollectionDashboard data) {
    final invoices = switch (_view) {
      _View.today => data.todayDue,
      _View.overdue => data.overdue,
      _View.upcoming => data.upcoming,
    };

    if (invoices.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
          child: Center(
            child: Text(
              switch (_view) {
                _View.today => 'Nothing due today.',
                _View.overdue => 'Nothing overdue — well collected.',
                _View.upcoming => 'Nothing due soon.',
              },
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ];
    }

    return [
      for (final invoice in invoices)
        _InvoiceCard(
          invoice: invoice,
          // The dashboard carries phones separately, keyed by document.
          phone: data.phoneByDocument[invoice.id],
        ),
    ];
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.sm,
      crossAxisSpacing: Spacing.sm,
      childAspectRatio: 1.9,
      children: [
        StatTile.money(
          label: 'Outstanding',
          amount: summary.totalOutstanding,
          emphasis: summary.totalOutstanding > 0 ? status.overdue : null,
          icon: Icons.account_balance_wallet_outlined,
        ),
        StatTile.money(
          label: 'Collected today',
          amount: summary.todayCollected,
          emphasis: status.settled,
          icon: Icons.today_outlined,
        ),
        StatTile.money(
          label: 'Overdue balance',
          amount: summary.overdueBalance,
          emphasis: summary.overdueBalance > 0 ? status.attention : null,
          icon: Icons.warning_amber_rounded,
        ),
        StatTile.money(
          label: 'Month collected',
          amount: summary.monthCollected,
          icon: Icons.calendar_month_outlined,
        ),
      ],
    );
  }
}

/// Ageing buckets as proportional segments — the shape of the debt matters
/// more than the exact figures when you are deciding who to chase.
class _AgeingBar extends StatelessWidget {
  const _AgeingBar({required this.aging});

  final CollectionAging aging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    final buckets = <(String, double, Color)>[
      ('Current', aging.current, status.settled),
      ('1–30', aging.days1To30, status.pending),
      ('31–60', aging.days31To60, status.attention),
      ('61–90', aging.days61To90, status.overdue),
      ('90+', aging.over90, theme.colorScheme.error),
    ];
    final total = buckets.fold<double>(0, (sum, b) => sum + b.$2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ageing', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (total <= 0)
              Text('Nothing outstanding.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Row(
                  children: [
                    for (final (_, amount, color) in buckets)
                      if (amount > 0)
                        Expanded(
                          flex: (amount / total * 1000).round().clamp(1, 1000),
                          child: Container(height: 10, color: color),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              for (final (label, amount, color) in buckets)
                if (amount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle)),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                            child: Text(label,
                                style: theme.textTheme.bodySmall)),
                        Text(Formatting.amount(amount),
                            style: theme.textTheme.bodySmall),
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

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, this.phone});

  final CollectionInvoice invoice;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final overdue = (invoice.daysOverdue ?? 0) > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.clientName ?? invoice.documentNumber,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      invoice.documentNumber,
                      if (overdue)
                        '${invoice.daysOverdue}d overdue'
                      else if (invoice.daysUntilDue != null)
                        'due in ${invoice.daysUntilDue}d',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: overdue
                            ? status.overdue
                            : theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(invoice.balanceDue),
                StatusChip(invoice.status, dense: true),
              ],
            ),
            ContactRow(phone: phone, compact: true),
          ],
        ),
      ),
    );
  }
}
