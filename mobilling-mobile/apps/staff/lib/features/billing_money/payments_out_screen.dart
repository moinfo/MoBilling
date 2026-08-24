import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmField, CrmPickerField, CrmSheet, showCrmSheet;
import 'billing_money_providers.dart';
import 'payment_method_field.dart';

/// Money paid out against bills — the web's Statutory → Payment History.
///
/// Tapping a row opens the actions sheet: a payment out can be corrected or
/// removed, and both move the bill's `paid_at` with them.
class PaymentsOutScreen extends ConsumerStatefulWidget {
  const PaymentsOutScreen({super.key});

  @override
  ConsumerState<PaymentsOutScreen> createState() => _PaymentsOutScreenState();
}

class _PaymentsOutScreenState extends ConsumerState<PaymentsOutScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  Future<void> _payBill() async {
    final recorded = await context.push<bool>('/payments-out/new');
    if (recorded == true) _listKey.currentState?.reload();
  }

  Future<void> _openActions(StaffPaymentOut payment) async {
    final changed = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _PaymentOutActionsSheet(payment: payment),
    );
    if (changed == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canPay =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingMoneyPermissions.paymentsOutCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Payment history',
        trailing: canPay
            ? InkActionButton(
                icon: Icons.add_card_outlined,
                tooltip: 'Pay a bill',
                onPressed: _payBill,
              )
            : null,
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) =>
            ref.read(billingMoneyServiceProvider).paymentsOut(page: page),
        itemBuilder: (context, payment) => Card(
          child: ListTile(
            title: Text(
              payment.billName ?? 'Bill payment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: _Meta(
                [
                  Formatting.date(payment.paymentDate),
                  if (payment.paymentMethod != null) payment.paymentMethod!,
                  if (payment.controlNumber != null)
                    'ctrl ${payment.controlNumber}',
                  if (payment.reference != null) payment.reference!,
                ].join(' · '),
              ),
            ),
            trailing: Money(payment.amount),
            onTap: () => _openActions(payment),
          ),
        ),
        emptyIcon: Icons.history_outlined,
        emptyTitle: 'No payments out yet',
        emptyMessage: canPay
            ? 'Pay a bill from the button above and it appears here.'
            : 'Payments made against bills appear here.',
      ),
    );
  }
}

/// What can be done to one payment out. Each row is gated on the permission
/// its route carries, so a sheet with nothing granted still explains itself.
class _PaymentOutActionsSheet extends ConsumerStatefulWidget {
  const _PaymentOutActionsSheet({required this.payment});

  final StaffPaymentOut payment;

  @override
  ConsumerState<_PaymentOutActionsSheet> createState() =>
      _PaymentOutActionsSheetState();
}

class _PaymentOutActionsSheetState
    extends ConsumerState<_PaymentOutActionsSheet> {
  bool _busy = false;

  StaffPaymentOut get payment => widget.payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(sessionControllerProvider).session;
    final canUpdate =
        auth?.can(BillingMoneyPermissions.paymentsOutUpdate) ?? false;
    final canDelete =
        auth?.can(BillingMoneyPermissions.paymentsOutDelete) ?? false;
    final receipt = payment.receiptUrl;

    return SafeArea(
      child: CrmSheet(
        eyebrow: payment.billName ?? 'Bill payment',
        title: Formatting.currency(payment.amount),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: _Meta(
              [
                Formatting.date(payment.paymentDate),
                if (payment.paymentMethod != null) payment.paymentMethod!,
                if (payment.controlNumber != null)
                  'ctrl ${payment.controlNumber}',
                if (payment.reference != null) payment.reference!,
              ].join(' · '),
            ),
          ),
          if (payment.notes != null && payment.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Text(payment.notes!, style: theme.textTheme.bodyMedium),
            ),
          if (receipt != null && receipt.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('View the attached receipt'),
              enabled: !_busy,
              onTap: () => launchUrl(
                Uri.parse(receipt),
                mode: LaunchMode.externalApplication,
              ),
            ),
          if (canUpdate)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit this payment'),
              enabled: !_busy,
              onTap: _edit,
            ),
          if (canDelete)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete', style: TextStyle(color: scheme.error)),
              enabled: !_busy,
              onTap: _delete,
            ),
          if (!canUpdate && !canDelete)
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
    final navigator = Navigator.of(context);
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _EditPaymentOutSheet(payment: payment),
    );
    if (saved == true) navigator.pop(true);
  }

  Future<void> _delete() async {
    // Naming both the amount and the bill is the point of the confirmation:
    // this figure leaves the books and the bill may reopen because of it.
    final sure = await _confirmDelete(context, payment);
    if (!sure || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(billingMoneyServiceProvider)
          .deletePaymentOut(payment.id);
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

Future<bool> _confirmDelete(
  BuildContext context,
  StaffPaymentOut payment,
) async {
  final scheme = Theme.of(context).colorScheme;
  final bill = payment.billName ?? 'this bill';
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Delete the ${Formatting.currency(payment.amount)} payment '
        'for $bill?',
      ),
      content: Text(
        'The payment comes off the books and $bill is recalculated — if this '
        'was what settled it, it reopens as unpaid.',
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

/// Correct a payment out. `PUT /payments-out/{id}` validates with `sometimes`
/// rules and — unlike the store route — applies no remaining-balance check, so
/// nothing is capped here either; the controller recomputes the bill's
/// `paid_at` from the new total. The receipt file cannot be replaced: the
/// update route ignores it.
class _EditPaymentOutSheet extends ConsumerStatefulWidget {
  const _EditPaymentOutSheet({required this.payment});

  final StaffPaymentOut payment;

  @override
  ConsumerState<_EditPaymentOutSheet> createState() =>
      _EditPaymentOutSheetState();
}

class _EditPaymentOutSheetState extends ConsumerState<_EditPaymentOutSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _controlNumber;
  late final TextEditingController _reference;
  late final TextEditingController _notes;

  late String? _method;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  StaffPaymentOut get payment => widget.payment;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: payment.amount.toStringAsFixed(2));
    _controlNumber = TextEditingController(text: payment.controlNumber ?? '');
    _reference = TextEditingController(text: payment.reference ?? '');
    _notes = TextEditingController(text: payment.notes ?? '');
    _method = payment.paymentMethod;
    _date = payment.paymentDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _controlNumber.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      // No `before_or_equal:today` on this route, unlike payments-in.
      lastDate: DateTime(DateTime.now().year + 1),
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
          .updatePaymentOut(
            id: payment.id,
            amount: double.parse(_amount.text.trim()),
            paymentDate: _date,
            paymentMethod: _method!,
            controlNumber: _controlNumber.text.trim().isEmpty
                ? null
                : _controlNumber.text.trim(),
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
            e.errorFor('payment_method') ??
            e.errorFor('payment_date') ??
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
          eyebrow: payment.billName ?? 'Bill payment',
          title: 'Edit payment',
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Amount paid',
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
                    return 'Enter the amount paid';
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
              label: 'Control number (optional)',
              child: TextFormField(
                controller: _controlNumber,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'The TRA / NSSF control number',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Reference (optional)',
              child: TextFormField(
                controller: _reference,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'Bank slip, cheque or transaction number',
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
                  hintText: 'Anything worth remembering about this payment',
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

/// A mono metadata line — date · method · reference — in the eyebrow register.
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
