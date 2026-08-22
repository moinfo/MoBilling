import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'billing_money_providers.dart';

/// Money paid out against bills — the web's Statutory → Payment History.
class PaymentsOutScreen extends ConsumerStatefulWidget {
  const PaymentsOutScreen({super.key});

  @override
  ConsumerState<PaymentsOutScreen> createState() => _PaymentsOutScreenState();
}

class _PaymentsOutScreenState extends ConsumerState<PaymentsOutScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPay = ref.watch(sessionControllerProvider).session?.can(
            BillingMoneyPermissions.paymentsOutCreate) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      floatingActionButton: canPay
          ? FloatingActionButton.extended(
              onPressed: () async {
                final recorded =
                    await context.push<bool>('/payments-out/new');
                if (recorded == true) _listKey.currentState?.reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Pay a bill'),
            )
          : null,
      body: PagedListView(
        key: _listKey,
        fetch: (page) =>
            ref.read(billingMoneyServiceProvider).paymentsOut(page: page),
        itemBuilder: (context, payment) => Card(
          child: ListTile(
            leading: Icon(Icons.arrow_upward_rounded,
                color: context.statusColors.pending),
            title: Text(payment.billName ?? 'Bill payment'),
            subtitle: Text(
              [
                Formatting.date(payment.paymentDate),
                if (payment.paymentMethod != null) payment.paymentMethod!,
                if (payment.controlNumber != null)
                  'ctrl ${payment.controlNumber}',
                if (payment.reference != null) payment.reference!,
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            trailing: Money(payment.amount),
          ),
        ),
        emptyIcon: Icons.history_outlined,
        emptyTitle: 'No payments out yet',
        emptyMessage: 'Payments you make against bills appear here.',
      ),
    );
  }
}
