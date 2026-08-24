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
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Collection'),
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
              // The hero: the one figure this screen is about.
              Reveal(child: _OutstandingCard(summary: data.summary)),
              const SizedBox(height: Spacing.sm),
              Reveal(
                delay: const Duration(milliseconds: 80),
                child: _CollectedTiles(summary: data.summary),
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Ageing'),
              const SizedBox(height: Spacing.sm),
              _AgeingBar(aging: data.aging),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Who to ring'),
              const SizedBox(height: Spacing.sm),
              SegmentedButton<_View>(
                segments: [
                  ButtonSegment(
                    value: _View.today,
                    label: Text(
                      'Today (${Formatting.integer(data.todayDue.length)})',
                    ),
                  ),
                  ButtonSegment(
                    value: _View.overdue,
                    label: Text(
                      'Overdue (${Formatting.integer(data.overdue.length)})',
                    ),
                  ),
                  ButtonSegment(
                    value: _View.upcoming,
                    label: Text(
                      'Soon (${Formatting.integer(data.upcoming.length)})',
                    ),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: Spacing.sm),
              _buildList(context, data),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, CollectionDashboard data) {
    final invoices = switch (_view) {
      _View.today => data.todayDue,
      _View.overdue => data.overdue,
      _View.upcoming => data.upcoming,
    };

    if (invoices.isEmpty) {
      return StateMessage(
        icon: Icons.check_circle_outline,
        title: switch (_view) {
          _View.today => 'Nothing due today',
          _View.overdue => 'Nothing overdue',
          _View.upcoming => 'Nothing due soon',
        },
        message: switch (_view) {
          _View.today => 'Invoices falling due today will be listed here.',
          _View.overdue => 'Well collected — every invoice is within terms.',
          _View.upcoming => 'Invoices due in the next few days appear here.',
        },
      );
    }

    return CrmCardList(
      children: [
        for (final invoice in invoices)
          _InvoiceTile(
            invoice: invoice,
            // The dashboard carries phones separately, keyed by document.
            phone: data.phoneByDocument[invoice.id],
          ),
      ],
    );
  }
}

/// Total outstanding in the display scale, with the overdue share under it
/// — the two figures a collector reads before deciding who to chase.
class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Outstanding'.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(
                summary.totalOutstanding,
                scale: MoneyScale.display,
                color: summary.totalOutstanding > 0 ? status.overdue : null,
              ),
            ),
            const Divider(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overdue balance',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Money(
                  summary.overdueBalance,
                  scale: MoneyScale.dense,
                  color: summary.overdueBalance > 0 ? status.attention : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What has come in: today and this month.
class _CollectedTiles extends StatelessWidget {
  const _CollectedTiles({required this.summary});

  final CollectionSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: StatTile.money(
            label: 'Collected today',
            amount: summary.todayCollected,
            emphasis: status.settled,
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: StatTile.money(
            label: 'Collected this month',
            amount: summary.monthCollected,
          ),
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
    final scheme = theme.colorScheme;
    final ramp = context.statusColors.agingRamp;

    final buckets = <(String, double, Color)>[
      ('Current', aging.current, ramp[0]),
      ('1–30 days', aging.days1To30, ramp[1]),
      ('31–60 days', aging.days31To60, ramp[2]),
      ('61–90 days', aging.days61To90, ramp[3]),
      ('Over 90 days', aging.over90, ramp[4]),
    ];
    final total = buckets.fold<double>(0, (sum, b) => sum + b.$2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total <= 0)
              Text(
                'Nothing outstanding.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: Row(
                  children: [
                    for (final (_, amount, color) in buckets)
                      if (amount > 0)
                        Expanded(
                          flex: (amount / total * 1000).round().clamp(1, 1000),
                          child: Container(height: 8, color: color),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              for (final (i, (label, amount, color)) in buckets.indexed)
                if (amount > 0) ...[
                  if (i > 0) const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyMedium),
                      ),
                      Money(amount, scale: MoneyScale.dense, showCode: false),
                    ],
                  ),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

/// One invoice to chase: who, the reference and how late, the balance, and
/// the number one tap away. The call button keeps a fixed slot so the money
/// column stays aligned whether or not a phone is on file.
class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, this.phone});

  final CollectionInvoice invoice;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final overdue = (invoice.daysOverdue ?? 0) > 0;

    final meta = [
      invoice.documentNumber,
      if (overdue)
        '${invoice.daysOverdue}d overdue'
      else if (invoice.daysUntilDue != null)
        'due in ${invoice.daysUntilDue}d',
    ].join(' · ');

    return ListTile(
      title: Text(
        invoice.clientName ?? invoice.documentNumber,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: CrmStatusLine(
          status: invoice.status,
          meta: meta,
          tone: overdue ? status.overdue : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Money(invoice.balanceDue),
          const SizedBox(width: Spacing.xs),
          SizedBox(
            width: 40,
            child: ContactRow(phone: phone, compact: true),
          ),
        ],
      ),
    );
  }
}
