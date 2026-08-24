import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../common/paged_list.dart';
import '../portal_providers.dart';
import 'dashboard_tab.dart' show InvoiceRow;

/// Paginated invoice list with a status filter. A body inside the portal
/// shell — the masthead belongs to the shell.
class InvoicesTab extends ConsumerStatefulWidget {
  const InvoicesTab({super.key});

  @override
  ConsumerState<InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<InvoicesTab> {
  final _listKey = GlobalKey<PagedListViewState>();

  /// null = all. The values mirror the visible slice of the documents.status
  /// enum — draft and cancelled never reach the portal (the controller
  /// excludes them), so they are not offered.
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('sent', 'Unpaid'),
    ('partial', 'Partial'),
    ('overdue', 'Overdue'),
    ('paid', 'Paid'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // One quiet row of chips under the masthead.
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            itemCount: _filters.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: Spacing.sm),
            itemBuilder: (context, index) {
              final (value, label) = _filters[index];
              return ChoiceChip(
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
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.xl,
            ),
            fetch: (page) => ref
                .read(portalServiceProvider)
                .documents(status: _status, page: page),
            itemBuilder: (context, invoice) =>
                Card(child: InvoiceRow(invoice: invoice)),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: _status == null
                ? 'No invoices yet'
                : 'No ${_filters.firstWhere((f) => f.$1 == _status).$2.toLowerCase()} invoices',
            emptyMessage: _status == null
                ? 'Invoices from your service provider will appear here.'
                : 'Choose another filter to see the rest of your invoices.',
          ),
        ),
      ],
    );
  }
}
