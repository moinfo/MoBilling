import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../billing_money/payment_method_field.dart';
import '../common/attach_file.dart';
import '../common/paged_list.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart' show CrmSheet, showCrmSheet;
import 'finance_providers.dart';

/// What the receipt and voucher endpoints accept: 10 MB each.
const _maxUploadBytes = 10 * 1024 * 1024;
const _receiptExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'doc',
  'docx',
  'xls',
  'xlsx',
];
const _voucherExtensions = <String>['pdf', 'jpg', 'jpeg', 'png'];

/// How many expenses are waiting on a decision, for the approver banner.
///
/// A dedicated stats endpoint doesn't exist, so this asks for the pending
/// page at `perPage: 1` and reads the paginator's `total` — one row over the
/// wire instead of walking every page just to count them.
final _pendingExpenseCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final page = await ref
      .watch(financeServiceProvider)
      .expenses(approvalStatus: 'pending', perPage: 1);
  return page.total;
});

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
  DateTimeRange? _range;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
  ];

  // The API wants a plain calendar date, not the localized display format.
  static final _ymd = DateFormat('yyyy-MM-dd');

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
    // Approving an expense changes the petty-cash verified balance and the
    // pending count both.
    ref.invalidate(pettyCashProvider);
    ref.invalidate(_pendingExpenseCountProvider);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _listKey.currentState?.reload();
  }

  void _clearDateRange() {
    setState(() => _range = null);
    _listKey.currentState?.reload();
  }

  /// The pending banner's shortcut: jump straight to the pending filter.
  void _showPending() {
    setState(() => _status = 'pending');
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionControllerProvider).session;
    final canCreate = auth?.can(FinancePermissions.expensesCreate) ?? false;
    final canApprove = auth?.can(FinancePermissions.expensesApprove) ?? false;
    final canUpdate = auth?.can(FinancePermissions.expensesUpdate) ?? false;
    final canDelete = auth?.can(FinancePermissions.expensesDelete) ?? false;
    // Only worth fetching for someone who can actually act on the queue.
    final pendingCount = canApprove
        ? ref.watch(_pendingExpenseCountProvider).valueOrNull
        : null;

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
          // Approval state, as a quiet row of chips under the masthead — the
          // date range rides along as one more chip rather than a second row,
          // since it is filtered the same way status is.
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              itemCount: _filters.length + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                if (index == _filters.length) {
                  return InputChip(
                    avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(
                      (_range == null
                              ? 'DATE RANGE'
                              : '${Formatting.date(_range!.start)} – '
                                    '${Formatting.date(_range!.end)}')
                          .toUpperCase(),
                    ),
                    selected: _range != null,
                    showCheckmark: false,
                    onPressed: _pickDateRange,
                    onDeleted: _range == null ? null : _clearDateRange,
                  );
                }
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
          if (canApprove && pendingCount != null && pendingCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.sm,
              ),
              child: _PendingBanner(count: pendingCount, onTap: _showPending),
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
                    dateFrom: _range == null
                        ? null
                        : _ymd.format(_range!.start),
                    dateTo: _range == null ? null : _ymd.format(_range!.end),
                    page: page,
                  ),
              itemBuilder: (context, expense) => _ExpenseCard(
                expense: expense,
                canApprove: canApprove,
                isOwnExpense:
                    expense.recordedById != null &&
                    expense.recordedById == auth?.user.id,
                canUpdate: canUpdate,
                canDelete: canDelete,
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

/// A prominent, tappable nudge for whoever can clear the approval queue.
///
/// Shown only to approvers, and only while something is actually waiting —
/// otherwise it would be a permanent fixture nobody reads.
class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = context.statusColors.attention;

    return Card(
      margin: EdgeInsets.zero,
      color: Color.alphaBlend(
        tone.withValues(alpha: 0.08),
        theme.cardTheme.color ?? scheme.surface,
      ),
      child: InkWell(
        borderRadius: Radii.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Icon(Icons.pending_actions_outlined, color: tone),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 expense is awaiting approval'
                      : '$count expenses are awaiting approval',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// One expense: description and amount on the first line, the chip and the
/// mono metadata line under it, and the approval decision — when there is
/// one to make — as a full row of its own at the bottom.
class _ExpenseCard extends ConsumerWidget {
  const _ExpenseCard({
    required this.expense,
    required this.canApprove,
    required this.isOwnExpense,
    required this.canUpdate,
    required this.canDelete,
    required this.onChanged,
  });

  final Expense expense;
  final bool canApprove;

  /// The server refuses to let whoever recorded an expense also decide it —
  /// separation of duties — so the button is withheld here too, rather than
  /// showing one that always ends in a 403.
  final bool isOwnExpense;
  final bool canUpdate;
  final bool canDelete;
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
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => _showActions(context, ref),
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
                  // A receipt on file is worth one glyph — it is the difference
                  // between a claim and a documented one.
                  if (expense.hasReceipt) ...[
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      Icons.attach_file,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Text(
                      [
                        if (expense.categoryPath.isNotEmpty)
                          expense.categoryPath,
                        Formatting.date(expense.expenseDate),
                        if (expense.paymentMethod != null)
                          expense.paymentMethod!,
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
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
              if (canApprove && expense.isPending && isOwnExpense) ...[
                const SizedBox(height: Spacing.md),
                Text(
                  'You recorded this — someone else has to review it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (canApprove && expense.isPending && !isOwnExpense) ...[
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
      ),
    );
  }

  /// Everything else this expense can have done to it. A phone row has no
  /// space for seven icons, so they live one tap down — approve and reject
  /// stay on the card because they are the decision the queue exists for.
  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final canSeeVouchers =
        ref
            .read(sessionControllerProvider)
            .session
            ?.can(FinancePermissions.expensesRead) ??
        false;

    final choice = await showCrmSheet<String>(
      context: context,
      builder: (context) => CrmSheet(
        eyebrow: Formatting.currency(expense.amount),
        title: expense.description,
        children: [
          Card(
            child: Column(
              children: [
                if (expense.hasReceipt)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('View receipt'),
                    onTap: () => Navigator.pop(context, 'receipt'),
                  ),
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit expense'),
                    subtitle: const Text('Attach or replace the receipt too.'),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                // Only a petty-cash expense has an approval to undo.
                if (canApprove && expense.isPettyCash && expense.isApproved)
                  ListTile(
                    leading: const Icon(Icons.undo_rounded),
                    title: const Text('Undo approval'),
                    subtitle: const Text(
                      'Back to pending; the float is restored until it is '
                      're-approved.',
                    ),
                    onTap: () => Navigator.pop(context, 'unapprove'),
                  ),
                if (expense.isPettyCash) ...[
                  if (canSeeVouchers)
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: const Text('Blank voucher'),
                      subtitle: const Text(
                        'Print it and have both parties '
                        'sign.',
                      ),
                      onTap: () => Navigator.pop(context, 'voucher'),
                    ),
                  if (expense.voucherAttachmentUrl != null)
                    ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text('View signed voucher'),
                      onTap: () => Navigator.pop(context, 'signed'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: Text(
                      expense.hasVoucher
                          ? 'Replace signed voucher'
                          : 'Upload signed voucher',
                    ),
                    subtitle: const Text('Photograph the signed slip.'),
                    onTap: () => Navigator.pop(context, 'upload'),
                  ),
                ],
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text(
                      'Delete expense',
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
      case 'receipt':
        await _open(context, expense.attachmentUrl);
      case 'signed':
        await _open(context, expense.voucherAttachmentUrl);
      case 'edit':
        await _edit(context, ref);
      case 'unapprove':
        await _unapprove(context, ref);
      case 'voucher':
        await sharePdf(
          context,
          fetch: () =>
              ref.read(financeServiceProvider).expenseVoucherPdf(expense.id),
          filename: 'voucher-${expense.id.substring(0, 8)}.pdf',
        );
      case 'upload':
        final done = await pickAndUploadVoucher(
          context,
          upload: (path, onProgress) => ref
              .read(financeServiceProvider)
              .uploadExpenseVoucher(
                expense.id,
                filePath: path,
                onProgress: onProgress,
              ),
        );
        if (done) onChanged();
      case 'delete':
        await _delete(context, ref);
    }
  }

  /// Receipts and signed vouchers sit on the server's public disk, so they
  /// open in the browser — no token to smuggle, no bytes to download first.
  Future<void> _open(BuildContext context, String? url) async {
    if (url == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open that file.')),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => RecordExpenseSheet(expense: expense),
    );
    if (saved == true) onChanged();
  }

  Future<void> _unapprove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(financeServiceProvider).unapproveExpense(expense.id);
      onChanged();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Sent back to pending review — the petty-cash balance was '
            'restored.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete expense',
          style: Type.display(22, color: scheme.onSurface),
        ),
        content: Text(
          'Delete "${expense.description}" of '
          '${Formatting.currency(expense.amount)}?',
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
          .deleteExpense(expense.id);
      onChanged();
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Expense deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
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

/// Record or edit an expense. Exposed so the petty-cash screen can reuse it
/// with the account pre-selected.
class RecordExpenseSheet extends ConsumerStatefulWidget {
  const RecordExpenseSheet({super.key, this.pettyCashAccountId, this.expense});

  /// When set, the expense is charged to the petty-cash float and the voucher
  /// signatory fields appear.
  final String? pettyCashAccountId;

  /// The expense being edited, or null to record a new one.
  final Expense? expense;

  @override
  ConsumerState<RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

class _RecordExpenseSheetState extends ConsumerState<RecordExpenseSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _controlNumber = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _givenBy = TextEditingController();
  final _receivedBy = TextEditingController();

  String? _subCategoryId;
  String? _method;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  /// The receipt about to be sent. Null while editing means "leave whatever
  /// is already on file alone" — the API only replaces what it is given.
  Attachment? _receipt;

  /// 0–1 while the receipt is on the wire.
  double? _uploadProgress;

  Expense? get _editing => widget.expense;
  bool get _isEdit => _editing != null;

  String? get _pettyCashAccountId =>
      _editing?.pettyCashAccountId ?? widget.pettyCashAccountId;
  bool get _isPettyCash => _pettyCashAccountId != null;

  @override
  void initState() {
    super.initState();
    final expense = _editing;
    if (expense == null) return;

    // Every field comes back populated: the API re-validates the whole
    // expense on update, so anything left blank here would be erased.
    _description.text = expense.description;
    _amount.text = expense.amount.toStringAsFixed(2);
    _controlNumber.text = expense.controlNumber ?? '';
    _reference.text = expense.reference ?? '';
    _notes.text = expense.notes ?? '';
    _givenBy.text = expense.givenByName ?? '';
    _receivedBy.text = expense.receivedByName ?? '';
    _subCategoryId = expense.subCategoryId;
    _method = expense.paymentMethod;
    _date = expense.expenseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [
      _description,
      _amount,
      _controlNumber,
      _reference,
      _notes,
      _givenBy,
      _receivedBy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picked = await pickAttachment(
      context,
      allowedExtensions: _receiptExtensions,
    );
    if (picked == null || !mounted) return;

    if (picked.bytes > _maxUploadBytes) {
      setState(
        () => _error =
            '${picked.name} is ${picked.readableSize} — a receipt may be at '
            'most 10 MB.',
      );
      return;
    }
    setState(() {
      _receipt = picked;
      _error = null;
    });
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
      _uploadProgress = _receipt == null ? null : 0;
    });

    String? blank(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    void onProgress(int sent, int total) {
      if (mounted && total > 0) setState(() => _uploadProgress = sent / total);
    }

    try {
      final service = ref.read(financeServiceProvider);
      final expense = _editing;
      if (expense == null) {
        await service.createExpense(
          description: _description.text.trim(),
          amount: amount,
          expenseDate: _date,
          paymentMethod: _method!,
          subCategoryId: _subCategoryId,
          pettyCashAccountId: widget.pettyCashAccountId,
          controlNumber: blank(_controlNumber),
          reference: blank(_reference),
          notes: blank(_notes),
          givenByName: blank(_givenBy),
          receivedByName: blank(_receivedBy),
          attachmentPath: _receipt?.path,
          onProgress: _receipt == null ? null : onProgress,
        );
      } else {
        await service.updateExpense(
          expense.id,
          description: _description.text.trim(),
          amount: amount,
          expenseDate: _date,
          paymentMethod: _method!,
          subCategoryId: _subCategoryId,
          pettyCashAccountId: expense.pettyCashAccountId,
          controlNumber: blank(_controlNumber),
          reference: blank(_reference),
          notes: blank(_notes),
          givenByName: blank(_givenBy),
          receivedByName: blank(_receivedBy),
          attachmentPath: _receipt?.path,
          onProgress: _receipt == null ? null : onProgress,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('amount') ??
            e.errorFor('description') ??
            e.errorFor('attachment') ??
            e.message,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _uploadProgress = null;
        });
      }
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
        bottom: sheetBottomInset(context) + Spacing.lg,
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
              _isEdit
                  ? 'Edit expense'
                  : _isPettyCash
                  ? 'Petty cash expense'
                  : 'Record expense',
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
            const FieldLabel('Control number (optional)'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _controlNumber,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'e.g. 991234567890'),
            ),
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
            const SizedBox(height: Spacing.md),
            // The reason this form is worth filling in on a phone: the slip
            // is in your hand right now.
            const FieldLabel('Receipt'),
            const SizedBox(height: Spacing.sm),
            _ReceiptField(
              picked: _receipt,
              existingUrl: _editing?.attachmentUrl,
              enabled: !_submitting,
              onPick: _pickReceipt,
              onClear: () => setState(() => _receipt = null),
            ),
            if (_uploadProgress != null) ...[
              const SizedBox(height: Spacing.sm),
              LinearProgressIndicator(value: _uploadProgress),
            ],
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _submitting
                  ? (_uploadProgress == null
                        ? 'Saving…'
                        : 'Uploading ${(_uploadProgress! * 100).round()}%')
                  : _isEdit
                  ? 'Save changes'
                  : 'Save expense',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The receipt slot: what is attached, or the invitation to attach one.
///
/// While editing, a receipt already on file is shown as a link rather than
/// re-downloaded — leaving it alone is the common case, and the API keeps
/// whatever it is not given.
class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.picked,
    required this.existingUrl,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final Attachment? picked;
  final String? existingUrl;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final file = picked;

    if (file != null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.check_circle_outline, color: scheme.primary),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          subtitle: Text(file.readableSize),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove',
            onPressed: enabled ? onClear : null,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(
            existingUrl == null ? 'Photograph the receipt' : 'Replace receipt',
          ),
          onPressed: enabled ? onPick : null,
        ),
        if (existingUrl != null) ...[
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View the receipt on file'),
              onPressed: () => launchUrl(
                Uri.parse(existingUrl!),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vouchers — shared with the petty-cash screen
// ---------------------------------------------------------------------------

/// Photograph or pick a signed voucher and send it, showing the bytes move.
///
/// Shared with the petty-cash screen because only the endpoint differs: both
/// post a `voucher` file of at most 10 MB. Returns true when the server took
/// it, so the caller knows to refresh.
Future<bool> pickAndUploadVoucher(
  BuildContext context, {
  required Future<String?> Function(String path, UploadProgress onProgress)
  upload,
}) async {
  final picked = await pickAttachment(
    context,
    allowedExtensions: _voucherExtensions,
  );
  if (picked == null || !context.mounted) return false;

  // Caught here rather than after a slow upload ends in a 422.
  if (picked.bytes > _maxUploadBytes) {
    await _showUploadFailure(
      context,
      '${picked.name} is ${picked.readableSize} — a voucher may be at most '
      '10 MB.',
    );
    return false;
  }

  final message = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UploadDialog(
      title: 'Uploading voucher',
      attachment: picked,
      upload: upload,
    ),
  );
  if (message == null || !context.mounted) return false;

  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  return true;
}

/// A failed upload gets a banner and an acknowledgement, never a silent drop.
Future<void> _showUploadFailure(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: ErrorBanner(message: message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );

/// Runs one upload and draws it. Owning the work rather than just displaying
/// it keeps the progress value's lifetime tied to the dialog that shows it.
///
/// Pops with the server's message on success; on failure it stays put and
/// swaps the bar for an [ErrorBanner], because a receipt that did not arrive
/// is something the person needs to know before walking away.
class _UploadDialog extends StatefulWidget {
  const _UploadDialog({
    required this.title,
    required this.attachment,
    required this.upload,
  });

  final String title;
  final Attachment attachment;
  final Future<String?> Function(String path, UploadProgress onProgress) upload;

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final message = await widget.upload(widget.attachment.path, (
        sent,
        total,
      ) {
        if (mounted && total > 0) setState(() => _progress = sent / total);
      });
      if (mounted) {
        Navigator.pop(context, message ?? 'Signed voucher attached.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _error == null ? widget.title : 'Upload failed',
        style: Type.display(22, color: theme.colorScheme.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ErrorBanner(message: _error!)
          else ...[
            Text(
              '${widget.attachment.name} · ${widget.attachment.readableSize}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            // Determinate, because on a slow connection an indeterminate bar
            // says nothing about whether it is worth waiting.
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: Spacing.sm),
            Text(
              '${(_progress * 100).round()}%',
              style: Type.mono(12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: _error == null
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
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
