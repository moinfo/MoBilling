import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';

/// Tenant-wide payment history. A tab body inside the home shell — the shell
/// owns the masthead, so this starts with the search.
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
            Spacing.sm,
          ),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search reference or client',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref
                .read(staffServiceProvider)
                .payments(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
                  page: page,
                ),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.xl,
            ),
            itemBuilder: (context, p) => Card(
              child: ListTile(
                title: Text(
                  p.clientName ?? p.documentNumber ?? 'Payment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Row(
                    children: [
                      // Every row here is money that arrived; the chip says
                      // so, which is what lets the figures stay uncoloured.
                      const StatusChip('paid', dense: true),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: _Meta([
                          if (p.documentNumber != null && p.clientName != null)
                            p.documentNumber!,
                          Formatting.date(p.paymentDate),
                          if (p.paymentMethod != null) p.paymentMethod!,
                          if (p.reference != null) p.reference!,
                        ].join(' · ')),
                      ),
                    ],
                  ),
                ),
                trailing: Money(p.amount),
              ),
            ),
            emptyIcon: Icons.payments_outlined,
            emptyTitle: 'No payments found',
            emptyMessage: 'Try another reference or client name.',
          ),
        ),
      ],
    );
  }
}

/// A mono metadata line — invoice · date · method · reference — in the
/// eyebrow register.
class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
