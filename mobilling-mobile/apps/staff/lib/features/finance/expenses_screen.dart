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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
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
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: !canCreate
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _record(context),
              icon: const Icon(Icons.add),
              label: const Text('Record'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search description',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              itemCount: _filters.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return FilterChip(
                  label: Text(label),
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
              fetch: (page) => ref.read(financeServiceProvider).expenses(
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
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => const RecordExpenseSheet(),
    );
    if (saved == true) _reload();
  }
}

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
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(expense.description,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Spacing.sm),
                Text(Formatting.currency(expense.amount),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (expense.categoryPath.isNotEmpty) expense.categoryPath,
                Formatting.date(expense.expenseDate),
                if (expense.paymentMethod != null) expense.paymentMethod!,
                if (expense.isPettyCash) 'petty cash',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                StatusChip(
                    expense.approvalStatus == 'approved'
                        ? 'active'
                        : expense.approvalStatus == 'rejected'
                            ? 'rejected'
                            : 'pending',
                    dense: true),
                if (expense.isPettyCash && !expense.hasVoucher) ...[
                  const SizedBox(width: Spacing.xs),
                  Text('voucher pending',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: status.attention)),
                ],
                const Spacer(),
                if (canApprove && expense.isPending) ...[
                  TextButton(
                    onPressed: () => _reject(context, ref),
                    child: Text('Reject',
                        style: TextStyle(color: theme.colorScheme.error)),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _approve(context, ref),
                    child: const Text('Approve'),
                  ),
                ],
              ],
            ),
            if (expense.rejectionReason != null) ...[
              const SizedBox(height: Spacing.xs),
              Text('Rejected: ${expense.rejectionReason}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            if (expense.approvedByName != null) ...[
              const SizedBox(height: 2),
              Text(
                'Approved by ${expense.approvedByName}'
                '${expense.approvedAt == null ? '' : ' · ${Formatting.date(expense.approvedAt)}'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
      messenger
          .showSnackBar(const SnackBar(content: Text('Expense approved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject expense'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            helperText: 'Shown to whoever submitted it',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
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
      messenger
          .showSnackBar(const SnackBar(content: Text('Expense rejected.')));
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
  ConsumerState<RecordExpenseSheet> createState() =>
      _RecordExpenseSheetState();
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
      _receivedBy
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
      await ref.read(financeServiceProvider).createExpense(
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
            givenByName:
                _givenBy.text.trim().isEmpty ? null : _givenBy.text.trim(),
            receivedByName: _receivedBy.text.trim().isEmpty
                ? null
                : _receivedBy.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('amount') ??
          e.errorFor('description') ??
          e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ??
            const <ExpenseCategory>[];

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isPettyCash ? 'Petty cash expense' : 'Record expense',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            if (_isPettyCash)
              Text('Needs administrator approval',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            const SizedBox(height: Spacing.md),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.sm),
            ],
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
            const SizedBox(height: Spacing.md),
            // Expenses attach to a SUB-category, so the picker is flattened
            // with the parent shown as a prefix.
            DropdownButtonFormField<String?>(
              initialValue: _subCategoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('Uncategorised')),
                for (final category in categories)
                  for (final sub in category.subCategories)
                    DropdownMenuItem(
                      value: sub.id,
                      child: Text('${category.name} › ${sub.name}',
                          overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _subCategoryId = v),
            ),
            const SizedBox(height: Spacing.md),
            PaymentMethodField(
              value: _method,
              enabled: !_submitting,
              onChanged: (v) => setState(() => _method = v),
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
            if (_isPettyCash) ...[
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _givenBy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Cash given by',
                  helperText: 'For the voucher',
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _receivedBy,
                textCapitalization: TextCapitalization.words,
                decoration:
                    const InputDecoration(labelText: 'Cash received by'),
              ),
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _reference,
              decoration:
                  const InputDecoration(labelText: 'Reference (optional)'),
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
              child: Text(_submitting ? 'Saving…' : 'Save expense'),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Receipt attachments can be added from the web app.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
