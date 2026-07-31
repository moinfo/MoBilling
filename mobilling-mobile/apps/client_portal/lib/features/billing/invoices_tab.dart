import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'dashboard_tab.dart' show InvoiceRow;

/// Paginated invoice list with a status filter.
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
            fetch: (page) => ref
                .read(portalServiceProvider)
                .documents(status: _status, page: page),
            itemBuilder: (context, invoice) => InvoiceRow(invoice: invoice),
            emptyIcon: Icons.receipt_long_outlined,
            emptyTitle: _status == null
                ? 'No invoices yet'
                : 'No ${_filters.firstWhere((f) => f.$1 == _status).$2.toLowerCase()} invoices',
            emptyMessage:
                'Invoices from your service provider will appear here.',
          ),
        ),
      ],
    );
  }
}
