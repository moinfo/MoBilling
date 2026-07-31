import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Account credit wallet: balance, ledger, add funds.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(creditProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account credit')),
      body: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your credit',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(creditProvider),
        ),
        data: (w) => RefreshIndicator(
          onRefresh: () => ref.refresh(creditProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Available credit',
                          style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        Formatting.currency(w.balance),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: Spacing.xs),
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
                    context.push(Routes.invoicePath(invoice.documentId));
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
