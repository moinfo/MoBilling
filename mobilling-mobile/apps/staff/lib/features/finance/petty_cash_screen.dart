import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmSheet, showCrmSheet;
import 'expenses_screen.dart' show RecordExpenseSheet, pickAndUploadVoucher;
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
    final canRead = auth?.can(FinancePermissions.pettyCashRead) ?? false;
    final canDelete = auth?.can(FinancePermissions.pettyCashDelete) ?? false;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Expenses', title: 'Petty cash'),
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
              // The one figure this screen is about.
              Reveal(child: _BalanceCard(data: data)),
              if (canSpend) ...[
                const SizedBox(height: Spacing.md),
                Reveal(
                  delay: const Duration(milliseconds: 80),
                  child: PrimaryButton(
                    label: 'Record a spend',
                    icon: Icons.remove_circle_outline,
                    onPressed: () => _spend(context, ref, data.accountId),
                  ),
                ),
              ],
              if (canTopUp || canReconcile) ...[
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    if (canTopUp)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Top up'),
                          onPressed: () => _transaction(context, ref),
                        ),
                      ),
                    if (canTopUp && canReconcile)
                      const SizedBox(width: Spacing.sm),
                    if (canReconcile)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.fact_check_outlined, size: 18),
                          label: const Text('Count the cash'),
                          onPressed: () => _reconcile(context, ref, data),
                        ),
                      ),
                  ],
                ),
              ],
              if (data.reconciliations.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                const SectionHeader('Last count'),
                const SizedBox(height: Spacing.sm),
                _ReconciliationCard(reconciliation: data.reconciliations.first),
              ],
              const SizedBox(height: Spacing.lg),
              const SectionHeader('History'),
              const SizedBox(height: Spacing.sm),
              if (data.history.isEmpty)
                StateMessage(
                  icon: Icons.savings_outlined,
                  title: 'Nothing recorded yet',
                  message: 'Top-ups, returns and spends will appear here.',
                  actionLabel: canSpend ? 'Record a spend' : null,
                  onAction: canSpend
                      ? () => _spend(context, ref, data.accountId)
                      : null,
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, entry) in data.history.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _HistoryTile(
                          entry: entry,
                          canRead: canRead,
                          canUpload: canTopUp,
                          canDelete: canDelete,
                        ),
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
    BuildContext context,
    WidgetRef ref,
    String accountId,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => RecordExpenseSheet(pettyCashAccountId: accountId),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }

  Future<void> _transaction(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const _TransactionSheet(),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }

  Future<void> _reconcile(
    BuildContext context,
    WidgetRef ref,
    PettyCash data,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ReconcileSheet(expected: data.committedBalance),
    );
    if (saved == true) ref.invalidate(pettyCashProvider);
  }
}

/// The hero: what is available now, at display scale on paper. When vouchers
/// are awaiting approval the two figures that explain the gap sit beneath a
/// rule, as figures rather than as a sentence.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data});

  final PettyCash data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final eyebrow = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'Available now',
                if (data.accountName.isNotEmpty) data.accountName,
              ].join(' · ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: eyebrow,
            ),
            const SizedBox(height: Spacing.sm),
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
              const Divider(height: Spacing.lg + Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label:
                          'Awaiting approval · ${Formatting.integer(data.pendingVoucherCount)}',
                      amount: data.pendingVoucherTotal,
                      tone: status.attention,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: _Figure(
                      label: 'Official float',
                      amount: data.verifiedBalance,
                    ),
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

/// A labelled row-scale figure inside a card.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.amount, this.tone});

  final String label;
  final Object? amount;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Money(amount, color: tone, showCode: false),
        ),
      ],
    );
  }
}

/// One ledger line. Direction is said by the mono kind label and, for money
/// in, by the figure's green — no signs, no coloured icons.
///
/// Tapping opens what can be done to it: the voucher for that movement, and
/// — for a hand-entered top-up or return — removing it.
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({
    required this.entry,
    required this.canRead,
    required this.canUpload,
    required this.canDelete,
  });

  final PettyCashEntry entry;
  final bool canRead;
  final bool canUpload;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final inflow = entry.isInflow;
    final pending = entry.approvalStatus == 'pending';

    return ListTile(
      dense: true,
      onTap: () => _showActions(context, ref),
      title: Text(
        entry.description,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (pending) ...[
            const StatusChip('pending', dense: true),
            const SizedBox(width: Spacing.sm),
          ],
          Flexible(
            child: Text(
              [
                entry.kind.replaceAll('_', ' '),
                Formatting.date(entry.date),
                if (entry.createdByName != null) entry.createdByName!,
                if (entry.voucherAttached) 'signed',
              ].join(' · ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      trailing: Money(entry.amount, color: inflow ? status.settled : null),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    // An expense's voucher belongs to the expense, not to this ledger line —
    // the API generates it from the Expenses side.
    final vouchersHere = !entry.isExpense;

    final choice = await showCrmSheet<String>(
      context: context,
      builder: (context) => CrmSheet(
        eyebrow: entry.kind.replaceAll('_', ' '),
        title: entry.description,
        children: [
          Card(
            child: Column(
              children: [
                if (vouchersHere && canRead)
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('Blank voucher'),
                    subtitle: const Text(
                      'Print it and have both parties sign.',
                    ),
                    onTap: () => Navigator.pop(context, 'voucher'),
                  ),
                if (entry.voucherAttachmentUrl != null)
                  ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('View signed voucher'),
                    onTap: () => Navigator.pop(context, 'signed'),
                  ),
                if (vouchersHere && canUpload)
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: Text(
                      entry.voucherAttached
                          ? 'Replace signed voucher'
                          : 'Upload signed voucher',
                    ),
                    subtitle: const Text('Photograph the signed slip.'),
                    onTap: () => Navigator.pop(context, 'upload'),
                  ),
                if (entry.isExpense)
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Handled on the Expenses screen'),
                    subtitle: Text(
                      'This line is an expense; its voucher lives with it.',
                    ),
                  ),
                if (canDelete && entry.isDeletable)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete this movement',
                      style: TextStyle(color: scheme.error),
                    ),
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'voucher':
        await sharePdf(
          context,
          fetch: () =>
              ref.read(financeServiceProvider).pettyCashVoucherPdf(entry.id),
          filename: 'voucher-${entry.id.substring(0, 8)}.pdf',
        );
      case 'signed':
        await launchUrl(
          Uri.parse(entry.voucherAttachmentUrl!),
          mode: LaunchMode.externalApplication,
        );
      case 'upload':
        final done = await pickAndUploadVoucher(
          context,
          upload: (path, onProgress) => ref
              .read(financeServiceProvider)
              .uploadPettyCashVoucher(
                entry.id,
                filePath: path,
                onProgress: onProgress,
              ),
        );
        if (done) ref.invalidate(pettyCashProvider);
      case 'delete':
        await _delete(context, ref);
    }
  }

  /// Removing a movement moves money in the books, so the amount is named on
  /// the way out and the button says what it does.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kind = entry.kind.replaceAll('_', ' ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete this $kind',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Text(
          'Delete the $kind of ${Formatting.currency(entry.amount)} recorded '
          '${Formatting.date(entry.date)}? The balance moves with it, the '
          'signed voucher is destroyed, and this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref
          .read(financeServiceProvider)
          .deletePettyCashTransaction(entry.id);
      ref.invalidate(pettyCashProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Transaction deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The most recent cash count: what was counted, and whether it balanced.
class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({required this.reconciliation});

  final PettyCashReconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COUNTED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Money(
                        reconciliation.countedAmount,
                        scale: MoneyScale.headline,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ToneTag(
                      balanced
                          ? 'Balanced'
                          : variance > 0
                          ? 'Over'
                          : 'Short',
                      color: balanced ? status.settled : status.overdue,
                    ),
                    if (!balanced) ...[
                      const SizedBox(height: Spacing.xs),
                      Money(
                        variance.abs(),
                        scale: MoneyScale.dense,
                        color: status.overdue,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              [
                Formatting.date(reconciliation.reconciledAt),
                if (reconciliation.createdByName != null)
                  reconciliation.createdByName!,
              ].join(' · ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (reconciliation.notes != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(reconciliation.notes!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// A [StatusChip]-shaped tag for a state the status enum has no word for
/// (balanced / over / short).
class _ToneTag extends StatelessWidget {
  const _ToneTag(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      text.toUpperCase(),
      style: Type.mono(9.5, tracking: 0.08, color: color),
    ),
  );
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
      await ref
          .read(financeServiceProvider)
          .pettyCashTransaction(
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PETTY CASH',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Petty cash movement',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Type'),
            const SizedBox(height: Spacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: const [
                DropdownMenuItem(
                  value: 'top_up',
                  child: Text('Top up the tin'),
                ),
                DropdownMenuItem(
                  value: 'return',
                  child: Text('Return cash to bank'),
                ),
                // Adjustments are only written by a reconciliation — the API
                // rejects them here.
              ],
              onChanged: _submitting ? null : (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Amount'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Date'),
            const SizedBox(height: Spacing.sm),
            _DateField(date: _date, onTap: _submitting ? null : _pickDate),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Notes (optional)'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Where the cash came from or went',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting
                  ? 'Saving…'
                  : _type == 'top_up'
                  ? 'Record top-up'
                  : 'Record return',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
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

  /// accepted = book the difference as an adjustment; investigating = flag
  /// it and leave the ledger untouched.
  String _resolution = 'accepted';
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
      await ref
          .read(financeServiceProvider)
          .reconcilePettyCash(
            countedBalance: counted,
            resolution: _resolution,
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
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final counted = double.tryParse(_counted.text.trim());
    final variance = counted == null ? null : counted - widget.expected;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PETTY CASH',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Count the cash',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'EXPECTED',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Money(widget.expected, scale: MoneyScale.dense),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Amount counted'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _counted,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
            // Live variance so a miscount is obvious before submitting.
            if (variance != null && variance.abs() >= 0.005) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    variance > 0 ? 'OVER BY' : 'SHORT BY',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: status.overdue,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Money(
                    variance.abs(),
                    scale: MoneyScale.dense,
                    color: status.overdue,
                  ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.md),
            // What to do with a difference — the API requires a decision.
            const FieldLabel('If it does not balance'),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'accepted',
                  icon: Icon(Icons.check, size: 16),
                  label: Text('Book difference'),
                ),
                ButtonSegment(
                  value: 'investigating',
                  icon: Icon(Icons.search, size: 16),
                  label: Text('Investigate'),
                ),
              ],
              selected: {_resolution},
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() => _resolution = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              _resolution == 'accepted'
                  ? 'The ledger is adjusted to match the count.'
                  : 'The ledger is left as is and the difference is flagged.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Notes'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Explain any difference',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Record count',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private building blocks (candidates for mobilling_ui)
// ---------------------------------------------------------------------------

/// A date shown in a field, tapping opens the picker.
class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(Radii.md),
    onTap: onTap,
    child: InputDecorator(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
      ),
      child: Text(
        Formatting.date(date),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}
