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
    final status = context.statusColors;
    final canGenerate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingMoneyPermissions.subscriptionsCreate) ??
        false;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Next bills'),
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the schedule',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
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
          final expected = items.fold<double>(0, (sum, b) => sum + b.lineTotal);
          final pastDue = overdue.fold<double>(
            0,
            (sum, b) => sum + b.lineTotal,
          );

          return RefreshIndicator(
            onRefresh: () => ref.refresh(nextBillsProvider.future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                // The one figure this screen is about: what the schedule is
                // worth when every charge lands.
                Reveal(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _Eyebrow('Expected value'),
                          const SizedBox(height: Spacing.sm),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Money(expected, scale: MoneyScale.display),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Reveal(
                  delay: const Duration(milliseconds: 80),
                  child: StatRail(
                    items: [
                      StatRailItem(
                        label: 'Scheduled',
                        value: Formatting.integer(items.length),
                      ),
                      StatRailItem(
                        label: 'Past due',
                        value: Formatting.integer(overdue.length),
                        emphasis: overdue.isNotEmpty ? status.overdue : null,
                      ),
                      StatRailItem(
                        label: 'Owed',
                        value: Formatting.compact(pastDue),
                        emphasis: pastDue > 0 ? status.overdue : null,
                      ),
                    ],
                  ),
                ),
                if (overdue.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  SectionHeader(
                    overdue.length == 1
                        ? '1 charge past due'
                        : '${overdue.length} charges past due',
                  ),
                  const SizedBox(height: Spacing.sm),
                  _BillList(
                    bills: overdue,
                    canGenerate: canGenerate,
                    generating: _generating,
                    onGenerate: _generate,
                  ),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  const SectionHeader('Upcoming'),
                  const SizedBox(height: Spacing.sm),
                  _BillList(
                    bills: upcoming,
                    canGenerate: canGenerate,
                    generating: _generating,
                    onGenerate: _generate,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One card of bills, a hairline between each.
class _BillList extends StatelessWidget {
  const _BillList({
    required this.bills,
    required this.canGenerate,
    required this.generating,
    required this.onGenerate,
  });

  final List<NextBill> bills;
  final bool canGenerate;
  final Set<String> generating;
  final ValueChanged<NextBill> onGenerate;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        for (final (i, bill) in bills.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _BillTile(
            bill: bill,
            canGenerate: canGenerate,
            busy: generating.contains(bill.subscriptionId),
            onGenerate: () => onGenerate(bill),
          ),
        ],
      ],
    ),
  );
}

class _BillTile extends StatelessWidget {
  const _BillTile({
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
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(
            bill.clientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                bill.productServiceName +
                    (bill.quantity > 1 ? ' ×${bill.quantity}' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  // Past due is the news; otherwise the cycle names the row.
                  StatusChip(
                    bill.isOverdue ? 'overdue' : bill.cycleLabel,
                    dense: true,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    child: _Meta(
                      [
                        if (bill.isOverdue) bill.cycleLabel,
                        if (bill.nextBill != null)
                          bill.isOverdue
                              ? 'due ${Formatting.date(bill.nextBill)}'
                              : Formatting.dueDescription(bill.nextBill),
                        bill.hasNeverBeenBilled
                            ? 'never billed'
                            : 'last ${Formatting.date(bill.lastBilled)}',
                      ].join(' · '),
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: Money(bill.lineTotal),
        ),
        if (canGenerate)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.sm,
              0,
              Spacing.sm,
              Spacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onGenerate,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long_outlined, size: 16),
                label: Text(busy ? 'Generating…' : 'Generate invoice now'),
              ),
            ),
          ),
      ],
    );
  }
}

/// The eyebrow that names a figure: Plex Mono, upper-case, quiet.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A mono metadata line — cycle · due · last billed — in the eyebrow register.
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
