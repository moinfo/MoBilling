import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_catalog/billing_catalog_providers.dart';
import '../billing_catalog/document_form_screen.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmSheet, CrmStatusLine, FilterStrip, showCrmSheet;

/// Tenant-wide invoice list with status filter + search. A tab body inside the
/// home shell — the shell owns the masthead, so this starts with the search.
class DocumentsTab extends ConsumerStatefulWidget {
  const DocumentsTab({super.key, this.initialStatus, this.showCreate = true});

  /// Pre-select a status chip — the "Unpaid Invoices" drawer entry opens
  /// this tab on `sent` (which the API expands to sent + overdue + partial).
  final String? initialStatus;

  /// Off where the enclosing screen owns a masthead and puts the `+` there
  /// instead, so raising an invoice is offered once rather than twice.
  final bool showCreate;

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  late String? _status = widget.initialStatus;

  /// Chasing mode. Off, the list behaves as it always has — a row opens the
  /// document. On, rows tick instead, and the button at the foot sends.
  bool _selecting = false;
  final _selected = <String>{};

  // 'sent' expands server-side to sent+overdue+partial ("unpaid").
  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('sent', 'Unpaid'),
    ('overdue', 'Overdue'),
    ('paid', 'Paid'),
    ('draft', 'Draft'),
  ];

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

  /// `remindUnpaid` silently drops anything that is not an unpaid invoice, so
  /// a row it would drop never becomes tickable — better no checkbox than a
  /// tick that turns out to have meant nothing.
  bool _isChaseable(StaffInvoiceRow row) =>
      (row.type == null || row.type == 'invoice') &&
      const {'sent', 'overdue', 'partial'}.contains(row.status);

  /// Chasing only makes sense on a list of unpaid invoices, so the entry
  /// appears on those two filters and nowhere else — and only for the
  /// permission the route itself requires.
  ///
  /// Read once per build and passed down, rather than watched again from
  /// inside the list's row builder, which runs after this build has returned.
  bool get _remindable {
    final auth = ref.watch(sessionControllerProvider).session;
    return (auth?.can(BillingCatalogPermissions.documentsSend) ?? false) &&
        (_status == 'sent' || _status == 'overdue');
  }

  /// Raising an invoice is gated on the same permission `POST /documents`
  /// requires, and lands on the new document so sending it is the next tap.
  bool get _creatable {
    if (!widget.showCreate) return false;
    final auth = ref.watch(sessionControllerProvider).session;
    return auth?.can(BillingCatalogPermissions.documentsCreate) ?? false;
  }

  void _toggle(StaffInvoiceRow row) => setState(() {
    if (!_selected.remove(row.id)) _selected.add(row.id);
    if (_selected.isEmpty) _selecting = false;
  });

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _remind() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final message = await showCrmSheet<String>(
      context: context,
      builder: (_) => _RemindSheet(
        documentIds: ids,
        label: ids.length == 1
            ? 'this invoice'
            : '${Formatting.integer(ids.length)} invoices',
      ),
    );
    if (message == null || !mounted) return;

    _endSelecting();
    messenger.showSnackBar(SnackBar(content: Text(message)));
    // A reminder bumps reminder_count and can move an invoice's stage, so the
    // rows the user is looking at are now stale.
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final remindable = _remindable;
    final creatable = _creatable;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            0,
          ),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search number or client',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),
        FilterStrip(
          options: _filters,
          selected: _status,
          onSelect: (value) {
            setState(() {
              _status = value;
              _selecting = false;
              _selected.clear();
            });
            _listKey.currentState?.reload();
          },
        ),
        if (remindable || creatable)
          _ListActionStrip(
            selecting: _selecting,
            count: _selected.length,
            onCreate: creatable
                ? () => raiseDocument(
                    context,
                    onSaved: () => _listKey.currentState?.reload(),
                  )
                : null,
            onStart: remindable
                ? () => setState(() => _selecting = true)
                : null,
            onCancel: _endSelecting,
          ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref
                .read(staffServiceProvider)
                .documents(
                  status: _status,
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.xs,
              Spacing.md,
              Spacing.xl,
            ),
            itemBuilder: (context, doc) {
              final tickable = remindable && _isChaseable(doc);
              return StaffInvoiceCard(
                document: doc,
                selected: _selecting && tickable
                    ? _selected.contains(doc.id)
                    : null,
                onTap: _selecting && tickable
                    ? () => _toggle(doc)
                    : () => context.push('/documents/${doc.id}'),
                // Press and hold to start chasing, the way a phone starts any
                // multi-select — so the strip above is a hint, not the only way.
                onLongPress: tickable && !_selecting
                    ? () {
                        setState(() => _selecting = true);
                        _toggle(doc);
                      }
                    : null,
              );
            },
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: 'No invoices found',
            emptyMessage: 'Try another number, client or filter.',
          ),
        ),
        if (_selecting && _selected.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.sm,
                Spacing.md,
                Spacing.md,
              ),
              child: PrimaryButton(
                label: _selected.length == 1
                    ? 'Send a reminder'
                    : 'Remind ${Formatting.integer(_selected.length)} invoices',
                icon: Icons.notifications_active_outlined,
                onPressed: _remind,
              ),
            ),
          ),
      ],
    );
  }
}

/// The line between the filters and the list: what can be done to the list as
/// a whole. Raising a new document sits on the left, chasing the existing ones
/// on the right — and once ticking has started the whole line becomes the
/// running count with a way out.
class _ListActionStrip extends StatelessWidget {
  const _ListActionStrip({
    required this.selecting,
    required this.count,
    required this.onCreate,
    required this.onStart,
    required this.onCancel,
  });

  final bool selecting;
  final int count;

  /// Null without `documents.create`.
  final VoidCallback? onCreate;

  /// Null without `documents.send`, or on a filter where chasing is meaningless.
  final VoidCallback? onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!selecting) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Row(
          children: [
            if (onCreate != null)
              TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New invoice'),
              ),
            const Spacer(),
            if (onStart != null)
              TextButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Remind unpaid'),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.sm, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 0
                  ? 'PICK THE INVOICES TO CHASE'
                  : '${Formatting.integer(count)} SELECTED',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

/// Which channel to chase on, then the chase itself.
///
/// It submits rather than handing a choice back, so a batch the server refuses
/// outright (every send failed → 422) shows on the form that caused it. Pops
/// with the API's summary line — "reminder sent to 3 client(s) covering 5
/// invoice(s)" — which counts clients, not invoices, because the server bundles
/// one client's invoices into a single message.
class _RemindSheet extends ConsumerStatefulWidget {
  const _RemindSheet({required this.documentIds, required this.label});

  final List<String> documentIds;

  /// What is being chased, for the sentence above the choices.
  final String label;

  @override
  ConsumerState<_RemindSheet> createState() => _RemindSheetState();
}

class _RemindSheetState extends ConsumerState<_RemindSheet> {
  RemindChannel _channel = RemindChannel.email;
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(billingCatalogServiceProvider)
          .remindUnpaid(
            documentIds: widget.documentIds,
            channel: _channel.wire,
          );
      if (!mounted) return;
      Navigator.of(context).pop(result.message ?? 'Reminders sent.');
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
      eyebrow: 'Unpaid invoices',
      title: 'Send a reminder',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'Chasing ${widget.label}. A client with several unpaid invoices '
          'gets one message covering all of them.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        RadioGroup<RemindChannel>(
          groupValue: _channel,
          onChanged: (value) {
            // Changing the channel mid-send would not reach the request that
            // is already out, so the choice simply freezes while it is.
            if (_busy) return;
            setState(() => _channel = value ?? _channel);
          },
          child: Column(
            children: [
              for (final channel in RemindChannel.values)
                RadioListTile<RemindChannel>(
                  value: channel,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(channel.label, style: theme.textTheme.bodyLarge),
                ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        PrimaryButton(
          label: 'Send reminder',
          busy: _busy,
          onPressed: _busy ? null : _send,
        ),
      ],
    );
  }
}

/// The web's "Unpaid Invoices" shortcut: every unpaid invoice, all time.
///
/// The mobile list has never applied the web's default this-month window,
/// so "all time" is simply the list; only the status preset is needed.
///
/// This one has a masthead of its own, so raising an invoice is a `+` on it
/// rather than a button in the body — which is why the tab below is told not
/// to offer its own.
class UnpaidInvoicesScreen extends ConsumerWidget {
  const UnpaidInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(sessionControllerProvider).session;
    final creatable =
        auth?.can(BillingCatalogPermissions.documentsCreate) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Unpaid invoices',
        trailing: creatable
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New invoice',
                onPressed: () => raiseDocument(context),
              )
            : null,
      ),
      body: const DocumentsTab(initialStatus: 'sent', showCreate: false),
    );
  }
}

/// Invoice row shared by the invoices tab, the by-type lists and the client
/// detail screen.
///
/// The status moves down beside the reference so the trailing column carries
/// amounts only — which is what lets a screenful of these read as one column
/// of money rather than as a grid of unrelated pairs.
class StaffInvoiceCard extends StatelessWidget {
  const StaffInvoiceCard({
    super.key,
    required this.document,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.showClient = true,
  });

  final StaffInvoiceRow document;

  /// Non-null puts the row in ticking mode: a checkbox leads, the card takes
  /// a faint tint when ticked, and [onTap] toggles instead of opening. Null —
  /// the default everywhere else — leaves the row exactly as it was.
  final bool? selected;

  /// Press and hold, used to start a multi-select from a row.
  final VoidCallback? onLongPress;

  /// Off on a client's own screen, where every row would otherwise repeat
  /// the name in the masthead. The reference then leads instead.
  final bool showClient;

  /// Optional so the older call sites that wrap this in their own [InkWell]
  /// keep working; pass it and the row gets the ripple itself.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Date and description are both values rather than labels, so they share
    // the second line in the body face instead of joining the mono eyebrow.
    final detail = [
      if (document.date != null) Formatting.date(document.date),
      if (document.description != null) document.description!,
    ].join(' · ');

    return Card(
      color: selected ?? false
          ? Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.06),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            )
          : null,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selected == null
            ? null
            : Checkbox(
                value: selected,
                onChanged: onTap == null ? null : (_) => onTap!(),
              ),
        title: Text(
          showClient
              ? (document.clientName ?? document.documentNumber)
              : document.documentNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Spacing.xs),
            // The reference alone on the chip's line: a phone is 390pt wide,
            // and a chip plus a reference plus a date is one thing too many
            // — the date would be the part that got ellipsed away. With the
            // client hidden the reference has moved up to the title, so the
            // chip keeps the line to itself.
            CrmStatusLine(
              status: document.status,
              meta: showClient ? document.documentNumber : '',
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        trailing: Money(document.total),
      ),
    );
  }
}
