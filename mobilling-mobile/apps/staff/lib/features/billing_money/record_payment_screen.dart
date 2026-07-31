import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'billing_money_providers.dart';
import 'payment_method_field.dart';

/// Record a payment received — the single most useful staff action away from a
/// desk ("the client just paid, log it before I forget").
///
/// Two steps: pick the invoice, then confirm the amount. Picking the invoice
/// first is what supplies `client_id`, which the API requires.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key});

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  UnpaidInvoice? _selected;

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

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(selected == null ? 'Choose invoice' : 'Record payment'),
      ),
      body: selected == null ? _buildPicker() : _buildForm(selected),
    );
  }

  Widget _buildPicker() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search invoice number or client',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) =>
                ref.read(billingMoneyServiceProvider).unpaidInvoices(
                      search: _search.text.trim().isEmpty
                          ? null
                          : _search.text.trim(),
                      page: page,
                    ),
            itemBuilder: (context, invoice) => Card(
              child: ListTile(
                title: Text(invoice.clientName ?? invoice.documentNumber),
                subtitle: Text([
                  invoice.documentNumber,
                  if (invoice.dueDate != null)
                    Formatting.dueDescription(invoice.dueDate),
                ].join(' · ')),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Formatting.currency(invoice.balanceDue),
                        style: Theme.of(context).textTheme.labelLarge),
                    StatusChip(invoice.status, dense: true),
                  ],
                ),
                onTap: () => setState(() => _selected = invoice),
              ),
            ),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: 'No unpaid invoices',
            emptyMessage: 'Everything is settled.',
          ),
        ),
      ],
    );
  }

  Widget _buildForm(UnpaidInvoice invoice) => _PaymentForm(
        invoice: invoice,
        onChangeInvoice: () => setState(() => _selected = null),
      );
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({required this.invoice, required this.onChangeInvoice});

  final UnpaidInvoice invoice;
  final VoidCallback onChangeInvoice;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String? _method;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  UnpaidInvoice get invoice => widget.invoice;

  @override
  void initState() {
    super.initState();
    // Prefill the balance due — the overwhelmingly common case is paying in full.
    _amount = TextEditingController(text: invoice.balanceDue.toStringAsFixed(2));
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final clientId = invoice.clientId;
    if (clientId == null || clientId.isEmpty) {
      // The API requires client_id and the invoice row is where we get it.
      setState(() => _error =
          'This invoice has no client on record — record the payment from the web app.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final message =
          await ref.read(billingMoneyServiceProvider).recordPaymentIn(
                clientId: clientId,
                documentId: invoice.id,
                amount: double.parse(_amount.text.trim()),
                paymentDate: _date,
                paymentMethod: _method!,
                reference: _reference.text.trim().isEmpty
                    ? null
                    : _reference.text.trim(),
                notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              );

      // The dashboard's collected/outstanding figures just changed.
      ref.invalidate(dashboardProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'Payment recorded.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('amount') ??
          e.errorFor('payment_date') ??
          e.errorFor('payment_method') ??
          e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.md),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],

            Card(
              child: ListTile(
                title: Text(invoice.clientName ?? invoice.documentNumber),
                subtitle: Text([
                  invoice.documentNumber,
                  'balance ${Formatting.currency(invoice.balanceDue)}',
                  if (invoice.isPartlyPaid)
                    'paid ${Formatting.currency(invoice.paidAmount)}',
                ].join(' · ')),
                trailing: TextButton(
                  onPressed: _submitting ? null : widget.onChangeInvoice,
                  child: const Text('Change'),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),

            TextFormField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${Formatting.tenantCurrency} ',
                helperText:
                    'Balance due ${Formatting.amount(invoice.balanceDue)}',
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed < 0.01) {
                  return 'Enter a valid amount';
                }
                // Overpayment isn't rejected by the API (credit can result),
                // so warn rather than block — but catch obvious typos.
                if (parsed > invoice.balanceDue * 10) {
                  return 'That looks far too large — check the amount';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),

            PaymentMethodField(
              value: _method,
              enabled: !_submitting,
              onChanged: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: Spacing.md),

            InkWell(
              onTap: _submitting ? null : _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Payment date',
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(Formatting.date(_date)),
              ),
            ),
            const SizedBox(height: Spacing.md),

            TextFormField(
              controller: _reference,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                helperText: 'M-Pesa code, cheque number, bank slip…',
              ),
            ),
            const SizedBox(height: Spacing.md),

            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 3,
              decoration:
                  const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: Spacing.lg),

            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Record payment'),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'A receipt is emailed to the client automatically.',
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
