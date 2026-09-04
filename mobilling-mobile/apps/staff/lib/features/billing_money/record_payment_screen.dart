import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart' show ClientPickerSheet;
import 'billing_money_providers.dart';
import 'payment_method_field.dart';

/// Record a payment received — the single most useful staff action away from a
/// desk ("the client just paid, log it before I forget").
///
/// Two steps: pick the invoice, then confirm the amount. Picking the invoice
/// first is what supplies `client_id`, which the API requires. The "no
/// invoice" trailing action skips straight to a client picker instead, for a
/// standalone payment — the API accepts `document_id` as optional and only
/// ever needed it for that one field.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, this.invoice});

  /// Arrived from an invoice rather than from the menu: skip the picker and
  /// open straight on the form. "Change invoice" still steps back to it.
  final UnpaidInvoice? invoice;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  UnpaidInvoice? _selected;
  StaffClient? _standaloneClient;

  @override
  void initState() {
    super.initState();
    _selected = widget.invoice;
  }

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

  Future<void> _pickStandaloneClient() async {
    final client = await ClientPickerSheet.show(context);
    if (client != null) setState(() => _standaloneClient = client);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final standalone = _standaloneClient;
    final showingForm = selected != null || standalone != null;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: showingForm ? 'Record payment' : 'Choose invoice',
        trailing: showingForm
            ? null
            : InkActionButton(
                icon: Icons.person_search_outlined,
                tooltip: 'Standalone payment — no invoice',
                onPressed: _pickStandaloneClient,
              ),
        // The search lives on the ink while picking, and leaves with the
        // picker so the form's masthead is the one line it needs.
        bottom: showingForm
            ? null
            : InkSearchField(
                controller: _search,
                hint: 'Search invoice number or client',
                onChanged: _onSearchChanged,
              ),
      ),
      body: selected != null
          ? _buildForm(selected)
          : standalone != null
          ? _buildStandaloneForm(standalone)
          : _buildPicker(),
    );
  }

  Widget _buildPicker() {
    return PagedListView(
      key: _listKey,
      fetch: (page) => ref
          .read(billingMoneyServiceProvider)
          .unpaidInvoices(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            page: page,
          ),
      itemBuilder: (context, invoice) => Card(
        child: ListTile(
          title: Text(
            invoice.clientName ?? invoice.documentNumber,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Row(
              children: [
                StatusChip(invoice.status, dense: true),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: _Meta(
                    [
                      invoice.documentNumber,
                      if (invoice.dueDate != null)
                        Formatting.dueDescription(invoice.dueDate),
                    ].join(' · '),
                  ),
                ),
              ],
            ),
          ),
          trailing: Money(invoice.balanceDue),
          onTap: () => setState(() => _selected = invoice),
        ),
      ),
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No unpaid invoices',
      emptyMessage: 'Everything is settled. Try another name or number.',
    );
  }

  Widget _buildForm(UnpaidInvoice invoice) => _PaymentForm(
    invoice: invoice,
    clientId: invoice.clientId ?? '',
    clientName: invoice.clientName,
    onChangeSelection: () => setState(() => _selected = null),
  );

  Widget _buildStandaloneForm(StaffClient client) => _PaymentForm(
    clientId: client.id,
    clientName: client.name,
    onChangeSelection: () => setState(() => _standaloneClient = null),
  );
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({
    this.invoice,
    required this.clientId,
    this.clientName,
    required this.onChangeSelection,
  });

  /// Null for a standalone payment — the amount goes on the books with no
  /// invoice attached at all.
  final UnpaidInvoice? invoice;
  final String clientId;
  final String? clientName;
  final VoidCallback onChangeSelection;

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

  /// The web's add-payment form ships this checked, and the API's own default
  /// (`boolean('send_email', true)`) agrees — so the receipt goes out unless
  /// the person collecting says otherwise.
  bool _sendEmail = true;

  UnpaidInvoice? get invoice => widget.invoice;

  @override
  void initState() {
    super.initState();
    // Prefill the balance due — the overwhelmingly common case is paying in
    // full. A standalone payment has no balance to prefill from.
    final invoice = widget.invoice;
    _amount = TextEditingController(
      text: invoice == null ? '' : invoice.balanceDue.toStringAsFixed(2),
    );
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

    final clientId = widget.clientId;
    if (clientId.isEmpty) {
      // The API requires client_id — an invoice missing one can't be posted.
      setState(
        () => _error =
            'This invoice has no client on record — record the payment from the web app.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final message = await ref
          .read(billingMoneyServiceProvider)
          .recordPaymentIn(
            clientId: clientId,
            documentId: widget.invoice?.id,
            amount: double.parse(_amount.text.trim()),
            paymentDate: _date,
            paymentMethod: _method!,
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            sendEmail: _sendEmail,
          );

      // The dashboard's collected/outstanding figures just changed.
      ref.invalidate(dashboardProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message ?? 'Payment recorded.')));
      Navigator.of(context).pop(true);
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
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invoice = widget.invoice;

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

            // The one figure this screen is about: what is still owed — or,
            // for a standalone payment, simply who it's for.
            Reveal(
              child: invoice == null
                  ? _StandaloneHeader(
                      clientName: widget.clientName ?? 'Client',
                      action: TextButton(
                        onPressed: _submitting
                            ? null
                            : widget.onChangeSelection,
                        child: const Text('Change client'),
                      ),
                    )
                  : _HeroFigure(
                      label: 'Balance due',
                      amount: invoice.balanceDue,
                      title: invoice.clientName ?? invoice.documentNumber,
                      meta: [
                        invoice.documentNumber,
                        if (invoice.isPartlyPaid)
                          'paid ${Formatting.currency(invoice.paidAmount)}',
                        if (invoice.dueDate != null)
                          Formatting.dueDescription(invoice.dueDate),
                      ].join(' · '),
                      status: invoice.status,
                      action: TextButton(
                        onPressed: _submitting
                            ? null
                            : widget.onChangeSelection,
                        child: const Text('Change invoice'),
                      ),
                    ),
            ),
            const SizedBox(height: Spacing.lg),

            const FieldLabel('Amount received'),
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
                helperText: invoice == null
                    ? null
                    : 'Balance due ${Formatting.amount(invoice.balanceDue)}',
              ),
              validator: (v) {
                final parsed = double.tryParse(v?.trim() ?? '');
                if (parsed == null || parsed < 0.01) {
                  return 'Enter the amount received';
                }
                // Overpayment isn't rejected by the API (credit can result),
                // so warn rather than block — but catch obvious typos. A
                // standalone payment has no balance to sanity-check against.
                if (invoice != null && parsed > invoice.balanceDue * 10) {
                  return 'That looks far too large — check the amount';
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
            _DateField(date: _date, enabled: !_submitting, onTap: _pickDate),
            const SizedBox(height: Spacing.md),

            const FieldLabel('Reference (optional)'),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _reference,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'M-Pesa code, cheque number, bank slip…',
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
                hintText: 'Anything the receipt should not say',
              ),
            ),
            const SizedBox(height: Spacing.md),

            // The receipt is the client's proof, so it goes out by default —
            // but a payment logged days late, or one the client already has a
            // paper receipt for, should not mail a second one. The API only
            // mails a receipt when there's a document to attach it to, so a
            // standalone payment has nothing for this checkbox to do.
            if (invoice != null) ...[
              CheckboxListTile(
                value: _sendEmail,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _sendEmail = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Email the receipt to the client'),
                subtitle: Text(
                  invoice.clientName == null
                      ? 'Sent to the address on the client record.'
                      : 'Sent to ${invoice.clientName}’s address on file.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],

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

/// The card a form leads with: the figure the form is about, in the display
/// scale, named by an eyebrow and explained by one mono line.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({
    required this.label,
    required this.amount,
    required this.title,
    required this.meta,
    this.status,
    this.action,
  });

  final String label;
  final Object? amount;
  final String title;
  final String meta;
  final String? status;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
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
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Money(amount, scale: MoneyScale.display),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: Text(
                title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                if (status != null) ...[
                  StatusChip(status, dense: true),
                  const SizedBox(width: Spacing.sm),
                ],
                Expanded(child: _Meta(meta)),
                ?action,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The card a standalone form leads with instead of [_HeroFigure] — there is
/// no balance to headline, only the client the payment is being logged for.
class _StandaloneHeader extends StatelessWidget {
  const _StandaloneHeader({required this.clientName, this.action});

  final String clientName;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.sm,
          Spacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'STANDALONE PAYMENT · NO INVOICE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    clientName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// A tappable field showing the chosen date, dressed as every other field.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          Formatting.date(date),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontFeatures: Type.figures,
          ),
        ),
      ),
    );
  }
}

/// A mono metadata line — reference · date — in the eyebrow register.
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
