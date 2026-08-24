import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmStatusLine, FilterStrip;

/// Tenant-wide invoice list with status filter + search. A tab body inside the
/// home shell — the shell owns the masthead, so this starts with the search.
class DocumentsTab extends ConsumerStatefulWidget {
  const DocumentsTab({super.key, this.initialStatus});

  /// Pre-select a status chip — the "Unpaid Invoices" drawer entry opens
  /// this tab on `sent` (which the API expands to sent + overdue + partial).
  final String? initialStatus;

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  late String? _status = widget.initialStatus;

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

  @override
  Widget build(BuildContext context) {
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
            setState(() => _status = value);
            _listKey.currentState?.reload();
          },
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
            itemBuilder: (context, doc) => StaffInvoiceCard(
              document: doc,
              onTap: () => context.push('/documents/${doc.id}'),
            ),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: 'No invoices found',
            emptyMessage: 'Try another number, client or filter.',
          ),
        ),
      ],
    );
  }
}

/// The web's "Unpaid Invoices" shortcut: every unpaid invoice, all time.
///
/// The mobile list has never applied the web's default this-month window,
/// so "all time" is simply the list; only the status preset is needed.
class UnpaidInvoicesScreen extends StatelessWidget {
  const UnpaidInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    appBar: ShellTopBar(eyebrow: 'Billing', title: 'Unpaid invoices'),
    body: DocumentsTab(initialStatus: 'sent'),
  );
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
    this.showClient = true,
  });

  final StaffInvoiceRow document;

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
      child: ListTile(
        onTap: onTap,
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
