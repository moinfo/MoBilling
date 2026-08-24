import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart' show AuthSession;
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../clients/client_detail_screen.dart' show ContactActions;
import '../common/share_pdf.dart';
import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmField, CrmMetaLine, CrmSheet, showCrmSheet;
import 'billing_catalog_providers.dart';
import 'document_form_screen.dart' show raiseDocument;

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
        builder: (doc) => _Body(
          doc: doc,
          // The approval panel raises two of the sheet's actions to the
          // surface; it runs them through the same path so a decision made
          // there and one made in the sheet behave identically.
          onAction: (action) => _run(context, ref, doc, action),
        ),
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
      // A pending invoice with every permission can offer nine actions, which
      // is taller than a default sheet is allowed to be.
      isScrollControlled: true,
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
        case _DocumentAction.sharePdf:
          // Nothing on the server changes, so this one neither confirms nor
          // invalidates — it hands the bytes to the platform share sheet and
          // returns. A credit note goes through its own endpoint, which is
          // the same renderer behind a check that the row really is one.
          await sharePdf(
            context,
            fetch: () => doc.type == 'credit_note'
                ? service.creditNotePdf(doc.id)
                : service.documentPdf(doc.id),
            filename: '${doc.documentNumber}.pdf',
          );
          return;
        case _DocumentAction.edit:
          // The form pops with the id it saved; this screen simply refetches
          // below, since the totals and the items have both moved.
          await raiseDocument(context, document: doc);
        case _DocumentAction.creditNote:
          // Seeded from this invoice: same client, same lines, linked as the
          // parent so the credit shows against it. It lands on the new note.
          await raiseDocument(context, sourceInvoice: doc);
        case _DocumentAction.send:
          final message = await service.sendDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Emailed to the client.')),
          );
        case _DocumentAction.sendWhatsApp:
          final confirmed = await _confirm(
            context,
            'Send over WhatsApp',
            'Send ${doc.documentNumber} to '
                '${doc.clientName ?? 'the client'} on '
                '${doc.clientPhone ?? 'WhatsApp'}?',
            confirmLabel: 'Send',
          );
          if (!confirmed) return;
          final message = await service.sendDocumentWhatsApp(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Sent over WhatsApp.')),
          );
        case _DocumentAction.submitForApproval:
          final message = await service.submitForApproval(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Submitted for approval.')),
          );
        case _DocumentAction.approve:
          final confirmed = await _confirm(
            context,
            'Approve and send',
            'Approve ${doc.documentNumber}? It is re-dated to today and '
                'emailed to ${doc.clientName ?? 'the client'}.',
            confirmLabel: 'Approve',
          );
          if (!confirmed) return;
          final message = await service.approveDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Approved.')),
          );
        case _DocumentAction.reject:
          final confirmed = await _confirm(
            context,
            'Reject this document',
            'Reject ${doc.documentNumber}? It goes back to draft for '
                'whoever raised it to edit.',
            confirmLabel: 'Reject',
            destructive: true,
          );
          if (!confirmed) return;
          final message = await service.rejectDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Rejected.')),
          );
        case _DocumentAction.returnToDraft:
          final confirmed = await _confirm(
            context,
            'Return to draft',
            'Reopen ${doc.documentNumber} for editing? It stops being a '
                'live document until it is sent again.',
            confirmLabel: 'Return to draft',
          );
          if (!confirmed) return;
          final message = await service.returnToDraft(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Returned to draft.')),
          );
        case _DocumentAction.refund:
          // The sheet calls the API itself so a "more than was paid" refusal
          // lands as an error banner on the form rather than as a snackbar
          // over a form the user can no longer see.
          final message = await showCrmSheet<String>(
            context: context,
            builder: (_) => _RefundSheet(doc: doc),
          );
          if (message == null) return;
          messenger.showSnackBar(SnackBar(content: Text(message)));
        case _DocumentAction.delete:
          final confirmed = await _confirm(
            context,
            'Delete this document',
            'Delete ${doc.documentNumber} for good? This cannot be undone.',
            confirmLabel: 'Delete',
            destructive: true,
          );
          if (!confirmed) return;
          // A credit note has its own delete, which clears its items too —
          // the generic one leaves them orphaned in the table.
          final message = doc.type == 'credit_note'
              ? await service.deleteCreditNote(doc.id)
              : await service.deleteDocument(doc.id);
          messenger.showSnackBar(
            SnackBar(content: Text(message ?? 'Document deleted.')),
          );
          // The record this screen is about is gone — going back to the list
          // is the only honest next state, and refetching it would 404.
          if (context.mounted) context.pop();
          return;
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

  /// [confirmLabel] names the verb rather than saying "OK", so the button
  /// itself states what is about to happen; [destructive] paints it in the
  /// error colour.
  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body, {
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Everything staff can do to a document from a phone, with the wording and
/// the icon each one gets in the sheet.
enum _DocumentAction {
  approve('Approve and send', Icons.check_circle_outlined),
  reject('Reject', Icons.do_not_disturb_on_outlined, destructive: true),
  submitForApproval('Submit for approval', Icons.rule_outlined),
  edit('Edit document', Icons.edit_outlined),
  sharePdf('Share PDF', Icons.ios_share_outlined),
  send('Email to client', Icons.forward_to_inbox_outlined),
  sendWhatsApp('Send over WhatsApp', Icons.chat_outlined),
  convert('Convert to invoice', Icons.receipt_long_outlined),
  convertProforma('Convert to proforma', Icons.description_outlined),
  dueDate('Extend due date', Icons.event_outlined),
  issue('Issue credit note', Icons.publish_outlined),
  creditNote('Raise a credit note', Icons.receipt_outlined),
  refund('Record a refund', Icons.currency_exchange_outlined),
  returnToDraft('Return to draft', Icons.undo_outlined),
  cancel('Cancel document', Icons.block_outlined, destructive: true),
  uncancel('Restore document', Icons.restore_outlined),
  delete('Delete document', Icons.delete_outline, destructive: true);

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
    final canSend = can(BillingCatalogPermissions.documentsSend);

    return [
      // The approval decision comes first because nothing else can happen to
      // the document until it is made.
      if (can(BillingCatalogPermissions.documentsApprove) &&
          doc.isPendingApproval) ...[
        approve,
        reject,
      ],
      if (canSend && doc.isDraft) submitForApproval,
      // `update` replaces the item list wholesale, and the controller refuses
      // a cancelled document outright. A credit note has no editable form —
      // `StoreDocumentRequest` will not accept its type — so it is amended by
      // deleting the draft and raising another.
      if (canUpdate && !doc.isCancelled && doc.type != 'credit_note') edit,
      if (can(BillingCatalogPermissions.documentsDownload)) sharePdf,
      if (canSend && !doc.isCancelled) send,
      // WhatsApp needs a number to send to, and the controller refuses a
      // document that has not been issued yet.
      if (canSend &&
          !doc.isCancelled &&
          !doc.isDraft &&
          !doc.isPendingApproval &&
          (doc.clientPhone?.isNotEmpty ?? false))
        sendWhatsApp,
      if (canConvert) convert,
      if (canConvert && doc.type == 'quotation') convertProforma,
      // `updateDueDate` only accepts sent | overdue | partial.
      if (can(BillingCatalogPermissions.documentsExtendDueDate) &&
          const {'sent', 'overdue', 'partial'}.contains(doc.status))
        dueDate,
      if (canUpdate && doc.type == 'credit_note' && doc.isDraft) issue,
      // Crediting an invoice is raising a new document against it, so it is
      // gated on documents.create, as `POST /credit-notes` is.
      if (can(BillingCatalogPermissions.documentsCreate) &&
          doc.isInvoice &&
          !doc.isCancelled)
        creditNote,
      // Guarded by the payments-in permission, as the route is — a refund is
      // money going back out of the takings.
      if (can(BillingCatalogPermissions.paymentsInCreate) && doc.isRefundable)
        refund,
      if (canUpdate && doc.canReturnToDraft) returnToDraft,
      if (canUpdate) doc.isCancelled ? uncancel : cancel,
      if (can(BillingCatalogPermissions.documentsDelete) && doc.isDeletable)
        delete,
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
            // Scrolls rather than clips: the list is as long as the document's
            // state and the user's permissions make it.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                            color: action.destructive
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(action),
                      ),
                  ],
                ),
              ),
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

/// What "awaiting approval" means and, for an approver, the two buttons that
/// end it. Someone without `documents.approve` is told who has to act instead
/// of being shown a button that would only 403.
class _ApprovalPanel extends ConsumerWidget {
  const _ApprovalPanel({required this.doc, required this.onAction});

  final StaffDocument doc;
  final Future<void> Function(_DocumentAction) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = context.statusColors.attention;
    final auth = ref.watch(sessionControllerProvider).session;
    final canApprove =
        auth?.can(BillingCatalogPermissions.documentsApprove) ?? false;

    return Card(
      color: Color.alphaBlend(
        tone.withValues(alpha: 0.06),
        theme.cardTheme.color ?? scheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AWAITING APPROVAL',
              style: theme.textTheme.labelSmall?.copyWith(color: tone),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              canApprove
                  ? 'Nobody has sent this to '
                        '${doc.clientName ?? 'the client'} yet. Approving '
                        're-dates it to today and emails it; rejecting sends '
                        'it back to draft.'
                  : 'Nobody has sent this to '
                        '${doc.clientName ?? 'the client'} yet. An approver '
                        'needs to review it before it goes out.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (canApprove) ...[
              const SizedBox(height: Spacing.md),
              PrimaryButton(
                label: 'Approve and send',
                icon: Icons.check_circle_outlined,
                onPressed: () => onAction(_DocumentAction.approve),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                onPressed: () => onAction(_DocumentAction.reject),
                icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The refund form. It submits itself rather than handing a draft back, so a
/// server refusal ("more than was paid") lands on the form that caused it.
///
/// Pops with the API's message on success.
class _RefundSheet extends ConsumerStatefulWidget {
  const _RefundSheet({required this.doc});

  final StaffDocument doc;

  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  late final _amount = TextEditingController(
    text: widget.doc.paidAmount.toStringAsFixed(2),
  );
  final _reference = TextEditingController();
  final _reason = TextEditingController();

  RefundMethod _method = RefundMethod.wallet;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount to give back.');
      return;
    }
    if (amount > widget.doc.paidAmount) {
      setState(
        () => _error =
            'That is more than has been paid on this invoice '
            '(${Formatting.amount(widget.doc.paidAmount)}).',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(billingCatalogServiceProvider)
          .recordRefund(
            widget.doc.id,
            amount: amount,
            method: _method.wire,
            reference: _reference.text.trim(),
            reason: _reason.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(message ?? 'Refund recorded.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: widget.doc.documentNumber,
      title: 'Record a refund',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'A wallet refund adds reusable account credit; every other method '
          'just records money returned outside the system. Either way this '
          "invoice's paid amount drops by the same figure.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Amount',
          child: TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: Formatting.amount(widget.doc.paidAmount),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Method',
          child: DropdownButtonFormField<RefundMethod>(
            initialValue: _method,
            items: [
              for (final method in RefundMethod.values)
                DropdownMenuItem(value: method, child: Text(method.label)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _method = value ?? _method),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Reference',
          child: TextField(
            controller: _reference,
            decoration: const InputDecoration(
              hintText: 'Transaction reference, if there is one',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Reason',
          child: TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Why is this being refunded?',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: 'Record refund',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.doc, required this.onAction});

  final StaffDocument doc;

  /// Runs an action through the screen's one handler, so the panel below the
  /// hero and the actions sheet cannot drift apart.
  final Future<void> Function(_DocumentAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Reveal(child: _HeroFigure(doc: doc)),

        // A document stuck in the approval queue is invisible work: it is not
        // a draft anyone is still writing and not something the client has
        // seen. Say so, and put the decision under the words.
        if (doc.isPendingApproval) ...[
          const SizedBox(height: Spacing.md),
          _ApprovalPanel(doc: doc, onAction: onAction),
        ],

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
