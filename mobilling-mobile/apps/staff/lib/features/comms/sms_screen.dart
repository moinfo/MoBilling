import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/paged_list.dart';
import '../common/share_pdf.dart';
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
        appBar: ShellTopBar(
          eyebrow: 'Communications',
          title: 'SMS',
          trailing: InkActionButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh balance',
            onPressed: () => ref.invalidate(smsBalanceProvider),
          ),
          bottom: const InkTabBar(tabs: ['Buy credits', 'Purchases']),
        ),
        body: const Column(
          children: [
            _BalanceCard(),
            Expanded(
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

/// The one figure this screen is about: credits left, in the display face.
class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final balance = ref.watch(smsBalanceProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.sm,
      ),
      child: Reveal(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CURRENT BALANCE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                balance.when(
                  loading: () => SizedBox(
                    height: MoneyScale.display.size,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (error, _) => Text(
                    commsErrorText(error),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  data: (b) => b.isConfigured
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              Formatting.integer(b.balance),
                              style: Type.display(
                                MoneyScale.display.size,
                                height: 1,
                                // Empty is the one state that needs a
                                // colour: nothing sends until it is topped
                                // up.
                                color: b.balance == 0
                                    ? status.overdue
                                    : theme.colorScheme.onSurface,
                              ).copyWith(fontFeatures: Type.figures),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'SMS',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Not configured',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
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

  /// A rejected order, shown above the form rather than in a snackbar.
  String? _formError;

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
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final message = await ref
          .read(commsServiceProvider)
          .requestSmsActivation();
      showCommsMessage(messenger, message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout() async {
    final messenger = ScaffoldMessenger.of(context);
    final quantity = _parsedQuantity;

    if (quantity < 100) {
      setState(() => _formError = 'Buy at least 100 SMS.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final checkout = await ref
          .read(commsServiceProvider)
          .smsCheckout(quantity: quantity);
      ref.read(smsPurchasesRefreshProvider.notifier).state++;

      final url = checkout.redirectUrl;
      if (url == null) {
        if (mounted) {
          setState(
            () => _formError =
                'Purchase created, but the payment page is not ready yet. '
                'Retry it from Purchases.',
          );
        }
        return;
      }
      await _openPayment(messenger, url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.sm,
        Spacing.md,
        Spacing.xl,
      ),
      children: [
        if (_formError != null) ...[
          ErrorBanner(message: _formError!),
          const SizedBox(height: Spacing.md),
        ],
        if (!configured) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SMS is not enabled yet',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    balance.valueOrNull?.message ??
                        'An administrator has to configure SMS for this account '
                            'before credits can be used.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (canBuy) ...[
                    const SizedBox(height: Spacing.md),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _requestActivation,
                      icon: const Icon(Icons.outgoing_mail, size: 18),
                      label: const Text('Request activation'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
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
                            selected: t.id == tier?.id,
                            selectedTileColor: theme.colorScheme.primary
                                .withValues(alpha: 0.06),
                            title: Text(
                              t.name,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: CommsMeta(
                              t.maxQuantity == null
                                  ? '${Formatting.integer(t.minQuantity)}+ SMS'
                                  : '${Formatting.integer(t.minQuantity)}–'
                                        '${Formatting.integer(t.maxQuantity)} SMS',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Money(t.pricePerSms),
                                const SizedBox(width: Spacing.xs),
                                Text(
                                  '/ SMS',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => setState(() {
                              _quantity.text = '${t.minQuantity}';
                              _formError = null;
                            }),
                          ),
                        ],
                        if (tiers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Text(
                              'No packages are configured.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  const SectionHeading('Your order'),
                  const CommsFieldLabel('SMS to buy'),
                  const SizedBox(height: Spacing.sm),
                  TextField(
                    controller: _quantity,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() => _formError = null),
                    decoration: const InputDecoration(
                      hintText: 'At least 100',
                      helperText: 'Minimum 100',
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        children: [
                          _OrderLine(
                            label: 'Tier',
                            value: Text(
                              tier?.name ?? 'No matching package',
                              style: theme.textTheme.bodyMedium,
                              textAlign: TextAlign.end,
                            ),
                          ),
                          const Divider(height: Spacing.lg),
                          _OrderLine(
                            label: 'Total',
                            value: tier == null
                                ? Text('—', style: theme.textTheme.bodyMedium)
                                : Money(
                                    quantity * tier.pricePerSms,
                                    scale: MoneyScale.headline,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  PrimaryButton(
                    label: _busy ? 'Opening Pesapal…' : 'Pay with Pesapal',
                    icon: Icons.open_in_new,
                    busy: _busy,
                    onPressed: (_busy || tier == null) ? null : _checkout,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Payment opens in your browser. Come back to Purchases to '
                    'confirm it once you are done.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

/// An eyebrow on the left, a figure or value on the right.
class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: value),
        ),
      ],
    );
  }
}

/// Bumped to make the history list reload after a purchase is created.
final StateProvider<int> smsPurchasesRefreshProvider = StateProvider<int>(
  (ref) => 0,
);

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
      final url = await ref
          .read(commsServiceProvider)
          .retrySmsPurchase(purchase.id);
      if (url == null) {
        showCommsMessage(
          messenger,
          'No payment page was returned.',
          isError: true,
        );
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
    final canPay = ref.watch(commsPermissionProvider(CommsPermissions.sms));

    // Reload when a checkout was just started on the other tab.
    ref.listen<int>(
      smsPurchasesRefreshProvider,
      (previous, next) => _list.currentState?.reload(),
    );

    return PagedListView<SmsPurchase>(
      key: _list,
      fetch: (page) => ref.read(commsServiceProvider).smsPurchases(page: page),
      emptyIcon: Icons.receipt_outlined,
      emptyTitle: 'No purchases yet',
      emptyMessage: 'Credits you buy will be listed here.',
      itemBuilder: (context, purchase) => _PurchaseCard(
        purchase: purchase,
        onCheckStatus: () => _checkStatus(purchase),
        onPay: canPay ? () => _retry(purchase) : null,
        onReceipt: purchase.isCompleted
            ? () => _downloadReceipt(context, purchase)
            : null,
        onInvoice: () => _downloadInvoice(context, purchase),
      ),
    );
  }

  Future<void> _downloadReceipt(
    BuildContext context,
    SmsPurchase purchase,
  ) => sharePdf(
    context,
    fetch: () => ref.read(commsServiceProvider).smsReceiptPdf(purchase.id),
    filename: 'sms-receipt-${purchase.receiptNumber ?? purchase.id}.pdf',
  );

  Future<void> _downloadInvoice(
    BuildContext context,
    SmsPurchase purchase,
  ) => sharePdf(
    context,
    fetch: () => ref.read(commsServiceProvider).smsInvoicePdf(purchase.id),
    filename: 'sms-invoice-${purchase.id}.pdf',
  );
}

/// One purchase: the credits bought, status beside the reference line, the
/// amount as the aligned figure on the right, and the two follow-up actions
/// while Pesapal has yet to confirm it.
class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({
    required this.purchase,
    required this.onCheckStatus,
    this.onPay,
    this.onReceipt,
    this.onInvoice,
  });

  final SmsPurchase purchase;
  final VoidCallback onCheckStatus;
  final VoidCallback? onPay;

  /// Null while the purchase has yet to complete — the server 422s a receipt
  /// request until then, so the action is hidden rather than offered and
  /// refused.
  final VoidCallback? onReceipt;
  final VoidCallback? onInvoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Formatting.integer(purchase.smsQuantity)} SMS',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          StatusChip(purchase.status, dense: true),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: CommsMeta(
                              [
                                if (purchase.packageName != null)
                                  purchase.packageName!,
                                Formatting.date(purchase.createdAt),
                                if (purchase.receiptNumber != null)
                                  purchase.receiptNumber!,
                                if (purchase.confirmationCode != null)
                                  purchase.confirmationCode!,
                              ].join(' · '),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Money(purchase.totalAmount),
              ],
            ),
            if (purchase.isPayable) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Check status'),
                      onPressed: onCheckStatus,
                    ),
                  ),
                  if (onPay != null) ...[
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Pay'),
                        onPressed: onPay,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (onReceipt != null || onInvoice != null) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  if (onReceipt != null)
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('Receipt'),
                        onPressed: onReceipt,
                      ),
                    ),
                  if (onReceipt != null && onInvoice != null)
                    const SizedBox(width: Spacing.sm),
                  if (onInvoice != null)
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('Invoice'),
                        onPressed: onInvoice,
                      ),
                    ),
                ],
              ),
            ],
          ],
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
    showCommsMessage(
      messenger,
      'Could not open the payment page.',
      isError: true,
    );
  }
}
