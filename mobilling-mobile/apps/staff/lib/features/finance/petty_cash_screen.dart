import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'expenses_screen.dart' show RecordExpenseSheet;
import 'finance_providers.dart';

/// The petty cash float: what is in the tin, where it went, and cash counts.
///
/// Two balances are shown deliberately. **Available** (committed) is the cash
/// physically left and the figure the server's insufficient-funds guard uses;
/// **verified** is the official float, which only drops once an expense is
/// approved. When they differ, expenses are awaiting approval — showing only
/// one number would let someone plan against money already spent.
class PettyCashScreen extends ConsumerWidget {
  const PettyCashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pettyCash = ref.watch(pettyCashProvider);
    final auth = ref.watch(sessionControllerProvider).session;
    final canTopUp = auth?.can(FinancePermissions.pettyCashTopup) ?? false;
    final canReconcile =
        auth?.can(FinancePermissions.pettyCashReconcile) ?? false;
    final canSpend = auth?.can(FinancePermissions.expensesCreate) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Petty cash')),
      body: CrmAsyncView(
        value: pettyCash,
        errorTitle: 'Could not load petty cash',
        onRetry: () => ref.invalidate(pettyCashProvider),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(pettyCashProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _BalanceCard(data: data),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  if (canSpend)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        label: const Text('Spend'),
                        onPressed: () => _spend(context, ref, data.accountId),
                      ),
                    ),
                  if (canSpend && canTopUp) const SizedBox(width: Spacing.sm),
                  if (canTopUp)
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('Top up'),
                        onPressed: () => _transaction(context, ref),
                      ),
                    ),
                ],
              ),
              if (canReconcile) ...[
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Count the cash'),
                  onPressed: () => _reconcile(context, ref, data),
                ),
              ],
              if (data.reconciliations.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Text('Last count',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                _ReconciliationCard(
                    reconciliation: data.reconciliations.first),
              ],
              const SizedBox(height: Spacing.lg),
              Text('History', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Spacing.sm),
              if (data.history.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  child: Center(
                    child: Text('Nothing recorded yet.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, entry) in data.history.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _HistoryTile(entry: entry),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _spend(
      BuildContext context, WidgetRef ref, String accountId) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => RecordExpenseSheet(pettyCashAccountId: accountId),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }

  Future<void> _transaction(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _TransactionSheet(),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }

  Future<void> _reconcile(
      BuildContext context, WidgetRef ref, PettyCash data) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ReconcileSheet(expected: data.committedBalance),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data});

  final PettyCash data;

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
            Text('Available now',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(
                data.committedBalance,
                scale: MoneyScale.display,
                color: data.committedBalance <= 0 ? status.overdue : null,
              ),
            ),
            // Only worth explaining the second number when it differs.
            if (data.hasPendingVouchers) ...[
              const SizedBox(height: Spacing.sm),
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: status.attention.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions_outlined,
                        size: 16, color: status.attention),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        '${data.pendingVoucherCount} expense${data.pendingVoucherCount == 1 ? '' : 's'} '
                        'awaiting approval — ${Formatting.amount(data.pendingVoucherTotal)}. '
                        'Official float is ${Formatting.currency(data.verifiedBalance)}.',
                        style: theme.textTheme.bodySmall,
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final PettyCashEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final inflow = entry.isInflow;

    return ListTile(
      dense: true,
      leading: Icon(
        inflow ? Icons.add_circle_outline : Icons.remove_circle_outline,
        size: 20,
        color: inflow ? status.settled : status.pending,
      ),
      title: Text(entry.description),
      subtitle: Text(
        [
          Formatting.date(entry.date),
          if (entry.createdByName != null) entry.createdByName!,
          if (entry.approvalStatus == 'pending') 'awaiting approval',
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Text(
        '${inflow ? '+' : '−'}${Formatting.amount(entry.amount)}',
        style: theme.textTheme.labelLarge?.copyWith(
          color: inflow ? status.settled : null,
        ),
      ),
    );
  }
}

class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({required this.reconciliation});

  final PettyCashReconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final variance = reconciliation.variance;
    final balanced = variance.abs() < 0.005;

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
                      'Counted ${Formatting.currency(reconciliation.countedAmount)}',
                      style: theme.textTheme.bodyMedium),
                ),
                Text(
                  balanced
                      ? 'Balanced'
                      : '${variance > 0 ? 'Over' : 'Short'} ${Formatting.amount(variance.abs())}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: balanced ? status.settled : status.overdue,
                  ),
                ),
              ],
            ),
            Text(
              [
                Formatting.date(reconciliation.reconciledAt),
                if (reconciliation.createdByName != null)
                  reconciliation.createdByName!,
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (reconciliation.notes != null)
              Text(reconciliation.notes!, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TransactionSheet extends ConsumerStatefulWidget {
  const _TransactionSheet();

  @override
  ConsumerState<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends ConsumerState<_TransactionSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  String _type = 'top_up';
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount < 0.01) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(financeServiceProvider).pettyCashTransaction(
            type: _type,
            amount: amount,
            transactionDate: _date,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('amount') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Petty cash movement',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'top_up', child: Text('Top up the tin')),
              DropdownMenuItem(
                  value: 'return', child: Text('Return cash to bank')),
              DropdownMenuItem(
                  value: 'adjustment_in', child: Text('Adjustment (gain)')),
              DropdownMenuItem(
                  value: 'adjustment_out', child: Text('Adjustment (loss)')),
            ],
            onChanged:
                _submitting ? null : (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
          const SizedBox(height: Spacing.md),
          InkWell(
            onTap: _submitting
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(DateTime.now().year - 2),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(Formatting.date(_date)),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _ReconcileSheet extends ConsumerStatefulWidget {
  const _ReconcileSheet({required this.expected});

  final double expected;

  @override
  ConsumerState<_ReconcileSheet> createState() => _ReconcileSheetState();
}

class _ReconcileSheetState extends ConsumerState<_ReconcileSheet> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final counted = double.tryParse(_counted.text.trim());
    if (counted == null || counted < 0) {
      setState(() => _error = 'Enter the amount you counted.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(financeServiceProvider).reconcilePettyCash(
            countedAmount: counted,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counted = double.tryParse(_counted.text.trim());
    final variance = counted == null ? null : counted - widget.expected;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Count the cash',
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          Text('Expected ${Formatting.currency(widget.expected)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          TextField(
            controller: _counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Amount counted',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
          // Live variance so a miscount is obvious before submitting.
          if (variance != null && variance.abs() >= 0.005) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              variance > 0
                  ? 'Over by ${Formatting.amount(variance)}'
                  : 'Short by ${Formatting.amount(variance.abs())}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: context.statusColors.overdue),
            ),
          ],
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText: 'Explain any difference',
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Saving…' : 'Record count'),
          ),
        ],
      ),
    );
  }
}
