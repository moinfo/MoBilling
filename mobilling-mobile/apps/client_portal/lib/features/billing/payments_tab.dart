import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/share_pdf.dart';

/// Payment history with reference/invoice-number search.
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
    // Debounced so we search once per pause, not once per keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _listKey.currentState?.reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search reference or invoice number',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: ValueListenableBuilder(
                valueListenable: _search,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          _listKey.currentState?.reload();
                        },
                      ),
              ),
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref.read(portalServiceProvider).payments(
                  search: _search.text.trim().isEmpty
                      ? null
                      : _search.text.trim(),
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
        ),
      ],
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
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: status.settled),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payment.documentNumber ?? 'Payment',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      Formatting.date(payment.paymentDate),
                      if (payment.paymentMethod != null)
                        payment.paymentMethod!,
                      if (payment.reference != null) payment.reference!,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              Formatting.currency(payment.amount),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: status.settled,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.receipt_outlined, size: 20),
              tooltip: 'Share receipt',
              visualDensity: VisualDensity.compact,
              onPressed: onReceipt,
            ),
          ],
        ),
      ),
    );
  }
}
