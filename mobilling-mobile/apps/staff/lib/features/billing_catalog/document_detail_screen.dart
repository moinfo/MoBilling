import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart' show AuthSession;
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'billing_catalog_providers.dart';

/// Full document view for staff — works for invoices, quotations, proformas
/// and credit notes, since they are all the same table.
///
/// Actions offered depend on both the document's state and the user's
/// permissions: convert only appears on an open quotation/proforma, cancel only
/// on something not already cancelled, and so on.
class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(staffDocumentProvider(documentId));
    final auth = ref.watch(sessionControllerProvider).session;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.valueOrNull?.documentNumber ?? 'Document'),
        actions: [
          if (document.hasValue)
            _ActionsMenu(
              document: document.value!,
              auth: auth,
              onDone: () => ref.invalidate(staffDocumentProvider(documentId)),
            ),
        ],
      ),
      body: CrmAsyncView(
        value: document,
        errorTitle: 'Could not load this document',
        onRetry: () => ref.invalidate(staffDocumentProvider(documentId)),
        builder: (doc) => _Body(doc: doc),
      ),
    );
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({
    required this.document,
    required this.auth,
    required this.onDone,
  });

  final StaffDocument document;
  final AuthSession? auth;
  final VoidCallback onDone;

  bool _can(String permission) => auth?.can(permission) ?? false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSend = _can(BillingCatalogPermissions.documentsSend);
    final canConvert = _can(BillingCatalogPermissions.documentsConvert);
    final canUpdate = _can(BillingCatalogPermissions.documentsUpdate);
    final canExtend = _can(BillingCatalogPermissions.documentsExtendDueDate);

    return PopupMenuButton<String>(
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        if (canSend && !document.isCancelled)
          const PopupMenuItem(value: 'send', child: Text('Email to client')),
        if (canConvert && document.isConvertible)
          const PopupMenuItem(
              value: 'convert', child: Text('Convert to invoice')),
        if (canConvert && document.isConvertible && document.type == 'quotation')
          const PopupMenuItem(
              value: 'convert-proforma', child: Text('Convert to proforma')),
        // `updateDueDate` only accepts sent | overdue | partial.
        if (canExtend &&
            const {'sent', 'overdue', 'partial'}.contains(document.status))
          const PopupMenuItem(
              value: 'due-date', child: Text('Extend due date')),
        if (canUpdate && document.type == 'credit_note' && document.isDraft)
          const PopupMenuItem(
              value: 'issue', child: Text('Issue credit note')),
        if (canUpdate)
          document.isCancelled
              ? const PopupMenuItem(
                  value: 'uncancel', child: Text('Restore'))
              : const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
      ],
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(billingCatalogServiceProvider);

    try {
      switch (action) {
        case 'send':
          final message = await service.sendDocument(document.id);
          messenger.showSnackBar(
              SnackBar(content: Text(message ?? 'Emailed to the client.')));
        case 'convert':
          final message = await service.convertDocument(document.id);
          messenger.showSnackBar(
              SnackBar(content: Text(message ?? 'Converted to an invoice.')));
        case 'convert-proforma':
          final message = await service.convertDocument(document.id,
              targetType: 'proforma');
          messenger.showSnackBar(
              SnackBar(content: Text(message ?? 'Converted to a proforma.')));
        case 'issue':
          await service.issueCreditNote(document.id);
          messenger.showSnackBar(
              const SnackBar(content: Text('Credit note issued.')));
        case 'cancel':
          await service.cancelDocument(document.id);
          messenger.showSnackBar(
              const SnackBar(content: Text('Document cancelled.')));
        case 'uncancel':
          await service.uncancelDocument(document.id);
          messenger
              .showSnackBar(const SnackBar(content: Text('Document restored.')));
        case 'due-date':
          final picked = await showDatePicker(
            context: context,
            initialDate: document.dueDate ?? DateTime.now(),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked == null) return;
          await service.extendDueDate(document.id, picked);
          messenger
              .showSnackBar(const SnackBar(content: Text('Due date updated.')));
      }
      onDone();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.doc});

  final StaffDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
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
                    Text(Formatting.date(doc.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                Text(doc.isPayable ? 'Balance due' : 'Total',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Money(
                    doc.isPayable ? doc.balanceDue : doc.total,
                    scale: MoneyScale.display,
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
                // Staff-only context: how hard this invoice has been chased.
                if (doc.reminderCount > 0 || doc.overdueStage != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    [
                      if (doc.reminderCount > 0)
                        '${doc.reminderCount} reminder${doc.reminderCount == 1 ? '' : 's'} sent',
                      if (doc.overdueStage != null)
                        'stage ${doc.overdueStage}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: status.attention),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),

        // Client, with one-tap contact.
        if (doc.clientName != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Client', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.xs),
                  Text(doc.clientName!, style: theme.textTheme.bodyMedium),
                  if (doc.clientEmail != null)
                    Text(doc.clientEmail!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      if (doc.clientPhone != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: const Text('Call'),
                            onPressed: () => launchUrl(
                                Uri(scheme: 'tel', path: doc.clientPhone)),
                          ),
                        ),
                      if (doc.clientPhone != null && doc.clientEmail != null)
                        const SizedBox(width: Spacing.sm),
                      if (doc.clientEmail != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.mail_outline, size: 18),
                            label: const Text('Email'),
                            onPressed: () => launchUrl(
                                Uri(scheme: 'mailto', path: doc.clientEmail)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Spacing.md),

        // Items and totals.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Items', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                for (final item in doc.items)
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
                              if (item.quantity != 1)
                                Text(
                                  '${Formatting.amount(item.quantity)}${item.unit == null ? '' : ' ${item.unit}'} × ${Formatting.currency(item.price)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant),
                                ),
                              if (item.serviceFrom != null &&
                                  item.serviceTo != null)
                                Text(
                                  '${Formatting.date(item.serviceFrom)} – ${Formatting.date(item.serviceTo)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Money(item.total),
                      ],
                    ),
                  ),
                const Divider(height: Spacing.lg),
                _TotalRow('Subtotal', doc.subtotal),
                if (doc.discountAmount > 0)
                  _TotalRow('Discount', -doc.discountAmount),
                if (doc.taxAmount > 0) _TotalRow('Tax', doc.taxAmount),
                _TotalRow('Total', doc.total, bold: true),
                if (doc.paidAmount > 0) _TotalRow('Paid', -doc.paidAmount),
                if (doc.paidAmount > 0)
                  _TotalRow('Balance due', doc.balanceDue, bold: true),
              ],
            ),
          ),
        ),

        if (doc.payments.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payments', style: theme.textTheme.titleSmall),
                  for (final payment in doc.payments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline,
                          size: 20, color: status.settled),
                      title: Text(Formatting.date(payment.paymentDate)),
                      subtitle: Text([
                        if (payment.paymentMethod != null)
                          payment.paymentMethod!,
                        if (payment.reference != null) payment.reference!,
                      ].join(' · ')),
                      trailing: Money(payment.amount),
                    ),
                ],
              ),
            ),
          ),
        ],

        if (doc.refunds.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Refunds', style: theme.textTheme.titleSmall),
                  for (final refund in doc.refunds)
                    CrmDetailRow(
                      Formatting.date(refund.createdAt),
                      '${Formatting.currency(refund.amount)}'
                      '${refund.method == null ? '' : ' · ${refund.method}'}',
                    ),
                ],
              ),
            ),
          ),
        ],

        if (doc.linkedCreditNotes.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Credit notes', style: theme.textTheme.titleSmall),
                  for (final note in doc.linkedCreditNotes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(note.documentNumber),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Money(note.total),
                          const SizedBox(width: Spacing.sm),
                          StatusChip(note.status, dense: true),
                        ],
                      ),
                    ),
                ],
              ),
            ),
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
          Money(value),
        ],
      ),
    );
  }
}
