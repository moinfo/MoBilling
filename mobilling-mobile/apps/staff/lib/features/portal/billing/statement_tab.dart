import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';

/// Account statement: invoices vs payments with the server-computed running
/// balance, optionally windowed by a date range.
///
/// Pushed from the More tab as a screen of its own, so it carries the
/// masthead.
class StatementTab extends ConsumerStatefulWidget {
  const StatementTab({super.key});

  @override
  ConsumerState<StatementTab> createState() => _StatementTabState();
}

class _StatementTabState extends ConsumerState<StatementTab> {
  DateTimeRange? _range;

  ({String? start, String? end}) get _key {
    final fmt = DateFormat('yyyy-MM-dd');
    return (
      start: _range == null ? null : fmt.format(_range!.start),
      end: _range == null ? null : fmt.format(_range!.end),
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final statement = ref.watch(portalStatementProvider(_key));
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Account statement'),
      body: Column(
        children: [
          // The period, as one quiet chip under the masthead.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              0,
            ),
            child: Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.date_range_outlined, size: 16),
                  label: Text(
                    _range == null
                        ? 'All time'
                        : '${Formatting.date(_range!.start)} – ${Formatting.date(_range!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickRange,
                ),
                if (_range != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Show all time',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _range = null),
                  ),
              ],
            ),
          ),
          Expanded(
            child: statement.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => StateMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your statement',
                message: error is ApiException ? error.message : null,
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(portalStatementProvider(_key)),
              ),
              data: (s) => s.entries.isEmpty
                  ? StateMessage(
                      icon: Icons.receipt_outlined,
                      title: 'Nothing in this period',
                      message: 'Invoices and payments will appear here.',
                      actionLabel: _range == null ? null : 'Show all time',
                      onAction: _range == null
                          ? null
                          : () => setState(() => _range = null),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(portalStatementProvider(_key).future),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Spacing.md),
                        children: [
                          // The closing balance is what a statement is for.
                          Reveal(
                            child: _HeroFigure(
                              label: s.closingBalance < 0
                                  ? 'In credit'
                                  : 'Closing balance',
                              amount: s.closingBalance < 0
                                  ? -s.closingBalance
                                  : s.closingBalance,
                              tone: s.closingBalance > 0
                                  ? status.overdue
                                  : status.settled,
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile.money(
                                  label: 'Invoiced',
                                  amount: s.totalDebits,
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: StatTile.money(
                                  label: 'Paid',
                                  amount: s.totalCredits,
                                  emphasis: status.settled,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Spacing.lg),
                          const SectionHeader('Entries'),
                          const SizedBox(height: Spacing.sm),
                          Card(
                            child: Column(
                              children: [
                                for (final (i, entry) in s.entries.indexed) ...[
                                  if (i > 0) const Divider(height: 1),
                                  _EntryTile(entry: entry),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          Text(
                            'Amounts in ${Formatting.tenantCurrency}'
                                .toUpperCase(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Spacing.xl),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one figure the screen is about: a mono eyebrow over a display-scale
/// readout, on a card tinted 6% toward the figure's state.
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
        theme.cardTheme.color ?? theme.colorScheme.surface,
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

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final StatementEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final isPayment = entry.isPayment;

    return ListTile(
      dense: true,
      title: Text(
        entry.description,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          Formatting.date(entry.date),
          if (entry.reference != null) entry.reference!,
        ].join(' · ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sign from the client's perspective: payments reduce what's owed.
          Money(
            isPayment ? -entry.credit : entry.debit,
            showCode: false,
            color: isPayment ? status.settled : null,
          ),
          const SizedBox(height: 2),
          Text(
            'BAL ${Formatting.amount(entry.balance)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
