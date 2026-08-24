import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../../providers.dart';
import '../../common/share_pdf.dart';
import '../portal_providers.dart';
import '../portal_sheet.dart';
import 'pay_invoice_sheet.dart';

/// Full invoice view — items, totals, payments, parties and how to pay.
///
/// Online payment goes through [PayInvoiceSheet] (Pesapal); the tenant's
/// offline instructions render inline for clients who prefer bank/M-Pesa.
class PortalInvoiceDetailScreen extends ConsumerWidget {
  const PortalInvoiceDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(portalDocumentProvider(documentId));
    final payable = document.valueOrNull?.isPayable ?? false;

    // Cancellation opens a billing ticket that commits the company to a
    // conversation, so the API restricts it to portal admins — a viewer must
    // not see an action that would only answer 403.
    final isAdmin = ref.watch(currentUserProvider)?.isPortalAdmin ?? false;
    final canCancel = isAdmin && (document.valueOrNull?.isCancellable ?? false);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: document.valueOrNull?.documentNumber ?? 'Invoice',
        trailing: !document.hasValue
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkActionButton(
                    icon: Icons.ios_share_outlined,
                    tooltip: 'Share PDF',
                    onPressed: () => sharePdf(
                      context,
                      fetch: () => ref
                          .read(portalServiceProvider)
                          .documentPdf(documentId),
                      filename: '${document.value!.documentNumber}.pdf',
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  InkActionButton(
                    icon: Icons.forward_to_inbox_outlined,
                    tooltip: 'Email me this invoice',
                    onPressed: () => _resend(context, ref),
                  ),
                ],
              ),
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this invoice',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(portalDocumentProvider(documentId)),
        ),
        data: (doc) => _InvoiceBody(
          doc: doc,
          onRequestCancellation: canCancel
              ? () => _requestCancellation(context, ref, doc)
              : null,
        ),
      ),
      bottomNavigationBar: !payable
          ? null
          : _PayBar(
              balanceDue: document.valueOrNull?.balanceDue,
              onPay: () => _pay(context, ref, document.value!),
              onUseCredit: () => _applyCredit(context, ref),
            ),
    );
  }

  Future<void> _applyCredit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(portalServiceProvider)
          .applyCreditToInvoice(documentId);
      ref.invalidate(portalDocumentProvider(documentId));
      ref.invalidate(portalCreditProvider);
      ref.invalidate(portalDashboardProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Credit applied to this invoice.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    PortalDocument doc,
  ) async {
    final paid = await PayInvoiceSheet.show(context, doc);
    if (paid == true) {
      // The webhook has already settled the invoice server-side; refetch so
      // the status chip, totals and dashboard all reflect it.
      ref.invalidate(portalDocumentProvider(documentId));
      ref.invalidate(portalDashboardProvider);
    }
  }

  /// Ask staff to cancel this invoice. Nothing is cancelled here — the API
  /// raises a billing ticket, so the sheet says so and the confirm button
  /// carries the verb rather than "OK".
  Future<void> _requestCancellation(
    BuildContext context,
    WidgetRef ref,
    PortalDocument doc,
  ) async {
    final reason = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    String? fieldError;

    final confirmed = await showPortalSheet<bool>(
      context,
      eyebrow: doc.documentNumber,
      title: 'Request cancellation',
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This opens a support ticket for our billing team — the invoice '
            'is not cancelled automatically, and payment is on hold until '
            'they answer.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          FieldLabel('Why are you cancelling?'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: reason,
            maxLines: 3,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (fieldError != null) setSheetState(() => fieldError = null);
            },
            decoration: InputDecoration(
              hintText: 'Tell us why this invoice should be cancelled',
              errorText: fieldError,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Request cancellation',
            onPressed: () {
              if (reason.text.trim().isEmpty) {
                setSheetState(() => fieldError = 'Give a reason.');
                return;
              }
              Navigator.pop(context, true);
            },
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(portalServiceProvider)
          .requestDocumentCancellation(documentId, reason: reason.text.trim());
      // The invoice now carries cancellation_requested, which hides the pay
      // bar — refetch rather than leave a stale, payable-looking screen.
      ref.invalidate(portalDocumentProvider(documentId));
      ref.invalidate(portalTicketsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Cancellation request submitted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _resend(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(portalServiceProvider).resendDocument(documentId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Invoice sent to your email.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// The action bar pinned under a payable invoice: wallet credit when there
/// is any to apply, and the one primary action — pay.
class _PayBar extends ConsumerWidget {
  const _PayBar({
    required this.balanceDue,
    required this.onPay,
    required this.onUseCredit,
  });

  final Object? balanceDue;
  final VoidCallback onPay;
  final VoidCallback onUseCredit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final credit = ref.watch(portalCreditProvider).valueOrNull?.balance ?? 0;

    return Material(
      color: theme.cardTheme.color ?? scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm + Spacing.xs,
              Spacing.md,
              Spacing.md,
            ),
            child: Row(
              children: [
                if (credit > 0) ...[
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: onUseCredit,
                      child: const Text('Use credit'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
                Expanded(
                  child: PrimaryButton(
                    icon: Icons.lock_outline,
                    label: 'Pay ${Formatting.currency(balanceDue)}',
                    onPressed: onPay,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceBody extends StatelessWidget {
  const _InvoiceBody({required this.doc, this.onRequestCancellation});

  final PortalDocument doc;

  /// Null for viewers, and for invoices the API would refuse to cancel.
  final VoidCallback? onRequestCancellation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Reveal(child: _HeroFigure(doc: doc)),
        const SizedBox(height: Spacing.lg),

        if (doc.cancellationRequested) ...[
          Card(
            color: Color.alphaBlend(
              context.statusColors.attention.withValues(alpha: 0.08),
              theme.cardTheme.color ?? scheme.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.pending_actions_outlined,
                    size: 20,
                    color: context.statusColors.attention,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'A cancellation request for this invoice is with our '
                      'billing team — payment is on hold until it is '
                      'resolved. Check your tickets for updates.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
        ],

        // Line items.
        const SectionHeader('Items'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, item) in doc.items.indexed) ...[
                  if (i > 0) const Divider(height: Spacing.md),
                  _ItemRow(item: item),
                ],
                const Divider(height: Spacing.lg),
                _TotalRow('Subtotal', doc.subtotal),
                if (doc.discountAmount > 0)
                  _TotalRow('Discount', -doc.discountAmount),
                if (doc.taxAmount > 0) _TotalRow('Tax', doc.taxAmount),
                if (doc.lateFee > 0) _TotalRow('Late fee', doc.lateFee),
                _TotalRow('Total', doc.total, bold: true),
                if (doc.paidAmount > 0) _TotalRow('Paid', -doc.paidAmount),
                if (doc.paidAmount > 0)
                  _TotalRow('Balance due', doc.balanceDue, bold: true),
              ],
            ),
          ),
        ),

        // Payments made against this invoice.
        if (doc.payments.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Payments'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, p) in doc.payments.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _PaymentTile(payment: p),
                ],
              ],
            ),
          ),
        ],

        // How to pay — the tenant's offline instructions.
        if (doc.isPayable && doc.paymentMethods.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('How to pay'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, method) in doc.paymentMethods.indexed) ...[
                    if (i > 0) const Divider(height: Spacing.md),
                    if (method.name != null)
                      Text(method.name!, style: theme.textTheme.titleSmall),
                    if (method.details != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        method.details!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],

        // Parties.
        if (doc.invoicedTo != null || doc.payTo != null) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Parties'),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.invoicedTo != null)
                Expanded(
                  child: _PartyCard(
                    title: 'Invoiced to',
                    party: doc.invoicedTo!,
                  ),
                ),
              if (doc.invoicedTo != null && doc.payTo != null)
                const SizedBox(width: Spacing.sm),
              if (doc.payTo != null)
                Expanded(
                  child: _PartyCard(title: 'Pay to', party: doc.payTo!),
                ),
            ],
          ),
        ],

        if (doc.notes != null) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Notes'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text(doc.notes!, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],

        if (onRequestCancellation != null) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Manage'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: ListTile(
              leading: Icon(Icons.cancel_outlined, color: scheme.error),
              title: Text(
                'Request cancellation',
                style: TextStyle(color: scheme.error),
              ),
              subtitle: Text(
                'OPENS A BILLING TICKET',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: onRequestCancellation,
            ),
          ),
        ],
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

/// The one figure this screen is about — the balance due while the invoice
/// is open, the total once it is settled — on a card tinted 6% toward the
/// figure's state, with the status chip and the issue date above it.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.doc});

  final PortalDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final late = doc.isPayable && (Formatting.daysUntil(doc.dueDate) ?? 1) < 0;
    final tone = doc.isPayable
        ? (late ? status.overdue : status.attention)
        : status.settled;

    return Card(
      color: Color.alphaBlend(
        tone.withValues(alpha: 0.06),
        theme.cardTheme.color ?? theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(doc.status),
                const Spacer(),
                Text(
                  Formatting.date(doc.date).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              (doc.isPayable ? 'Balance due' : 'Total').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Money(
                doc.isPayable ? doc.balanceDue : doc.total,
                scale: MoneyScale.display,
                color: tone,
              ),
            ),
            if (doc.isPayable && doc.dueDate != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                Formatting.dueDescription(doc.dueDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: late
                      ? status.overdue
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: late ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final DocumentItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description, style: theme.textTheme.bodyMedium),
              if (item.serviceFrom != null && item.serviceTo != null)
                Text(
                  '${Formatting.date(item.serviceFrom)} – ${Formatting.date(item.serviceTo)}',
                  style: muted,
                ),
              if (item.quantity != 1)
                Text(
                  '${Formatting.amount(item.quantity)} × ${Formatting.currency(item.price)}',
                  style: muted,
                ),
            ],
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Money(item.total, scale: MoneyScale.dense, showCode: false),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final PaymentSummary payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(
        Formatting.date(payment.paymentDate),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        [
          if (payment.paymentMethod != null) payment.paymentMethod!,
          if (payment.reference != null) payment.reference!,
        ].join(' · ').toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Money(payment.amount, color: status.settled),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Only the final line carries the currency code. Repeating it down a
    // totals column adds three words and no information — the column is all
    // one currency by definition.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: bold ? Spacing.xs : 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
          Money(
            value,
            scale: bold ? MoneyScale.row : MoneyScale.dense,
            showCode: bold,
            color: bold ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({required this.title, required this.party});

  final String title;
  final PartyPanel party;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      party.name,
      party.address,
      party.email,
      party.phone,
      if (party.taxId != null) 'TIN: ${party.taxId}',
    ].whereType<String>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            for (final line in lines)
              Text(line, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
