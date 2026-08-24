import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';
import '../portal_routes.dart';

/// Account credit wallet: balance, ledger, add funds.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(portalCreditProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Your account', title: 'Account credit'),
      body: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your credit',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
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
              Reveal(
                child: Card(
                  color: Color.alphaBlend(
                    status.settled.withValues(alpha: 0.06),
                    theme.cardTheme.color ?? theme.colorScheme.surface,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AVAILABLE CREDIT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Money(
                            w.balance,
                            scale: MoneyScale.display,
                            color: status.settled,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'Credit is applied to invoices automatically or '
                          'from the invoice screen.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              PrimaryButton(
                icon: Icons.add,
                label: 'Add funds',
                onPressed: () => _topup(context, ref),
              ),
              if (w.ledger.isEmpty) ...[
                const SizedBox(height: Spacing.xl),
                Text(
                  'Top-ups and credit applied to invoices will be listed here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: Spacing.lg),
                const SectionHeader('Recent activity'),
                const SizedBox(height: Spacing.sm),
                Card(
                  child: Column(
                    children: [
                      for (final (i, entry) in w.ledger.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _LedgerTile(entry: entry),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _topup(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    String? error;
    var submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final theme = Theme.of(sheetContext);

          Future<void> submit() async {
            final value = double.tryParse(amount.text.trim());
            if (value == null || value < 5000) {
              setSheetState(() => error = 'Enter at least 5,000.');
              return;
            }
            setSheetState(() {
              submitting = true;
              error = null;
            });
            try {
              final invoice = await ref
                  .read(portalServiceProvider)
                  .topupCredit(value);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (context.mounted) {
                context.push(PortalRoutes.invoicePath(invoice.documentId));
              }
            } on ApiException catch (e) {
              setSheetState(() {
                submitting = false;
                error = e.errorFor('amount') ?? e.message;
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: Spacing.lg,
              right: Spacing.lg,
              top: Spacing.sm,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ACCOUNT CREDIT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Add funds',
                  style: Type.display(22, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'An invoice is created for the amount; your credit lands '
                  'when it is paid.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                if (error != null) ...[
                  ErrorBanner(message: error!),
                  const SizedBox(height: Spacing.md),
                ],
                Text('Amount', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                TextField(
                  controller: amount,
                  enabled: !submitting,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onSubmitted: (_) => submitting ? null : submit(),
                  decoration: InputDecoration(
                    hintText: '5,000 or more',
                    prefixText: '${Formatting.tenantCurrency} ',
                    helperText: 'Minimum 5,000.',
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: submitting ? 'Creating invoice…' : 'Create invoice',
                  busy: submitting,
                  onPressed: submitting ? null : submit,
                ),
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(sheetContext),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});

  final CreditEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(
        entry.notes ?? (entry.isDeposit ? 'Top-up' : 'Applied to invoice'),
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        Formatting.dateTime(entry.createdAt).toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // Sign from the wallet's perspective: top-ups in, applications out.
      trailing: Money(
        entry.isDeposit ? entry.amount : -entry.amount,
        showCode: false,
        color: entry.isDeposit ? status.settled : null,
      ),
    );
  }
}
