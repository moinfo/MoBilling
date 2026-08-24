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

  Future<void> _payBill() async {
    final recorded = await context.push<bool>('/payments-out/new');
    if (recorded == true) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final canPay =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingMoneyPermissions.paymentsOutCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Statutory',
        title: 'Payment history',
        trailing: canPay
            ? InkActionButton(
                icon: Icons.add_card_outlined,
                tooltip: 'Pay a bill',
                onPressed: _payBill,
              )
            : null,
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) =>
            ref.read(billingMoneyServiceProvider).paymentsOut(page: page),
        itemBuilder: (context, payment) => Card(
          child: ListTile(
            title: Text(
              payment.billName ?? 'Bill payment',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: _Meta([
                Formatting.date(payment.paymentDate),
                if (payment.paymentMethod != null) payment.paymentMethod!,
                if (payment.controlNumber != null)
                  'ctrl ${payment.controlNumber}',
                if (payment.reference != null) payment.reference!,
              ].join(' · ')),
            ),
            trailing: Money(payment.amount),
          ),
        ),
        emptyIcon: Icons.history_outlined,
        emptyTitle: 'No payments out yet',
        emptyMessage: canPay
            ? 'Pay a bill from the button above and it appears here.'
            : 'Payments made against bills appear here.',
      ),
    );
  }
}

/// A mono metadata line — date · method · reference — in the eyebrow register.
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
