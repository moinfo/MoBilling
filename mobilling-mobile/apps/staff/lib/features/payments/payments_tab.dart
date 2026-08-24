import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_money/billing_money_providers.dart';
import '../billing_money/payment_method_field.dart';
import '../common/paged_list.dart';
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart'
    show CrmField, CrmPickerField, CrmSheet, showCrmSheet;

/// Tenant-wide payment history. A tab body inside the home shell — the shell
/// owns the masthead, so this starts with the search.
///
/// Tapping a row opens the actions sheet, which is where the person who
/// collected the money corrects it, hands over the receipt, or takes it back
/// off the books.
class PaymentsTab extends ConsumerStatefulWidget {
  const PaymentsTab({super.key});

  @override
  ConsumerState<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<PaymentsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

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

  Future<void> _openActions(StaffPaymentIn payment) async {
    final changed = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _PaymentActionsSheet(payment: payment),
    );
    if (changed != true) return;
    // The money on the books moved: this list and the dashboard's
    // collected/outstanding figures both need refetching.
    _listKey.currentState?.reload();
    ref.invalidate(dashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.sm,
          ),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search reference or client',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            // Reads through the billing-money service rather than the leaner
            // dashboard one: an edit has to post `client_id` back, and only
            // this model carries it.
            fetch: (page) => ref
                .read(billingMoneyServiceProvider)
                .paymentsIn(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.xl,
            ),
            itemBuilder: (context, p) => Card(
              child: ListTile(
                title: Text(
                  p.clientName ?? p.documentNumber ?? 'Payment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Row(
                    children: [
                      // Every row here is money that arrived; the chip says
                      // so, which is what lets the figures stay uncoloured.
                      const StatusChip('paid', dense: true),
                      const SizedBox(width: Spacing.sm),
                      Flexible(child: _Meta(_metaLine(p))),
                    ],
                  ),
                ),
                trailing: Money(p.amount),
                onTap: () => _openActions(p),
              ),
            ),
            emptyIcon: Icons.payments_outlined,
            emptyTitle: 'No payments found',
            emptyMessage: 'Try another reference or client name.',
          ),
        ),
      ],
    );
  }
}

/// Invoice · date · method · reference — whichever of them the row has.
String _metaLine(StaffPaymentIn p) => [
  if (p.documentNumber != null && p.clientName != null) p.documentNumber!,
  Formatting.date(p.paymentDate),
  if (p.paymentMethod != null) p.paymentMethod!,
  if (p.reference != null) p.reference!,
].join(' · ');

/// What can be done to one recorded payment. Each row is gated on the exact
/// permission its route carries — `payments_in.update`, `.delete`,
/// `.resend_receipt`, and `.read` for the PDF.
class _PaymentActionsSheet extends ConsumerStatefulWidget {
  const _PaymentActionsSheet({required this.payment});

  final StaffPaymentIn payment;

  @override
  ConsumerState<_PaymentActionsSheet> createState() =>
      _PaymentActionsSheetState();
}

class _PaymentActionsSheetState extends ConsumerState<_PaymentActionsSheet> {
  bool _busy = false;

  StaffPaymentIn get payment => widget.payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(sessionControllerProvider).session;
    final canRead = auth?.can(BillingMoneyPermissions.paymentsInRead) ?? false;
    final canUpdate =
        auth?.can(BillingMoneyPermissions.paymentsInUpdate) ?? false;
    final canDelete =
        auth?.can(BillingMoneyPermissions.paymentsInDelete) ?? false;
    final canResend =
        auth?.can(BillingMoneyPermissions.paymentsInResendReceipt) ?? false;
    final nothingGranted = !canRead && !canUpdate && !canDelete && !canResend;

    return SafeArea(
      child: CrmSheet(
        eyebrow: payment.clientName ?? payment.documentNumber ?? 'Payment',
        title: Formatting.currency(payment.amount),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: _Meta(_metaLine(payment)),
          ),
          if (payment.notes != null && payment.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Text(payment.notes!, style: theme.textTheme.bodyMedium),
            ),
          if (canUpdate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit this payment'),
              subtitle: const Text('The invoice balance follows the change'),
              enabled: !_busy,
              onTap: _edit,
            ),
          if (canResend)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.forward_to_inbox_outlined),
              title: const Text('Resend the receipt'),
              subtitle: Text(
                payment.hasInvoice
                    ? 'Emailed to the address on the client record'
                    : 'Needs an invoice — this payment stands alone',
              ),
              enabled: !_busy && payment.hasInvoice,
              onTap: _resendReceipt,
            ),
          if (canRead)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Receipt PDF'),
              subtitle: const Text('Print it, or send it however you like'),
              enabled: !_busy,
              onTap: _shareReceipt,
            ),
          if (canDelete)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete', style: TextStyle(color: scheme.error)),
              enabled: !_busy,
              onTap: _delete,
            ),
          if (nothingGranted)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                'You can see this payment but not change it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final clientId = payment.clientId;
    if (clientId == null || clientId.isEmpty) {
      // `PUT /payments-in/{id}` re-validates with `StorePaymentInRequest`,
      // which requires `client_id` — without one there is nothing to send.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'This payment has no client on record — edit it from the web app.',
          ),
        ),
      );
      return;
    }

    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _EditPaymentSheet(payment: payment, clientId: clientId),
    );
    if (saved == true) navigator.pop(true);
  }

  Future<void> _resendReceipt() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(billingMoneyServiceProvider)
          .resendReceipt(payment.id);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Receipt email sent.')),
      );
    } on ApiException catch (e) {
      // "Client has no email address" is the API's own 422 wording, and it is
      // the most useful thing to show.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareReceipt() => sharePdf(
    context,
    fetch: () => ref.read(billingMoneyServiceProvider).receiptPdf(payment.id),
    filename: payment.receiptFileName,
  );

  Future<void> _delete() async {
    final sure = await _confirmDelete(context, payment);
    if (!sure || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(billingMoneyServiceProvider)
          .deletePaymentIn(payment.id);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Payment deleted.')),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Deleting a payment moves money in the books, so the confirmation names the
/// amount and the invoice, and the button says the verb.
Future<bool> _confirmDelete(
  BuildContext context,
  StaffPaymentIn payment,
) async {
  final scheme = Theme.of(context).colorScheme;
  final target = payment.documentNumber ?? payment.clientName ?? 'this client';
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Delete the ${Formatting.currency(payment.amount)} payment '
        'for $target?',
      ),
      content: Text(
        payment.hasInvoice
            ? 'The payment comes off the books and $target is recalculated — '
                  'it goes back to unpaid or partly paid, and the client may '
                  'be chased for it again.'
            : 'The payment comes off the books. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return sure ?? false;
}

/// Correct a recorded payment.
///
/// The route re-validates with `StorePaymentInRequest`, so the client and the
/// invoice go back up untouched alongside whatever changed — and the date is
/// still capped at today by `before_or_equal:today`.
class _EditPaymentSheet extends ConsumerStatefulWidget {
  const _EditPaymentSheet({required this.payment, required this.clientId});

  final StaffPaymentIn payment;
  final String clientId;

  @override
  ConsumerState<_EditPaymentSheet> createState() => _EditPaymentSheetState();
}

class _EditPaymentSheetState extends ConsumerState<_EditPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  late final TextEditingController _notes;

  late String? _method;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  StaffPaymentIn get payment => widget.payment;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: payment.amount.toStringAsFixed(2));
    _reference = TextEditingController(text: payment.reference ?? '');
    _notes = TextEditingController(text: payment.notes ?? '');
    _method = payment.paymentMethod;
    final now = DateTime.now();
    final recorded = payment.paymentDate ?? now;
    // A stored date in the future would fail the picker's own bounds.
    _date = recorded.isAfter(now) ? now : recorded;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      // The API validates payment_date as before_or_equal:today.
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(billingMoneyServiceProvider)
          .updatePaymentIn(
            id: payment.id,
            clientId: widget.clientId,
            documentId: payment.documentId,
            amount: double.parse(_amount.text.trim()),
            paymentDate: _date,
            paymentMethod: _method!,
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      messenger.showSnackBar(const SnackBar(content: Text('Payment updated.')));
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('amount') ??
            e.errorFor('payment_date') ??
            e.errorFor('payment_method') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Form(
        key: _formKey,
        child: CrmSheet(
          eyebrow: payment.documentNumber ?? payment.clientName ?? 'Payment',
          title: 'Edit payment',
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Amount received',
              child: TextFormField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFeatures: Type.figures,
                ),
                decoration: InputDecoration(
                  hintText: '0.00',
                  prefixText: '${Formatting.tenantCurrency} ',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed < 0.01) {
                    return 'Enter the amount received';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Payment method',
              child: PaymentMethodField(
                value: _method,
                enabled: !_saving,
                onChanged: (v) => setState(() => _method = v),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Payment date',
              value: Formatting.date(_date),
              onTap: _saving ? null : _pickDate,
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Reference (optional)',
              child: TextFormField(
                controller: _reference,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'M-Pesa code, cheque number, bank slip…',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Notes (optional)',
              child: TextFormField(
                controller: _notes,
                enabled: !_saving,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Anything the receipt should not say',
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save changes',
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// A mono metadata line — invoice · date · method · reference — in the
/// eyebrow register.
class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
