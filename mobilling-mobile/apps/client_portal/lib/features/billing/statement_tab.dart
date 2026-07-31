import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Account statement: invoices vs payments with the server-computed running
/// balance, optionally windowed by a date range.
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
    final statement = ref.watch(statementProvider(_key));
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _range == null
                        ? 'All time'
                        : '${Formatting.date(_range!.start)} – ${Formatting.date(_range!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40)),
                ),
              ),
              if (_range != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear range',
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
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(statementProvider(_key)),
            ),
            data: (s) => s.entries.isEmpty
                ? const StateMessage(
                    icon: Icons.receipt_outlined,
                    title: 'Nothing in this period',
                    message: 'Invoices and payments will appear here.',
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(statementProvider(_key).future),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Spacing.md),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: StatTile(
                                label: 'Invoiced',
                                value: Formatting.amount(s.totalDebits),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: StatTile(
                                label: 'Paid',
                                value: Formatting.amount(s.totalCredits),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: StatTile(
                                label: 'Balance',
                                value: Formatting.amount(s.closingBalance),
                                emphasis: s.closingBalance > 0
                                    ? context.statusColors.overdue
                                    : context.statusColors.settled,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Spacing.md),
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
                          'Amounts in ${Formatting.tenantCurrency}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: Spacing.xl),
                      ],
                    ),
                  ),
          ),
        ),
      ],
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
      leading: Icon(
        isPayment ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
        size: 20,
        color: isPayment ? status.settled : status.pending,
      ),
      title: Text(entry.description),
      subtitle: Text([
        Formatting.date(entry.date),
        if (entry.reference != null) entry.reference!,
      ].join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            // Sign from the client's perspective: payments reduce what's owed.
            isPayment
                ? '−${Formatting.amount(entry.credit)}'
                : '+${Formatting.amount(entry.debit)}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: isPayment ? status.settled : null,
            ),
          ),
          Text(
            'bal ${Formatting.amount(entry.balance)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
