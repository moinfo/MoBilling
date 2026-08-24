import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart' show AuthSession;
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../clients/client_detail_screen.dart' show ContactActions;
import '../crm/crm_ui.dart' show CrmAsyncView, CrmMetaLine;
import 'billing_catalog_providers.dart';

/// Full document view for staff — works for invoices, quotations, proformas
/// and credit notes, since they are all the same table.
///
/// The screen opens on the one figure it is about (the balance while money is
/// still owed, the total once it is not), tinted toward that figure's state;
/// everything below it — items, totals, payments, credits — explains that
/// number and is set quietly so it never competes with it.
///
/// Actions offered depend on both the document's state and the user's
/// permissions: convert only appears on an open quotation/proforma, cancel
/// only on something not already cancelled, and so on.
class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(staffDocumentProvider(documentId));
    final auth = ref.watch(sessionControllerProvider).session;
    final actions = document.hasValue
        ? _DocumentAction.forDocument(document.value!, auth)
        : const <_DocumentAction>[];

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: document.valueOrNull?.documentNumber ?? 'Document',
        // One tile rather than a menu glyph: the actions here rewrite a
        // financial record, so they are worth a sheet you can read.
        trailing: actions.isEmpty
            ? null
            : InkActionButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Actions',
                onPressed: () =>
                    _openActions(context, ref, document.value!, actions),
              ),
      ),
      body: CrmAsyncView(
        value: document,
        errorTitle: 'Could not load this document',
        onRetry: () => ref.invalidate(staffDocumentProvider(documentId)),
        builder: (doc) => _Body(doc: doc),
      ),
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    StaffDocument doc,
    List<_DocumentAction> actions,
  ) async {
    final chosen = await showModalBottomSheet<_DocumentAction>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ActionsSheet(doc: doc, actions: actions),
    );
    if (chosen == null || !context.mounted) return;
    await _run(context, ref, doc, chosen);
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    StaffDocument doc,
    _DocumentAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(billingCatalogServiceProvider);

    try {
      switch (action) {
        case _DocumentAction.send:
          final message = await service.sendDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Emailed to the client.')),
          );
        case _DocumentAction.convert:
          final message = await service.convertDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Converted to an invoice.')),
          );
        case _DocumentAction.convertProforma:
          final message = await service.convertDocument(
            doc.id,
            targetType: 'proforma',
          );
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Converted to a proforma.')),
          );
        case _DocumentAction.issue:
          await service.issueCreditNote(doc.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Credit note issued.')),
          );
        case _DocumentAction.cancel:
          await service.cancelDocument(doc.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Document cancelled.')),
          );
        case _DocumentAction.uncancel:
          await service.uncancelDocument(doc.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Document restored.')),
          );
        case _DocumentAction.dueDate:
          final now = DateTime.now();
          final due = doc.dueDate;
          final picked = await showDatePicker(
            context: context,
            // An overdue invoice's due date is in the past, and a picker
            // cannot open before its own first date.
            initialDate: due == null || due.isBefore(now) ? now : due,
            firstDate: now,
            lastDate: now.add(const Duration(days: 365)),
          );
          if (picked == null) return;
          await service.extendDueDate(doc.id, picked);
          messenger.showSnackBar(
            const SnackBar(content: Text('Due date updated.')),
          );
      }
      ref.invalidate(staffDocumentProvider(documentId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Everything staff can do to a document from a phone, with the wording and
/// the icon each one gets in the sheet.
enum _DocumentAction {
  send('Email to client', Icons.forward_to_inbox_outlined),
  convert('Convert to invoice', Icons.receipt_long_outlined),
  convertProforma('Convert to proforma', Icons.description_outlined),
  dueDate('Extend due date', Icons.event_outlined),
  issue('Issue credit note', Icons.publish_outlined),
  cancel('Cancel document', Icons.block_outlined, destructive: true),
  uncancel('Restore document', Icons.restore_outlined);

  const _DocumentAction(this.label, this.icon, {this.destructive = false});

  final String label;
  final IconData icon;

  /// Throws work away, so it is set in the error tone and sits last.
  final bool destructive;

  /// Which actions this document, in this state, offers this user.
  static List<_DocumentAction> forDocument(
    StaffDocument doc,
    AuthSession? auth,
  ) {
    bool can(String permission) => auth?.can(permission) ?? false;

    final canConvert =
        can(BillingCatalogPermissions.documentsConvert) && doc.isConvertible;
    final canUpdate = can(BillingCatalogPermissions.documentsUpdate);

    return [
      if (can(BillingCatalogPermissions.documentsSend) && !doc.isCancelled)
        send,
      if (canConvert) convert,
      if (canConvert && doc.type == 'quotation') convertProforma,
      // `updateDueDate` only accepts sent | overdue | partial.
      if (can(BillingCatalogPermissions.documentsExtendDueDate) &&
          const {'sent', 'overdue', 'partial'}.contains(doc.status))
        dueDate,
      if (canUpdate && doc.type == 'credit_note' && doc.isDraft) issue,
      if (canUpdate) doc.isCancelled ? uncancel : cancel,
    ];
  }
}

/// The actions sheet: the document named in the eyebrow, the actions as rows
/// big enough for a thumb.
class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({required this.doc, required this.actions});

  final StaffDocument doc;
  final List<_DocumentAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrmMetaLine(doc.documentNumber),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Document actions',
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
            for (final action in actions)
              ListTile(
                leading: Icon(
                  action.icon,
                  size: 20,
                  color: action.destructive
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
                title: Text(
                  action.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: action.destructive ? scheme.error : scheme.onSurface,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
  }
}

/// The pay button, gated on the same permission as the menu's shortcut.
///
/// Hands the invoice to the record-payment flow so it opens on the form
/// instead of asking staff to find, in a list, the invoice they are looking
/// at. Refreshes this document on the way back, since the balance has moved.
class _RecordPaymentAction extends ConsumerWidget {
  const _RecordPaymentAction({required this.doc});

  final StaffDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    if (!(auth?.can('payments_in.create') ?? false)) {
      return const SizedBox.shrink();
    }

    return PrimaryButton(
      label: 'Record payment',
      icon: Icons.add_card_outlined,
      onPressed: () async {
        final recorded = await context.push<bool>(
          '/payments/record',
          extra: UnpaidInvoice(
            id: doc.id,
            documentNumber: doc.documentNumber,
            status: doc.status,
            total: doc.total,
            paidAmount: doc.paidAmount,
            balanceDue: doc.balanceDue,
            clientId: doc.clientId,
            clientName: doc.clientName,
            date: doc.date,
            dueDate: doc.dueDate,
          ),
        );
        if (recorded ?? false) ref.invalidate(staffDocumentProvider(doc.id));
      },
    );
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
        Reveal(child: _HeroFigure(doc: doc)),

        // Taking the money is what this screen is for while anything is
        // owed, so it is a button under the figure rather than an entry in
        // the actions sheet — the rest of that sheet rewrites the record;
        // this is the one thing staff came to do.
        if (doc.isPayable) ...[
          const SizedBox(height: Spacing.md),
          _RecordPaymentAction(doc: doc),
        ],

        if (doc.clientName != null) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Client'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.clientName!, style: theme.textTheme.titleSmall),
                  // An address and a number are values, not labels — the
                  // eyebrow's upper case would misrepresent both.
                  for (final line in [
                    if (doc.clientEmail != null) doc.clientEmail!,
                    if (doc.clientPhone != null) doc.clientPhone!,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (doc.clientEmail != null || doc.clientPhone != null) ...[
                    const SizedBox(height: Spacing.md),
                    ContactActions(
                      phone: doc.clientPhone,
                      email: doc.clientEmail,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: Spacing.lg),
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
                _TotalRow('Total', doc.total, bold: true),
                if (doc.paidAmount > 0) ...[
                  _TotalRow('Paid', -doc.paidAmount),
                  _TotalRow('Balance due', doc.balanceDue, bold: true),
                ],
              ],
            ),
          ),
        ),

        if (doc.payments.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Payments'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, payment) in doc.payments.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(
                      Formatting.date(payment.paymentDate),
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: CrmMetaLine(
                      [
                        if (payment.paymentMethod != null)
                          payment.paymentMethod!,
                        if (payment.reference != null) payment.reference!,
                      ].join(' · '),
                    ),
                    // Money that arrived, in the colour this app keeps for
                    // settled.
                    trailing: Money(payment.amount, color: status.settled),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (doc.refunds.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Refunds'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, refund) in doc.refunds.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(
                      Formatting.date(refund.createdAt),
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: refund.method == null
                        ? null
                        : CrmMetaLine(refund.method!),
                    trailing: Money(-refund.amount),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (doc.linkedCreditNotes.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Credit notes'),
          const SizedBox(height: Spacing.sm),
          Card(
            child: Column(
              children: [
                for (final (i, note) in doc.linkedCreditNotes.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(
                      note.documentNumber,
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(note.status, dense: true),
                      ),
                    ),
                    trailing: Money(note.total),
                  ),
                ],
              ],
            ),
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
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

/// The one figure this screen is about, on a card tinted 6% toward that
/// figure's state — with the status chip and issue date above it, and the
/// chasing history below, which is the part only staff get to see.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.doc});

  final StaffDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final late = doc.isPayable && (Formatting.daysUntil(doc.dueDate) ?? 1) < 0;
    final tone = doc.isPayable
        ? (late ? status.overdue : status.attention)
        : status.settled;

    final chased = [
      if (doc.reminderCount > 0)
        '${doc.reminderCount} reminder${doc.reminderCount == 1 ? '' : 's'} sent',
      if (doc.overdueStage != null) 'stage ${doc.overdueStage}',
    ].join(' · ');

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
                const SizedBox(width: Spacing.sm),
                // The title is only a reference number, and INV-1042 and
                // CN-0007 look alike at a glance — so the kind is named here.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: CrmMetaLine(
                      '${StatusColors.label(doc.type)} · '
                      '${Formatting.date(doc.date)}',
                    ),
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
            if (chased.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              CrmMetaLine(chased, color: status.attention),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final StaffDocumentItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.description, style: theme.textTheme.bodyMedium),
              if (item.quantity != 1 ||
                  (item.serviceFrom != null && item.serviceTo != null)) ...[
                const SizedBox(height: 2),
                CrmMetaLine(
                  [
                    if (item.quantity != 1)
                      '${Formatting.amount(item.quantity)}'
                          '${item.unit == null ? '' : ' ${item.unit}'}'
                          ' × ${Formatting.amount(item.price)}',
                    if (item.serviceFrom != null && item.serviceTo != null)
                      '${Formatting.date(item.serviceFrom)} – '
                          '${Formatting.date(item.serviceTo)}',
                  ].join(' · '),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Money(item.total, scale: MoneyScale.dense, showCode: false),
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

    // Only the decisive lines carry the currency code. Repeating it down a
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
