import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import 'billing_money_providers.dart';

/// The upcoming recurring-billing schedule.
///
/// These rows are projections, not records — the backend walks each active
/// subscription's billing cycle forward and skips dates that already have a
/// paid invoice. An "overdue" row therefore means the recurring job has not
/// produced (or nobody has paid) an invoice that should exist, which is
/// exactly what a person checking this screen wants to catch.
class NextBillsScreen extends ConsumerStatefulWidget {
  const NextBillsScreen({super.key});

  @override
  ConsumerState<NextBillsScreen> createState() => _NextBillsScreenState();
}

class _NextBillsScreenState extends ConsumerState<NextBillsScreen> {
  final Set<String> _generating = {};

  Future<void> _generate(NextBill bill) async {
    if (_generating.contains(bill.subscriptionId)) return;
    setState(() => _generating.add(bill.subscriptionId));

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(billingMoneyServiceProvider)
          .generateInvoice(bill.subscriptionId);
      ref.invalidate(nextBillsProvider);
      ref.invalidate(dashboardProvider);
      // The server's message names the invoice and the recipient.
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _generating.remove(bill.subscriptionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bills = ref.watch(nextBillsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;
    final canGenerate = ref.watch(sessionControllerProvider).session?.can(
              BillingMoneyPermissions.subscriptionsCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Next bills')),
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the schedule',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(nextBillsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const StateMessage(
              icon: Icons.event_repeat_outlined,
              title: 'Nothing scheduled',
              message: 'Active subscriptions with a repeating cycle show here.',
            );
          }

          final overdue = items.where((b) => b.isOverdue).toList();
          final upcoming = items.where((b) => !b.isOverdue).toList();
          final expected =
              items.fold<double>(0, (sum, b) => sum + b.lineTotal);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(nextBillsProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Scheduled',
                        value: '${items.length}',
                        icon: Icons.event_repeat_outlined,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: StatTile(
                        label: 'Expected value',
                        value: Formatting.amount(expected),
                      ),
                    ),
                  ],
                ),
                if (overdue.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: status.overdue),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        overdue.length == 1
                            ? '1 charge is past due'
                            : '${overdue.length} charges are past due',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: status.overdue),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  for (final bill in overdue)
                    _BillCard(
                      bill: bill,
                      canGenerate: canGenerate,
                      busy: _generating.contains(bill.subscriptionId),
                      onGenerate: () => _generate(bill),
                    ),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  Text('Upcoming', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.sm),
                  for (final bill in upcoming)
                    _BillCard(
                      bill: bill,
                      canGenerate: canGenerate,
                      busy: _generating.contains(bill.subscriptionId),
                      onGenerate: () => _generate(bill),
                    ),
                ],
                const SizedBox(height: Spacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.canGenerate,
    required this.busy,
    required this.onGenerate,
  });

  final NextBill bill;
  final bool canGenerate;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(bill.clientName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text(Formatting.currency(bill.lineTotal),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              bill.productServiceName +
                  (bill.quantity > 1 ? ' ×${bill.quantity}' : ''),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                bill.cycleLabel,
                if (bill.nextBill != null)
                  bill.isOverdue
                      ? 'due ${Formatting.date(bill.nextBill)}'
                      : Formatting.dueDescription(bill.nextBill),
                bill.hasNeverBeenBilled
                    ? 'never billed'
                    : 'last ${Formatting.date(bill.lastBilled)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: bill.isOverdue
                    ? status.overdue
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (canGenerate) ...[
              const SizedBox(height: Spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : onGenerate,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(busy ? 'Generating…' : 'Generate invoice now'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
