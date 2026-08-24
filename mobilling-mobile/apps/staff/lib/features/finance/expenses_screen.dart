import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_money/payment_method_field.dart';
import '../common/paged_list.dart';
import 'finance_providers.dart';

/// Expenses, with the petty-cash approval flow.
///
/// A petty-cash expense sits `pending` until an administrator approves it —
/// only then does it leave the verified float. Approvers get inline
/// approve/reject on each pending row; a rejection requires a reason.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  void _reload() {
    _listKey.currentState?.reload();
    // Approving an expense changes the petty-cash verified balance.
    ref.invalidate(pettyCashProvider);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate = auth?.can(FinancePermissions.expensesCreate) ?? false;
    final canApprove = auth?.can(FinancePermissions.expensesApprove) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Expenses',
        title: 'Expenses',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Record expense',
                onPressed: () => _record(context),
              ),
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search description',
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          // Approval state, as a quiet row of chips under the masthead.
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              itemCount: _filters.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return ChoiceChip(
                  label: Text(label.toUpperCase()),
                  selected: _status == value,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _status = value);
                    _listKey.currentState?.reload();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.xl,
              ),
              fetch: (page) => ref
                  .read(financeServiceProvider)
                  .expenses(
                    approvalStatus: _status,
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, expense) => _ExpenseCard(
                expense: expense,
                canApprove: canApprove,
                onChanged: _reload,
              ),
              emptyIcon: Icons.money_off_outlined,
              emptyTitle: 'No expenses found',
              emptyMessage: canCreate
                  ? 'Record one with the + button above.'
                  : 'Nothing matches this search or filter.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _record(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const RecordExpenseSheet(),
    );
    if (saved == true) _reload();
  }
}

/// One expense: description and amount on the first line, the chip and the
/// mono metadata line under it, and the approval decision — when there is
/// one to make — as a full row of its own at the bottom.
class _ExpenseCard extends ConsumerWidget {
  const _ExpenseCard({
    required this.expense,
    required this.canApprove,
    required this.onChanged,
  });

  final Expense expense;
  final bool canApprove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

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
                  child: Text(
                    expense.description,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Money(expense.amount),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                StatusChip(
                  expense.approvalStatus == 'approved'
                      ? 'approved'
                      : expense.approvalStatus == 'rejected'
                      ? 'rejected'
                      : 'pending',
                  dense: true,
                ),
                if (expense.isPettyCash && !expense.hasVoucher) ...[
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'VOUCHER PENDING',
                    style: meta?.copyWith(color: status.attention),
                  ),
                ],
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Text(
                    [
                      if (expense.categoryPath.isNotEmpty) expense.categoryPath,
                      Formatting.date(expense.expenseDate),
                      if (expense.paymentMethod != null) expense.paymentMethod!,
                      if (expense.isPettyCash) 'petty cash',
                    ].join(' · ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                ),
              ],
            ),
            if (expense.rejectionReason != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Rejected: ${expense.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (expense.approvedByName != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Approved by ${expense.approvedByName}'
                '${expense.approvedAt == null ? '' : ' · ${Formatting.date(expense.approvedAt)}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canApprove && expense.isPending) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(context, ref),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _approve(context, ref),
                      child: const Text('Approve'),
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

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(financeServiceProvider).approveExpense(expense.id);
      onChanged();
      messenger.showSnackBar(
        const SnackBar(content: Text('Expense approved.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Reject expense',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('Reason'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Why it is being rejected',
                helperText: 'Shown to whoever submitted it',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject expense'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;

    try {
      await ref
          .read(financeServiceProvider)
          .rejectExpense(expense.id, reason: reason);
      onChanged();
      messenger.showSnackBar(
        const SnackBar(content: Text('Expense rejected.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Record an expense. Exposed so the petty-cash screen can reuse it with the
/// account pre-selected.
class RecordExpenseSheet extends ConsumerStatefulWidget {
  const RecordExpenseSheet({super.key, this.pettyCashAccountId});

  /// When set, the expense is charged to the petty-cash float and the voucher
  /// signatory fields appear.
  final String? pettyCashAccountId;

  @override
  ConsumerState<RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

class _RecordExpenseSheetState extends ConsumerState<RecordExpenseSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _givenBy = TextEditingController();
  final _receivedBy = TextEditingController();

  String? _subCategoryId;
  String? _method;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  bool get _isPettyCash => widget.pettyCashAccountId != null;

  @override
  void dispose() {
    for (final c in [
      _description,
      _amount,
      _reference,
      _notes,
      _givenBy,
      _receivedBy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_description.text.trim().isEmpty || amount == null || amount < 0.01) {
      setState(() => _error = 'A description and a valid amount are required.');
      return;
    }
    if (_method == null) {
      setState(() => _error = 'Choose a payment method.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(financeServiceProvider)
          .createExpense(
            description: _description.text.trim(),
            amount: amount,
            expenseDate: _date,
            paymentMethod: _method!,
            subCategoryId: _subCategoryId,
            pettyCashAccountId: widget.pettyCashAccountId,
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            givenByName: _givenBy.text.trim().isEmpty
                ? null
                : _givenBy.text.trim(),
            receivedByName: _receivedBy.text.trim().isEmpty
                ? null
                : _receivedBy.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('amount') ?? e.errorFor('description') ?? e.message,
      );
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
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ??
        const <ExpenseCategory>[];

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isPettyCash ? 'PETTY CASH' : 'EXPENSES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              _isPettyCash ? 'Petty cash expense' : 'Record expense',
              style: Type.display(22, color: scheme.onSurface),
            ),
            if (_isPettyCash) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                'Needs administrator approval before it leaves the float.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            const FieldLabel('Description'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _description,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What the money was spent on',
              ),
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
            // Expenses attach to a SUB-category, so the picker is flattened
            // with the parent shown as a prefix.
            const FieldLabel('Category'),
            const SizedBox(height: Spacing.sm),
            DropdownButtonFormField<String?>(
              initialValue: _subCategoryId,
              isExpanded: true,
              decoration: const InputDecoration(hintText: 'Choose a category'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Uncategorised'),
                ),
                for (final category in categories)
                  for (final sub in category.subCategories)
                    DropdownMenuItem(
                      value: sub.id,
                      child: Text(
                        '${category.name} › ${sub.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _subCategoryId = v),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Payment method'),
            const SizedBox(height: Spacing.sm),
            PaymentMethodField(
              value: _method,
              enabled: !_submitting,
              onChanged: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Date'),
            const SizedBox(height: Spacing.sm),
            _DateField(date: _date, onTap: _submitting ? null : _pickDate),
            if (_isPettyCash) ...[
              const SizedBox(height: Spacing.md),
              const FieldLabel('Cash given by'),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _givenBy,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Name on the voucher',
                ),
              ),
              const SizedBox(height: Spacing.md),
              const FieldLabel('Cash received by'),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _receivedBy,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Name on the voucher',
                ),
              ),
            ],
            const SizedBox(height: Spacing.md),
            const FieldLabel('Reference (optional)'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _reference,
              enabled: !_submitting,
              decoration: const InputDecoration(
                hintText: 'Receipt or invoice number',
              ),
            ),
            const SizedBox(height: Spacing.md),
            const FieldLabel('Notes (optional)'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Anything an approver should know',
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting ? 'Saving…' : 'Save expense',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Receipt attachments can be added from the web app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
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
