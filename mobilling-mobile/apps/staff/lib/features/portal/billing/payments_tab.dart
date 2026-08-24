import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../common/paged_list.dart';
import '../../common/share_pdf.dart';
import '../portal_providers.dart';

/// Payment history with reference/invoice-number search.
///
/// Pushed from the More tab as a screen of its own, so it carries the
/// masthead; the search field sits on the ink beneath the title.
class PortalPaymentsTab extends ConsumerStatefulWidget {
  const PortalPaymentsTab({super.key});

  @override
  ConsumerState<PortalPaymentsTab> createState() => _PortalPaymentsTabState();
}

class _PortalPaymentsTabState extends ConsumerState<PortalPaymentsTab> {
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
    // Debounced so we search once per pause, not once per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _listKey.currentState?.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Payment history',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search reference or invoice number',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) => ref
            .read(portalServiceProvider)
            .payments(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, payment) => _PaymentCard(
          payment: payment,
          onReceipt: () => sharePdf(
            context,
            fetch: () =>
                ref.read(portalServiceProvider).paymentReceipt(payment.id),
            // Mirrors the backend's RCT-YYYYMMDD-XXXXXX receipt naming.
            filename:
                'RCT-${payment.paymentDate == null ? payment.id.substring(0, 6) : '${payment.paymentDate!.year}${payment.paymentDate!.month.toString().padLeft(2, '0')}${payment.paymentDate!.day.toString().padLeft(2, '0')}'}.pdf',
          ),
        ),
        emptyIcon: Icons.payments_outlined,
        emptyTitle: 'No payments found',
        emptyMessage: 'Payments you make will be listed here.',
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.onReceipt});

  final PaymentSummary payment;
  final VoidCallback onReceipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.sm,
          Spacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payment.documentNumber ?? 'Payment',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    [
                      Formatting.date(payment.paymentDate),
                      if (payment.paymentMethod != null) payment.paymentMethod!,
                      if (payment.reference != null) payment.reference!,
                    ].join(' · ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Money(payment.amount, color: status.settled),
            const SizedBox(width: Spacing.xs),
            IconButton(
              icon: const Icon(Icons.receipt_outlined, size: 20),
              tooltip: 'Share receipt',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.primary,
              onPressed: onReceipt,
            ),
          ],
        ),
      ),
    );
  }
}
