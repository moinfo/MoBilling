import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/attach_file.dart';
import 'billing_money_providers.dart';
import 'payment_method_field.dart';

/// Pay a bill — pick an unsettled bill, then enter the payment.
///
/// The amount is capped at the bill's remaining balance client-side because
/// `StorePaymentOutRequest::withValidator` rejects anything above it (and
/// rejects already-settled bills outright), and a caught 422 is a worse
/// experience than a disabled row.
class PayBillScreen extends ConsumerStatefulWidget {
  const PayBillScreen({super.key, this.initialBill});

  /// Skips the picker straight to the payment form — the Statutory Bills
  /// screen's own "Mark paid" action already knows which bill it means.
  final StaffBill? initialBill;

  @override
  ConsumerState<PayBillScreen> createState() => _PayBillScreenState();
}

class _PayBillScreenState extends ConsumerState<PayBillScreen> {
  late StaffBill? _selected = widget.initialBill;
  List<StaffBill>? _bills;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // Still loaded even when a bill is preselected, so "change bill" (from
    // the payment form) has a list to fall back to.
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
      setState(
        () => _bills = all
            .where((b) => b.isActive && !b.isPaid && b.remaining > 0)
            .toList(growable: false),
      );
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
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: selected == null ? 'Choose bill' : 'Pay bill',
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
        actionLabel: 'Try again',
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

    final owed = bills.fold<double>(0, (sum, b) => sum + b.remaining);

    return RefreshIndicator(
      onRefresh: _loadBills,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          // What the whole list adds up to — the figure the picker is about.
          Reveal(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow(
                      '${bills.length} ${bills.length == 1 ? 'bill' : 'bills'} still owed',
                    ),
                    const SizedBox(height: Spacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Money(owed, scale: MoneyScale.display),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Choose a bill to pay'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, bill) in bills.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(
                      bill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Row(
                        children: [
                          StatusChip(bill.status, dense: true),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: _Meta(
                              [
                                if (bill.categoryName != null)
                                  bill.categoryName!,
                                if (bill.dueDate != null)
                                  Formatting.dueDescription(bill.dueDate),
                                if (bill.paidTotal > 0)
                                  'paid ${Formatting.amount(bill.paidTotal)} of ${Formatting.amount(bill.amount)}',
                              ].join(' · '),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Money(bill.remaining),
                    onTap: () => setState(() => _selected = bill),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

  /// Proof of payment — the bank slip or the stamped control-number receipt.
  Attachment? _receipt;

  /// `StorePaymentOutRequest` caps the upload at `max:5120` (KB).
  static const _maxReceiptBytes = 5120 * 1024;

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

  /// Attach the receipt — camera first, since paying a bill from a phone
  /// usually means the slip is in your hand.
  Future<void> _pickReceipt() async {
    final picked = await pickAttachment(
      context,
      // Exactly the API's `mimes:pdf,jpg,jpeg,png`.
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (picked == null || !mounted) return;

    if (picked.bytes > _maxReceiptBytes) {
      setState(
        () => _error =
            'That receipt is ${picked.readableSize} — the limit is 5 MB.',
      );
      return;
    }
    setState(() {
      _receipt = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(billingMoneyServiceProvider)
          .recordPaymentOut(
            billId: bill.id,
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
            receiptPath: _receipt?.path,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('amount') ??
            e.errorFor('bill_id') ??
            e.errorFor('receipt') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.xl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],

            // The one figure this screen is about: what is left to pay.
            Reveal(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.sm,
                    Spacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Eyebrow('Remaining on this bill'),
                      const SizedBox(height: Spacing.sm),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Money(bill.remaining, scale: MoneyScale.display),
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        bill.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          StatusChip(bill.status, dense: true),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: _Meta(
                              [
                                'of ${Formatting.currency(bill.amount)}',
                                if (bill.dueDate != null)
                                  Formatting.dueDescription(bill.dueDate),
                              ].join(' · '),
                            ),
                          ),
                          TextButton(
                            onPressed: _submitting ? null : widget.onChangeBill,
                            child: const Text('Change bill'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),

            const FieldLabel('Amount paid'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _amount,
              enabled: !_submitting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: Type.figures,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${Formatting.tenantCurrency} ',
                helperText: 'At most ${Formatting.amount(bill.remaining)}',
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed < 0.01) {
                  return 'Enter the amount paid';
                }
                // Mirrors the server's withValidator rule.
                if (parsed > bill.remaining + 0.005) {
                  return 'Cannot exceed the remaining ${Formatting.amount(bill.remaining)}';
                }
                return null;
              },
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

            const FieldLabel('Payment date'),
            const SizedBox(height: Spacing.sm),
            InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: _submitting ? null : _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                ),
                child: Text(
                  Formatting.date(_date),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFeatures: Type.figures,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),

            const FieldLabel('Control number (optional)'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _controlNumber,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'The TRA / NSSF control number',
                helperText:
                    'For statutory payments made against a control number',
              ),
            ),
            const SizedBox(height: Spacing.md),

            const FieldLabel('Reference (optional)'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _reference,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Bank slip, cheque or transaction number',
              ),
            ),
            const SizedBox(height: Spacing.md),

            const FieldLabel('Notes (optional)'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _notes,
              enabled: !_submitting,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Anything worth remembering about this payment',
              ),
            ),
            const SizedBox(height: Spacing.md),

            const FieldLabel('Receipt (optional)'),
            const SizedBox(height: Spacing.sm),
            _ReceiptField(
              file: _receipt,
              enabled: !_submitting,
              onPick: _pickReceipt,
              onClear: () => setState(() => _receipt = null),
            ),
            const SizedBox(height: Spacing.lg),

            PrimaryButton(
              label: _submitting ? 'Recording…' : 'Record payment',
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// The attach-a-receipt control: an empty field that opens the picker, or the
/// chosen file named with its size and a way to drop it again.
class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.file,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final Attachment? file;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen = file;

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.attach_file_outlined, size: 20),
          suffixIcon: chosen == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove receipt',
                  onPressed: enabled ? onClear : null,
                ),
          helperText: chosen == null
              ? 'A photo of the slip or the PDF receipt — up to 5 MB'
              : null,
        ),
        child: chosen == null
            ? Text(
                'Attach a receipt',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      chosen.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    chosen.readableSize,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The eyebrow that names a figure: Plex Mono, upper-case, quiet.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A mono metadata line — category · due date — in the eyebrow register.
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
