import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Account credit wallet: balance, ledger, add funds.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(portalCreditProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account credit')),
      body: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your credit',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalCreditProvider),
        ),
        data: (w) => RefreshIndicator(
          onRefresh: () => ref.refresh(portalCreditProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // The wallet balance is what this screen is for, so it gets the
              // same hero treatment as the balance on the portal home.
              Card(
                color: Color.alphaBlend(
                  context.statusColors.settled.withValues(alpha: 0.06),
                  Theme.of(context).colorScheme.surface,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVAILABLE CREDIT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: Type.eyebrowTracking,
                            ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Money(
                          w.balance,
                          scale: MoneyScale.display,
                          color: context.statusColors.settled,
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        'Credit is applied to invoices automatically or from '
                        'the invoice screen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton.icon(
                onPressed: () => _topup(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add funds'),
              ),
              if (w.ledger.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Text('Recent activity',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (final (i, entry) in w.ledger.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: Icon(
                            entry.isDeposit
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            size: 20,
                            color: entry.isDeposit
                                ? context.statusColors.settled
                                : context.statusColors.pending,
                          ),
                          title: Text(entry.notes ??
                              (entry.isDeposit ? 'Top-up' : 'Applied to invoice')),
                          subtitle: Text(Formatting.dateTime(entry.createdAt)),
                          trailing: Text(
                            '${entry.isDeposit ? '+' : '−'}${Formatting.amount(entry.amount)}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _topup(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add funds'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Text(error!,
                    style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error)),
                const SizedBox(height: Spacing.sm),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${Formatting.tenantCurrency} ',
                  helperText: 'Minimum 5,000 — an invoice is created; your '
                      'credit lands when it is paid.',
                  helperMaxLines: 3,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final value = double.tryParse(amount.text.trim());
                if (value == null || value < 5000) {
                  setDialogState(
                      () => error = 'Enter at least 5,000.');
                  return;
                }
                try {
                  final invoice =
                      await ref.read(portalServiceProvider).topupCredit(value);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) {
                    context.push(PortalRoutes.invoicePath(invoice.documentId));
                  }
                } on ApiException catch (e) {
                  setDialogState(
                      () => error = e.errorFor('amount') ?? e.message);
                }
              },
              child: const Text('Create invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
