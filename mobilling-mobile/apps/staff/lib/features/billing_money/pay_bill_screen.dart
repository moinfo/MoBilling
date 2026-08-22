import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'billing_money_providers.dart';
import 'payment_method_field.dart';

/// Pay a bill — pick an unsettled bill, then enter the payment.
///
/// The amount is capped at the bill's remaining balance client-side because
/// `StorePaymentOutRequest::withValidator` rejects anything above it (and
/// rejects already-settled bills outright), and a caught 422 is a worse
/// experience than a disabled row.
class PayBillScreen extends ConsumerStatefulWidget {
  const PayBillScreen({super.key});

  @override
  ConsumerState<PayBillScreen> createState() => _PayBillScreenState();
}

class _PayBillScreenState extends ConsumerState<PayBillScreen> {
  StaffBill? _selected;
  List<StaffBill>? _bills;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // /bills is paginated oldest-due first, and the oldest are mostly
      // paid — walk every page (bounded) so the bill that still needs paying
      // is actually offered.
      final service = ref.read(billingMoneyServiceProvider);
      final all = <StaffBill>[];
      var page = await service.bills(perPage: 100);
      all.addAll(page.items);
      while (page.hasMore && page.currentPage < 20) {
        page = await service.bills(page: page.nextPage!, perPage: 100);
        all.addAll(page.items);
      }
      if (!mounted) return;
      // Only bills that can still take a payment.
      setState(() => _bills = all
          .where((b) => b.isActive && !b.isPaid && b.remaining > 0)
          .toList(growable: false));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(selected == null ? 'Choose bill' : 'Pay bill'),
      ),
      body: selected != null
          ? _PayBillForm(
              bill: selected,
              onChangeBill: () => setState(() => _selected = null),
            )
          : _buildPicker(context),
    );
  }

  Widget _buildPicker(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_loadError != null) {
      return StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load bills',
        message: _loadError,
        actionLabel: 'Retry',
        onAction: _loadBills,
      );
    }

    final bills = _bills ?? const <StaffBill>[];
    if (bills.isEmpty) {
      return const StateMessage(
        icon: Icons.check_circle_outline,
        title: 'Nothing outstanding',
        message: 'Every active bill is fully paid.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: bills.length,
      separatorBuilder: (context, index) => const SizedBox(height: Spacing.sm),
      itemBuilder: (context, index) {
        final bill = bills[index];
        return Card(
          child: ListTile(
            title: Text(bill.name),
            subtitle: Text([
              if (bill.categoryName != null) bill.categoryName!,
              if (bill.dueDate != null) Formatting.dueDescription(bill.dueDate),
              if (bill.paidTotal > 0)
                'paid ${Formatting.amount(bill.paidTotal)} of ${Formatting.amount(bill.amount)}',
            ].join(' · ')),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(bill.remaining),
                StatusChip(bill.status, dense: true),
              ],
            ),
            onTap: () => setState(() => _selected = bill),
          ),
        );
      },
    );
  }
}

class _PayBillForm extends ConsumerStatefulWidget {
  const _PayBillForm({required this.bill, required this.onChangeBill});

  final StaffBill bill;
  final VoidCallback onChangeBill;

  @override
  ConsumerState<_PayBillForm> createState() => _PayBillFormState();
}

class _PayBillFormState extends ConsumerState<_PayBillForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _controlNumber = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  String? _method;
  DateTime _date = DateTime.now();
  bool _submitting = false;
  String? _error;

  StaffBill get bill => widget.bill;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: bill.remaining.toStringAsFixed(2));
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
      // Unlike payments-in, the API does NOT cap payment_date at today here,
      // so a forward-dated payment is legitimate.
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(billingMoneyServiceProvider).recordPaymentOut(
            billId: bill.id,
            amount: double.parse(_amount.text.trim()),
            paymentDate: _date,
            paymentMethod: _method!,
            controlNumber: _controlNumber.text.trim().isEmpty
                ? null
                : _controlNumber.text.trim(),
            reference:
                _reference.text.trim().isEmpty ? null : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Payment recorded.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error =
          e.errorFor('amount') ?? e.errorFor('bill_id') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                title: Text(bill.name),
                subtitle: Text(
                    'Remaining ${Formatting.currency(bill.remaining)} of ${Formatting.currency(bill.amount)}'),
                trailing: TextButton(
                  onPressed: _submitting ? null : widget.onChangeBill,
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
                    'At most ${Formatting.amount(bill.remaining)}',
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed < 0.01) {
                  return 'Enter a valid amount';
                }
                // Mirrors the server's withValidator rule.
                if (parsed > bill.remaining + 0.005) {
                  return 'Cannot exceed the remaining ${Formatting.amount(bill.remaining)}';
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
              controller: _controlNumber,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Control number (optional)',
                helperText: 'For TRA / NSSF style statutory payments',
              ),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _reference,
              enabled: !_submitting,
              decoration:
                  const InputDecoration(labelText: 'Reference (optional)'),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
          ],
        ),
      ),
    );
  }
}
