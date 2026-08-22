import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';

/// Tenant-wide invoice list with status filter + search.
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
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, 0),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search number or client',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm),
            itemCount: _filters.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Spacing.sm),
            itemBuilder: (context, index) {
              final (value, label) = _filters[index];
              return FilterChip(
                label: Text(label),
                selected: _status == value,
                showCheckmark: false,
                onSelected: (_) {
                  setState(() => _status = value);
                  _listKey.currentState?.reload();
                },
              );
            },
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref.read(staffServiceProvider).documents(
                  status: _status,
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            itemBuilder: (context, doc) => InkWell(
              borderRadius: Radii.card,
              onTap: () => context.push('/documents/${doc.id}'),
              child: StaffInvoiceCard(document: doc),
            ),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: 'No invoices found',
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Unpaid invoices')),
        body: const DocumentsTab(initialStatus: 'sent'),
      );
}

/// Invoice row shared by the invoices tab and the client detail screen.
class StaffInvoiceCard extends StatelessWidget {
  const StaffInvoiceCard({super.key, required this.document});

  final StaffInvoiceRow document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(document.clientName ?? document.documentNumber,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      document.documentNumber,
                      if (document.date != null)
                        Formatting.date(document.date),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (document.description != null) ...[
                    const SizedBox(height: 2),
                    Text(document.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Money(document.total),
                const SizedBox(height: Spacing.xs),
                StatusChip(document.status, dense: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
