import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/paged_list.dart';
import 'comms_providers.dart';
import 'comms_ui.dart';

final AutoDisposeFutureProvider<SmsBalance> smsBalanceProvider =
    FutureProvider.autoDispose<SmsBalance>(
  (ref) => ref.watch(commsServiceProvider).smsBalance(),
);

final AutoDisposeFutureProvider<List<SmsPackageOption>> smsPackagesProvider =
    FutureProvider.autoDispose<List<SmsPackageOption>>(
  (ref) => ref.watch(commsServiceProvider).smsPackages(),
);

/// SMS credits: balance, buying more, and the purchase log.
///
/// Payment is a Pesapal-hosted page, so buying necessarily leaves the app. The
/// purchase row stays payable until Pesapal confirms, and the status poll on
/// each row is how a returning user finds out whether it went through — there
/// is no push callback into the app.
class SmsScreen extends ConsumerWidget {
  const SmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SMS'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Buy credits'),
              Tab(text: 'Purchases'),
            ],
          ),
        ),
        body: Column(
          children: [
            const _BalanceCard(),
            const Expanded(
              child: TabBarView(
                children: [_BuyCreditsView(), _PurchaseHistoryView()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balance = ref.watch(smsBalanceProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              Icon(Icons.sms_outlined,
                  size: 28, color: theme.colorScheme.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current balance',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: Spacing.xs),
                    balance.when(
                      loading: () => const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (error, _) => Text(
                        commsErrorText(error),
                        style: theme.textTheme.bodySmall,
                      ),
                      data: (b) => Text(
                        b.isConfigured
                            ? '${b.balance} SMS'
                            : 'Not configured',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(smsBalanceProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyCreditsView extends ConsumerStatefulWidget {
  const _BuyCreditsView();

  @override
  ConsumerState<_BuyCreditsView> createState() => _BuyCreditsViewState();
}

class _BuyCreditsViewState extends ConsumerState<_BuyCreditsView> {
  final _quantity = TextEditingController(text: '100');
  bool _busy = false;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  int get _parsedQuantity => int.tryParse(_quantity.text.trim()) ?? 0;

  /// Mirrors `SmsPackage::forQuantity` — the widest matching tier wins, which
  /// for non-overlapping tiers is simply the one containing the quantity.
  SmsPackageOption? _tierFor(List<SmsPackageOption> packages, int quantity) {
    SmsPackageOption? match;
    for (final p in packages.where((p) => p.covers(quantity))) {
      if (match == null || p.minQuantity > match.minQuantity) match = p;
    }
    return match;
  }

  Future<void> _requestActivation() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final message = await ref.read(commsServiceProvider).requestSmsActivation();
      showCommsMessage(messenger, message);
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout() async {
    final messenger = ScaffoldMessenger.of(context);
    final quantity = _parsedQuantity;

    if (quantity < 100) {
      showCommsMessage(messenger, 'Buy at least 100 SMS.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final checkout =
          await ref.read(commsServiceProvider).smsCheckout(quantity: quantity);
      ref.read(smsPurchasesRefreshProvider.notifier).state++;

      final url = checkout.redirectUrl;
      if (url == null) {
        showCommsMessage(
          messenger,
          'Purchase created, but the payment page is not ready yet. '
          'Retry it from Purchases.',
          isError: true,
        );
        return;
      }
      await _openPayment(messenger, url);
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = ref.watch(smsBalanceProvider);
    final packages = ref.watch(smsPackagesProvider);
    final canBuy = ref.watch(commsPermissionProvider(CommsPermissions.sms));

    // Treat an unresolved balance as configured: showing the activation prompt
    // to a tenant that simply has a slow reseller call would be worse.
    final configured = balance.valueOrNull?.isConfigured ?? true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.xl),
      children: [
        if (!configured) ...[
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SMS is not enabled yet',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    balance.valueOrNull?.message ??
                        'An administrator has to configure SMS for this account '
                            'before credits can be used.',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (canBuy) ...[
                    const SizedBox(height: Spacing.md),
                    FilledButton.icon(
                      onPressed: _busy ? null : _requestActivation,
                      icon: const Icon(Icons.outgoing_mail, size: 18),
                      label: const Text('Request activation'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        if (!canBuy)
          const StateMessage(
            icon: Icons.lock_outline,
            title: 'Viewing only',
            message: 'Your role cannot buy SMS credits.',
          )
        else
          CommsAsyncView<List<SmsPackageOption>>(
            value: packages,
            errorTitle: 'Could not load packages',
            onRetry: () => ref.invalidate(smsPackagesProvider),
            builder: (context, tiers) {
              final quantity = _parsedQuantity;
              final tier = _tierFor(tiers, quantity);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeading('Price tiers'),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, t) in tiers.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            selected: t.id == tier?.id,
                            title: Text(t.name),
                            subtitle: Text(t.maxQuantity == null
                                ? '${t.minQuantity}+ SMS'
                                : '${t.minQuantity}–${t.maxQuantity} SMS'),
                            trailing: Text(
                              '${Formatting.currency(t.pricePerSms)} / SMS',
                              style: theme.textTheme.labelMedium,
                            ),
                            onTap: () => setState(
                                () => _quantity.text = '${t.minQuantity}'),
                          ),
                        ],
                        if (tiers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(Spacing.md),
                            child: Text('No packages are configured.'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  const SectionHeading('Quantity'),
                  TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'SMS to buy',
                      helperText: 'Minimum 100',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        children: [
                          DetailRow(
                            label: 'Tier',
                            value: tier?.name ?? 'No matching package',
                          ),
                          DetailRow(
                            label: 'Total',
                            value: tier == null
                                ? '—'
                                : Formatting.currency(
                                    quantity * tier.pricePerSms),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  FilledButton.icon(
                    onPressed: (_busy || tier == null) ? null : _checkout,
                    icon: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Pay with Pesapal'),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Payment opens in your browser. Come back to Purchases to '
                    'confirm it once you are done.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Bumped to make the history list reload after a purchase is created.
final StateProvider<int> smsPurchasesRefreshProvider =
    StateProvider<int>((ref) => 0);

class _PurchaseHistoryView extends ConsumerStatefulWidget {
  const _PurchaseHistoryView();

  @override
  ConsumerState<_PurchaseHistoryView> createState() =>
      _PurchaseHistoryViewState();
}

class _PurchaseHistoryViewState extends ConsumerState<_PurchaseHistoryView> {
  final _list = GlobalKey<PagedListViewState<SmsPurchase>>();

  Future<void> _checkStatus(SmsPurchase purchase) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await ref
          .read(commsServiceProvider)
          .smsPurchaseStatus(purchase.id);
      showCommsMessage(
        messenger,
        status.isCompleted
            ? 'Payment confirmed — ${status.smsQuantity} SMS credited.'
            : 'Still ${StatusColors.label(status.status).toLowerCase()}'
                '${status.description == null ? '' : ': ${status.description}'}',
      );
      _list.currentState?.reload();
      ref.invalidate(smsBalanceProvider);
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  Future<void> _retry(SmsPurchase purchase) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url =
          await ref.read(commsServiceProvider).retrySmsPurchase(purchase.id);
      if (url == null) {
        showCommsMessage(messenger, 'No payment page was returned.',
            isError: true);
        return;
      }
      await _openPayment(messenger, url);
      _list.currentState?.reload();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPay = ref.watch(commsPermissionProvider(CommsPermissions.sms));

    // Reload when a checkout was just started on the other tab.
    ref.listen<int>(smsPurchasesRefreshProvider,
        (previous, next) => _list.currentState?.reload());

    return PagedListView<SmsPurchase>(
      key: _list,
      fetch: (page) => ref.read(commsServiceProvider).smsPurchases(page: page),
      emptyIcon: Icons.receipt_outlined,
      emptyTitle: 'No purchases yet',
      emptyMessage: 'Credits you buy will be listed here.',
      itemBuilder: (context, purchase) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${purchase.smsQuantity} SMS',
                        style: theme.textTheme.titleSmall),
                  ),
                  Text(Formatting.currency(purchase.totalAmount),
                      style: theme.textTheme.labelLarge),
                  const SizedBox(width: Spacing.sm),
                  StatusChip(purchase.status, dense: true),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                [
                  if (purchase.packageName != null) purchase.packageName!,
                  Formatting.date(purchase.createdAt),
                  if (purchase.receiptNumber != null) purchase.receiptNumber!,
                  if (purchase.confirmationCode != null)
                    purchase.confirmationCode!,
                ].join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (purchase.isPayable) ...[
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text('Check status'),
                        onPressed: () => _checkStatus(purchase),
                      ),
                    ),
                    if (canPay) ...[
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Pay'),
                          onPressed: () => _retry(purchase),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hand a Pesapal payment page to the browser. Kept out of the widgets so both
/// checkout and retry report a blocked launch the same way.
Future<void> _openPayment(ScaffoldMessengerState messenger, String url) async {
  final uri = Uri.tryParse(url);
  final opened = uri == null
      ? false
      : await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    showCommsMessage(messenger, 'Could not open the payment page.',
        isError: true);
  }
}
