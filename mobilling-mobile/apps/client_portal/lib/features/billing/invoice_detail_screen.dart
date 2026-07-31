import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/share_pdf.dart';
import 'pay_invoice_sheet.dart';

/// Full invoice view — items, totals, payments, parties and how to pay.
///
/// Online payment goes through [PayInvoiceSheet] (Pesapal); the tenant's
/// offline instructions render inline for clients who prefer bank/M-Pesa.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentProvider(documentId));
    final payable = document.valueOrNull?.isPayable ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.valueOrNull?.documentNumber ?? 'Invoice'),
        actions: [
          if (document.hasValue) ...[
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Share PDF',
              onPressed: () => sharePdf(
                context,
                fetch: () =>
                    ref.read(portalServiceProvider).documentPdf(documentId),
                filename: '${document.value!.documentNumber}.pdf',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.forward_to_inbox_outlined),
              tooltip: 'Email me this invoice',
              onPressed: () => _resend(context, ref),
            ),
          ],
        ],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this invoice',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(documentProvider(documentId)),
        ),
        data: (doc) => _InvoiceBody(doc: doc),
      ),
      bottomNavigationBar: !payable
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Spacing.md, Spacing.sm, Spacing.md, Spacing.md),
                child: Row(
                  children: [
                    // Wallet credit, when there is any to apply.
                    Consumer(builder: (context, ref, _) {
                      final credit =
                          ref.watch(creditProvider).valueOrNull?.balance ?? 0;
                      if (credit <= 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: Spacing.sm),
                        child: OutlinedButton(
                          onPressed: () => _applyCredit(context, ref),
                          child: const Text('Use credit'),
                        ),
                      );
                    }),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: Text(
                            'Pay ${Formatting.currency(document.valueOrNull?.balanceDue)}'),
                        onPressed: () => _pay(context, ref, document.value!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _applyCredit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message =
          await ref.read(portalServiceProvider).applyCreditToInvoice(documentId);
      ref.invalidate(documentProvider(documentId));
      ref.invalidate(creditProvider);
      ref.invalidate(dashboardProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(message ?? 'Credit applied.')));
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
      ref.invalidate(documentProvider(documentId));
      ref.invalidate(dashboardProvider);
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

class _InvoiceBody extends StatelessWidget {
  const _InvoiceBody({required this.doc});

  final PortalDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        // Header: status + the number that matters most right now.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusChip(doc.status),
                    Text(
                      Formatting.date(doc.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  doc.isPayable ? 'Balance due' : 'Total',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  Formatting.currency(
                      doc.isPayable ? doc.balanceDue : doc.total),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: doc.isPayable ? status.overdue : status.settled,
                  ),
                ),
                if (doc.isPayable && doc.dueDate != null)
                  Text(
                    Formatting.dueDescription(doc.dueDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (Formatting.daysUntil(doc.dueDate) ?? 1) < 0
                          ? status.overdue
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),

        // Line items.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Items', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                for (final item in doc.items) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.description,
                                  style: theme.textTheme.bodyMedium),
                              if (item.serviceFrom != null &&
                                  item.serviceTo != null)
                                Text(
                                  '${Formatting.date(item.serviceFrom)} – ${Formatting.date(item.serviceTo)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              if (item.quantity != 1)
                                Text(
                                  '${Formatting.amount(item.quantity)} × ${Formatting.currency(item.price)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(Formatting.currency(item.total),
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
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
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payments', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  for (final p in doc.payments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline,
                          color: status.settled, size: 20),
                      title: Text(Formatting.date(p.paymentDate)),
                      subtitle: Text([
                        if (p.paymentMethod != null) p.paymentMethod!,
                        if (p.reference != null) p.reference!,
                      ].join(' · ')),
                      trailing: Text(
                        Formatting.currency(p.amount),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],

        // How to pay — the tenant's offline instructions.
        if (doc.isPayable && doc.paymentMethods.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to pay', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.sm),
                  for (final method in doc.paymentMethods) ...[
                    if (method.name != null)
                      Text(method.name!,
                          style: theme.textTheme.labelLarge),
                    if (method.details != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: Text(
                          method.details!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],

        // Parties.
        if (doc.invoicedTo != null || doc.payTo != null) ...[
          const SizedBox(height: Spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.invoicedTo != null)
                Expanded(
                    child: _PartyCard(title: 'Invoiced to', party: doc.invoicedTo!)),
              if (doc.invoicedTo != null && doc.payTo != null)
                const SizedBox(width: Spacing.sm),
              if (doc.payTo != null)
                Expanded(child: _PartyCard(title: 'Pay to', party: doc.payTo!)),
            ],
          ),
        ],

        if (doc.notes != null) ...[
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(doc.notes!, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.xl),
      ],
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
    final style = bold
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(Formatting.currency(value), style: style),
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
            Text(title,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: Spacing.xs),
            for (final line in lines)
              Text(line, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
