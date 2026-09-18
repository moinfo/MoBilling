import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/attach_file.dart';
import '../common/paged_list.dart';
import 'staff_self_providers.dart';
import '../crm/crm_ui.dart'
    show
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmPickerField,
        CrmSheet,
        showCrmSheet;

/// What each System Records withdrawal was actually spent on. Only
/// `withdraw`-type records can be linked — the same ones whose
/// `totalExpensed`/`remainingAmount` figures this feeds.
class SystemRecordExpensesScreen extends ConsumerStatefulWidget {
  const SystemRecordExpensesScreen({super.key});

  @override
  ConsumerState<SystemRecordExpensesScreen> createState() =>
      _SystemRecordExpensesScreenState();
}

class _SystemRecordExpensesScreenState
    extends ConsumerState<SystemRecordExpensesScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(_withdrawsProvider);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  Future<void> _openForm({SystemRecordExpense? expense}) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _ExpenseFormSheet(expense: expense),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(SystemRecordExpense expense) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this usage entry?'),
        content: Text(
          '"${expense.description ?? '—'}" '
          '(${Formatting.currency(expense.amount)}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
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
      await ref
          .read(staffSelfServiceProvider)
          .deleteSystemRecordExpense(expense.id);
      _reload();
      messenger.showSnackBar(
        const SnackBar(content: Text('Usage entry deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate =
        session?.can(StaffSelfPermissions.systemRecordExpensesCreate) ??
        false;
    final canUpdate =
        session?.can(StaffSelfPermissions.systemRecordExpensesUpdate) ??
        false;
    final canDelete =
        session?.can(StaffSelfPermissions.systemRecordExpensesDelete) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Records & Verification',
        title: 'Withdraw Usage',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Record usage',
                onPressed: () => _openForm(),
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search description',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: PagedListView<SystemRecordExpense>(
        key: _listKey,
        fetch: (page) => ref
            .read(staffSelfServiceProvider)
            .systemRecordExpenses(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, expense) => _ExpenseCard(
          expense: expense,
          onTap: (canUpdate || canDelete)
              ? () => _openDetail(expense, canUpdate, canDelete)
              : null,
        ),
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitle: 'No usage recorded yet',
        emptyMessage: canCreate
            ? 'What was a withdrawal actually spent on? Record it here.'
            : 'Entries appear here as they are recorded.',
      ),
    );
  }

  Future<void> _openDetail(
    SystemRecordExpense expense,
    bool canUpdate,
    bool canDelete,
  ) async {
    final action = await showCrmSheet<String>(
      context: context,
      builder: (_) => _ExpenseDetailSheet(
        expense: expense,
        canUpdate: canUpdate,
        canDelete: canDelete,
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _openForm(expense: expense);
    } else if (action == 'delete') {
      await _delete(expense);
    }
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense, required this.onTap});

  final SystemRecordExpense expense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final e = expense;

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          e.description ?? '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              Formatting.date(e.expenseDate),
              if (e.systemName != null) e.systemName!,
              if (e.propertyName != null) e.propertyName!,
            ].join(' · '),
          ),
        ),
        trailing: Money(e.amount),
      ),
    );
  }
}

class _ExpenseDetailSheet extends StatelessWidget {
  const _ExpenseDetailSheet({
    required this.expense,
    required this.canUpdate,
    required this.canDelete,
  });

  final SystemRecordExpense expense;
  final bool canUpdate;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = expense;

    return CrmSheet(
      eyebrow: Formatting.date(e.expenseDate),
      title: 'Usage entry',
      children: [
        Money(e.amount, scale: MoneyScale.headline),
        const SizedBox(height: Spacing.md),
        if (e.systemRecordAmount != null)
          CrmDetailRow(
            'Against withdraw',
            '${Formatting.currency(e.systemRecordAmount)}'
                '${e.systemRecordDate == null ? '' : ' on ${Formatting.date(e.systemRecordDate)}'}',
          ),
        if (e.systemName != null) CrmDetailRow('System', e.systemName!),
        if (e.propertyName != null)
          CrmDetailRow('Property', e.propertyName!),
        if (e.description != null)
          CrmDetailRow('Description', e.description!),
        if (e.createdByName != null)
          CrmDetailRow('Recorded by', e.createdByName!),
        if (e.attachmentUrl == null)
          const CrmDetailRow('Attachment', 'None')
        else
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(e.attachmentUrl!),
              mode: LaunchMode.externalApplication,
            ),
            child: const CrmDetailRow('Attachment', 'View →'),
          ),
        const SizedBox(height: Spacing.lg),
        if (canUpdate)
          PrimaryButton(
            label: 'Edit this entry',
            icon: Icons.edit_outlined,
            onPressed: () => Navigator.of(context).pop('edit'),
          ),
        if (canDelete) ...[
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
            label: Text('Delete', style: TextStyle(color: scheme.error)),
            onPressed: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ],
    );
  }
}

/// Add or correct a usage entry. The attachment is optional on both create
/// and edit — unlike a deposit slip, proof of spend isn't always a single
/// document.
class _ExpenseFormSheet extends ConsumerStatefulWidget {
  const _ExpenseFormSheet({this.expense});

  final SystemRecordExpense? expense;

  @override
  ConsumerState<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<_ExpenseFormSheet> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _systemRecordId;
  DateTime _date = DateTime.now();
  Attachment? _attachment;
  bool _submitting = false;
  String? _error;

  static const _maxAttachmentBytes = 10 * 1024 * 1024;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e == null) return;
    _systemRecordId = e.systemRecordId;
    _amount.text = Formatting.amount(e.amount);
    _description.text = e.description ?? '';
    _date = e.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final picked = await pickAttachment(context);
    if (picked == null) return;
    if (picked.bytes > _maxAttachmentBytes) {
      setState(() => _error = 'That file is over the 10 MB limit.');
      return;
    }
    setState(() {
      _attachment = picked;
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final description = _description.text.trim();

    if (_systemRecordId == null) {
      setState(() => _error = 'Choose which withdrawal this was spent from.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than 0.');
      return;
    }
    if (description.isEmpty) {
      setState(() => _error = 'Describe what this money was used for.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(staffSelfServiceProvider);
      if (_editing) {
        await service.updateSystemRecordExpense(
          widget.expense!.id,
          systemRecordId: _systemRecordId!,
          amount: amount,
          expenseDate: _date,
          description: description,
          attachmentPath: _attachment?.path,
        );
      } else {
        await service.createSystemRecordExpense(
          systemRecordId: _systemRecordId!,
          amount: amount,
          expenseDate: _date,
          description: description,
          attachmentPath: _attachment?.path,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Usage updated.' : 'Usage recorded.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            e.errorFor('attachment') ??
            e.errorFor('amount') ??
            e.errorFor('system_record_id') ??
            e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final withdraws = ref.watch(_withdrawsProvider);

    return CrmSheet(
      eyebrow: 'System records',
      title: _editing ? 'Edit usage' : 'Record usage',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        withdraws.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorBanner(
            message: e is ApiException
                ? 'Could not load withdrawals: ${e.message}'
                : 'Could not load withdrawals.',
          ),
          data: (rows) {
            final options = rows.where(
              (r) => r.id == _systemRecordId || (r.remainingAmount ?? r.amount) != 0,
            ).toList();
            return CrmField(
              label: 'Against withdraw',
              child: DropdownButtonFormField<String>(
                initialValue: options.any((r) => r.id == _systemRecordId)
                    ? _systemRecordId
                    : null,
                isExpanded: true,
                hint: const Text('Choose which withdrawal this was spent from'),
                items: [
                  for (final r in options)
                    DropdownMenuItem(
                      value: r.id,
                      child: Text(
                        '${r.systemName ?? '—'} / ${r.propertyName ?? '—'} — '
                        '${Formatting.currency(r.amount)} on '
                        '${Formatting.date(r.recordDate)} '
                        '(Remaining: '
                        '${Formatting.currency(r.remainingAmount ?? r.amount)})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _systemRecordId = v),
              ),
            );
          },
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Amount spent',
          child: TextField(
            controller: _amount,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: '${Formatting.tenantCurrency} ',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Date',
          value: Formatting.date(_date),
          onTap: _submitting ? null : _pickDate,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What was this money used for?',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Attachment (optional)',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(
              _attachment?.name ??
                  (_editing
                      ? 'Keep the attachment on file'
                      : 'Upload proof of spend'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _submitting ? null : _pickAttachment,
          ),
        ),
        if (_editing && widget.expense!.attachmentUrl != null && _attachment == null) ...[
          const SizedBox(height: Spacing.xs),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse(widget.expense!.attachmentUrl!),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Current attachment: view →',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Save',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Only withdraws can be linked — the same list the balance/remaining
/// figures on System Records already come from.
final AutoDisposeFutureProvider<List<SystemRecord>> _withdrawsProvider =
    FutureProvider.autoDispose<List<SystemRecord>>(
      (ref) => ref
          .watch(staffSelfServiceProvider)
          .systemRecords(type: SystemRecordTypes.withdraw, perPage: 200)
          .then((p) => p.items),
    );
