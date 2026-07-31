import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';

/// Tenant-wide payment history.
class PaymentsTab extends ConsumerStatefulWidget {
  const PaymentsTab({super.key});

  @override
  ConsumerState<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<PaymentsTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

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
    final status = context.statusColors;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search reference or client',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref.read(staffServiceProvider).payments(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            itemBuilder: (context, p) => Card(
              child: ListTile(
                leading:
                    Icon(Icons.arrow_downward_rounded, color: status.settled),
                title: Text(p.clientName ?? p.documentNumber ?? 'Payment'),
                subtitle: Text(
                  [
                    Formatting.date(p.paymentDate),
                    if (p.paymentMethod != null) p.paymentMethod!,
                    if (p.reference != null) p.reference!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Text(
                  Formatting.currency(p.amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: status.settled),
                ),
              ),
            ),
            emptyIcon: Icons.payments_outlined,
            emptyTitle: 'No payments found',
          ),
        ),
      ],
    );
  }
}
