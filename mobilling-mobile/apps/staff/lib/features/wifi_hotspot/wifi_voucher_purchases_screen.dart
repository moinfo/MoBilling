import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmDetailRow, CrmField, CrmMetaLine, CrmSheet, FilterStrip, showCrmSheet;
import 'wifi_hotspot_providers.dart';

/// Every voucher sold on this tenant's routers — online (Pesapal) or
/// staff-recorded cash/manual. The "Sell Voucher" action here is the
/// mobile-only shortcut web keeps in the same page rather than a
/// dedicated screen.
class WifiVoucherPurchasesScreen extends ConsumerStatefulWidget {
  const WifiVoucherPurchasesScreen({super.key});

  @override
  ConsumerState<WifiVoucherPurchasesScreen> createState() =>
      _WifiVoucherPurchasesScreenState();
}

class _WifiVoucherPurchasesScreenState
    extends ConsumerState<WifiVoucherPurchasesScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  static const _statusFilters = <(String?, String)>[
    (null, 'All'),
    ('completed', 'Completed'),
    ('pending', 'Pending'),
    ('failed', 'Failed'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() => _listKey.currentState?.reload();

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _sell() async {
    final sold = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _SellVoucherSheet(),
    );
    if (sold == true) _reload();
  }

  Future<void> _openDetail(WifiVoucherPurchase purchase) async {
    await showCrmSheet<void>(
      context: context,
      builder: (_) => _VoucherDetailSheet(purchase: purchase),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canSell =
        session?.can(WifiHotspotPermissions.purchasesCreate) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'WiFi Hotspot',
        title: 'Voucher Sales',
        trailing: canSell
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Sell voucher (cash)',
                onPressed: _sell,
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search by phone',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _reload();
          },
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _statusFilters,
            selected: _status,
            onSelect: (v) {
              setState(() => _status = v);
              _reload();
            },
          ),
          Expanded(
            child: PagedListView<WifiVoucherPurchase>(
              key: _listKey,
              fetch: (page) => ref
                  .read(wifiHotspotServiceProvider)
                  .voucherPurchases(
                    status: _status,
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              itemBuilder: (context, purchase) => _PurchaseCard(
                purchase: purchase,
                onTap: () => _openDetail(purchase),
              ),
              emptyIcon: Icons.wifi_outlined,
              emptyTitle: 'No voucher sales yet',
              emptyMessage: canSell
                  ? 'Sell the first one from the button above.'
                  : 'Sales appear here as customers buy vouchers.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  const _PurchaseCard({required this.purchase, required this.onTap});

  final WifiVoucherPurchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = purchase;

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(p.customerPhone),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              if (p.routerName != null) p.routerName!,
              if (p.planName != null) p.planName!,
              if (p.hotspotUsername != null) p.hotspotUsername!,
            ].join(' · '),
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Money(p.amount),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusChip(p.status, dense: true),
                if (p.isBlocked) ...[
                  const SizedBox(width: 4),
                  const StatusChip('blocked', dense: true),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoucherDetailSheet extends ConsumerStatefulWidget {
  const _VoucherDetailSheet({required this.purchase});

  final WifiVoucherPurchase purchase;

  @override
  ConsumerState<_VoucherDetailSheet> createState() =>
      _VoucherDetailSheetState();
}

class _VoucherDetailSheetState extends ConsumerState<_VoucherDetailSheet> {
  late WifiVoucherPurchase _purchase;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _purchase = widget.purchase;
  }

  Future<void> _block() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${_purchase.hotspotUsername}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This immediately disconnects and locks out this customer. '
              "They'll no longer be able to use this voucher.",
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. abusing bandwidth',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final reason = controller.text.trim();
      final updated = await ref
          .read(wifiHotspotServiceProvider)
          .blockVoucher(_purchase.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        setState(() => _purchase = updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Voucher access has been revoked.')),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unblock() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(wifiHotspotServiceProvider)
          .unblockVoucher(_purchase.id);
      if (mounted) {
        setState(() => _purchase = updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Voucher access restored.')),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canBlock =
        session?.can(WifiHotspotPermissions.purchasesUpdate) ?? false;
    final p = _purchase;

    return CrmSheet(
      eyebrow: Formatting.date(p.createdAt),
      title: p.customerPhone,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Money(p.amount, scale: MoneyScale.headline)),
            StatusChip(p.status, dense: true),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (p.routerName != null) CrmDetailRow('Router', p.routerName!),
        if (p.planName != null) CrmDetailRow('Plan', p.planName!),
        if (p.customerName != null) CrmDetailRow('Customer', p.customerName!),
        if (p.hotspotUsername != null)
          CrmDetailRow('Voucher code', p.hotspotUsername!),
        if (p.paymentMethodUsed != null)
          CrmDetailRow('Payment method', p.paymentMethodUsed!)
        else
          const CrmDetailRow('Payment method', 'Online checkout'),
        if (p.voucherExpiresAt != null)
          CrmDetailRow('Expires', Formatting.date(p.voucherExpiresAt)),
        if (p.isBlocked)
          CrmDetailRow('Blocked', p.blockedReason ?? 'No reason given'),
        const SizedBox(height: Spacing.lg),
        if (p.isProvisioned) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.speed_outlined, size: 18),
            label: const Text('View data/time usage'),
            onPressed: () => showCrmSheet<void>(
              context: context,
              builder: (_) => _UsageSheet(purchase: p),
            ),
          ),
          if (canBlock) ...[
            const SizedBox(height: Spacing.sm),
            if (p.isBlocked)
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: Text(_busy ? 'Unblocking…' : 'Unblock'),
                onPressed: _busy ? null : _unblock,
              )
            else
              OutlinedButton.icon(
                icon: Icon(
                  Icons.block_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                label: Text(
                  _busy ? 'Blocking…' : 'Block this voucher',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: _busy ? null : _block,
              ),
          ],
        ],
      ],
    );
  }
}

class _UsageSheet extends ConsumerWidget {
  const _UsageSheet({required this.purchase});

  final WifiVoucherPurchase purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(_voucherUsageProvider(purchase.id));
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: purchase.hotspotUsername ?? 'Usage',
      title: 'Data & time usage',
      children: [
        usage.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorBanner(
            message: e is ApiException ? e.message : 'Could not load usage.',
          ),
          data: (u) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!u.routerReachable) ...[
                const ErrorBanner(
                  message:
                      'Router is not reachable right now — figures may be stale.',
                ),
                const SizedBox(height: Spacing.md),
              ],
              Text('Data', style: theme.textTheme.labelLarge),
              const SizedBox(height: Spacing.xs),
              if (u.dataCapMb == null)
                const Text('Unlimited')
              else ...[
                Text(
                  u.dataUsedMb == null
                      ? 'Unknown'
                      : '${(u.dataUsedMb! / 1024).toStringAsFixed(2)} GB used '
                            '/ ${(u.dataCapMb! / 1024).toStringAsFixed(2)} GB',
                ),
                const SizedBox(height: Spacing.xs),
                LinearProgressIndicator(
                  value: u.dataUsedMb == null
                      ? 0
                      : (u.dataUsedMb! / u.dataCapMb!).clamp(0, 1),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              Text('Time', style: theme.textTheme.labelLarge),
              const SizedBox(height: Spacing.xs),
              if (u.durationSeconds == null)
                const Text('Unlimited')
              else ...[
                Text(
                  u.timeUsedSeconds == null
                      ? 'Not started yet'
                      : '${_formatSeconds(u.timeUsedSeconds!)} used / '
                            '${_formatSeconds(u.durationSeconds!)}',
                ),
                if (u.timeUsedSeconds != null) ...[
                  const SizedBox(height: Spacing.xs),
                  LinearProgressIndicator(
                    value: (u.timeUsedSeconds! / u.durationSeconds!).clamp(
                      0,
                      1,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _formatSeconds(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final parts = <String>[
    if (d > 0) '${d}d',
    if (h > 0) '${h}h',
    if (m > 0 || (d == 0 && h == 0)) '${m}m',
  ];
  return parts.join(' ');
}

final AutoDisposeFutureProviderFamily<WifiVoucherUsage, String>
_voucherUsageProvider = FutureProvider.autoDispose.family<WifiVoucherUsage, String>(
  (ref, id) => ref.watch(wifiHotspotServiceProvider).voucherUsage(id),
);

/// For customers paying with physical cash instead of the online checkout.
/// The voucher is created immediately and its code texted/WhatsApp'd to
/// their phone — same provisioning path as an online payment.
class _SellVoucherSheet extends ConsumerStatefulWidget {
  const _SellVoucherSheet();

  @override
  ConsumerState<_SellVoucherSheet> createState() => _SellVoucherSheetState();
}

class _SellVoucherSheetState extends ConsumerState<_SellVoucherSheet> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  String? _routerId;
  String? _planId;
  String _paymentMethod = 'cash';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (_routerId == null || _planId == null) {
      setState(() => _error = 'Choose a router and a plan.');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = "Enter the customer's phone number.");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final purchase = await ref
          .read(wifiHotspotServiceProvider)
          .sellVoucher(
            mikrotikRouterId: _routerId!,
            wifiPlanId: _planId!,
            customerPhone: phone,
            paymentMethod: _paymentMethod,
            customerName: _name.text.trim().isEmpty
                ? null
                : _name.text.trim(),
          );
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            purchase.hotspotUsername != null
                ? 'Code ${purchase.hotspotUsername} created and sent to the '
                      "customer's phone."
                : 'Voucher created.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final routers = ref.watch(allRoutersProvider);
    final plans = _routerId == null
        ? null
        : ref.watch(plansForRouterProvider(_routerId!));

    return CrmSheet(
      eyebrow: 'WiFi Hotspot',
      title: 'Sell Voucher (Cash)',
      children: [
        Text(
          'For customers paying with physical cash instead of the online '
          "checkout. The voucher is created immediately and its code is "
          "texted/WhatsApp'd to their phone.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        routers.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorBanner(
            message: e is ApiException
                ? 'Could not load routers: ${e.message}'
                : 'Could not load routers.',
          ),
          data: (rows) => CrmField(
            label: 'Router',
            child: DropdownButtonFormField<String>(
              initialValue: rows.any((r) => r.id == _routerId)
                  ? _routerId
                  : null,
              isExpanded: true,
              hint: const Text('Select router'),
              items: [
                for (final r in rows)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _routerId = v;
                      _planId = null;
                    }),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Plan',
          child: plans == null
              ? DropdownButtonFormField<String>(
                  items: const [],
                  onChanged: null,
                  hint: const Text('Select a router first'),
                )
              : plans.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorBanner(
                    message: e is ApiException
                        ? 'Could not load plans: ${e.message}'
                        : 'Could not load plans.',
                  ),
                  data: (rows) => DropdownButtonFormField<String>(
                    initialValue: rows.any((p) => p.id == _planId)
                        ? _planId
                        : null,
                    isExpanded: true,
                    hint: const Text('Select plan'),
                    items: [
                      for (final p in rows)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.name} — ${Formatting.currency(p.price)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _planId = v),
                  ),
                ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Customer phone',
          child: TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'e.g. 0712345678'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Customer name (optional)',
          child: TextField(controller: _name, enabled: !_busy),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Payment method',
          child: DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            isExpanded: true,
            items: [
              for (final (value, label) in WifiPaymentMethods.values)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _paymentMethod = v ?? _paymentMethod),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _busy ? 'Creating…' : 'Create & send voucher',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
