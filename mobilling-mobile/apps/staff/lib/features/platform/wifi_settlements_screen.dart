import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmField, CrmMetaLine, CrmSheet, FilterStrip, showCrmSheet;
import 'platform_providers.dart';

/// Cross-tenant settlement ledger for platform_collected WiFi vouchers —
/// MoBilling's own Pesapal account collected the money; this is where a
/// super admin tracks what's owed to each tenant and records that it was
/// paid out by hand. Not a real money transfer — no disbursement API exists.
class WifiSettlementsScreen extends ConsumerStatefulWidget {
  const WifiSettlementsScreen({super.key});

  @override
  ConsumerState<WifiSettlementsScreen> createState() =>
      _WifiSettlementsScreenState();
}

class _WifiSettlementsScreenState
    extends ConsumerState<WifiSettlementsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _tenantId;
  bool? _settled = false;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('false', 'Unsettled'),
    ('true', 'Settled'),
  ];

  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(_settlementsSummaryProvider);
  }

  Future<void> _settle(WifiSettlementRow row) async {
    final settled = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _SettleSheet(row: row),
    );
    if (settled == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_settlementsSummaryProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Platform', title: 'WiFi Settlements'),
      body: Column(
        children: [
          summary.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.sm),
                  itemBuilder: (context, index) {
                    final s = rows[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: () {
                        setState(() {
                          _tenantId = _tenantId == s.tenantId
                              ? null
                              : s.tenantId;
                        });
                        _listKey.currentState?.reload();
                      },
                      child: Card(
                        color: _tenantId == s.tenantId
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(Spacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                s.tenantName,
                                style: Theme.of(context).textTheme.labelMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Money(s.totalOwed, scale: MoneyScale.dense),
                              Text(
                                '${s.count} unsettled',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: FilterStrip(
              options: _filters,
              selected: _settled?.toString(),
              onSelect: (v) {
                setState(() => _settled = v == null ? null : v == 'true');
                _listKey.currentState?.reload();
              },
            ),
          ),
          Expanded(
            child: PagedListView<WifiSettlementRow>(
              key: _listKey,
              fetch: (page) => ref
                  .read(platformServiceProvider)
                  .wifiSettlements(
                    tenantId: _tenantId,
                    settled: _settled,
                    page: page,
                  ),
              itemBuilder: (context, row) => _SettlementCard(
                row: row,
                onSettle: row.isSettled ? null : () => _settle(row),
              ),
              emptyIcon: Icons.wifi_outlined,
              emptyTitle: 'No platform-collected voucher sales yet',
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.row, required this.onSettle});

  final WifiSettlementRow row;
  final VoidCallback? onSettle;

  @override
  Widget build(BuildContext context) {
    final r = row;

    return Card(
      child: ListTile(
        title: Text(r.tenantName ?? 'Unknown'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              r.customerPhone,
              if (r.completedAt != null) Formatting.date(r.completedAt),
              if (r.commissionAmount != null)
                '−${Formatting.currency(r.commissionAmount)} commission',
            ].join(' · '),
          ),
        ),
        trailing: onSettle == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Money(r.netAmount ?? r.amount),
                  const SizedBox(height: 2),
                  const StatusChip('settled', dense: true),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Money(r.netAmount ?? r.amount),
                  const SizedBox(height: 2),
                  TextButton.icon(
                    onPressed: onSettle,
                    icon: const Icon(Icons.payments_outlined, size: 14),
                    label: const Text('Mark paid'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({required this.row});

  final WifiSettlementRow row;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'mpesa';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final message = await ref
          .read(platformServiceProvider)
          .settleWifiVoucherPurchase(
            widget.row.id,
            method: _method,
            reference: _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(message)));
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
    final r = widget.row;

    return CrmSheet(
      eyebrow: 'WiFi Settlements',
      title: 'Mark as settled',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'Confirm you have paid ${r.tenantName ?? 'this tenant'} '
          '${Formatting.currency(r.netAmount ?? r.amount)} outside the app '
          '(mobile money, bank transfer, or cash), then record it here.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Method',
          child: DropdownButtonFormField<String>(
            initialValue: _method,
            isExpanded: true,
            items: [
              for (final (value, label) in WifiSettlementMethods.values)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _method = v ?? _method),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Reference (optional)',
          child: TextField(
            controller: _reference,
            enabled: !_busy,
            decoration: const InputDecoration(
              hintText: 'e.g. M-Pesa transaction code',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes (optional)',
          child: TextField(controller: _notes, enabled: !_busy, maxLines: 3),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: 'Confirm settlement',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

final AutoDisposeFutureProvider<List<WifiSettlementSummaryRow>>
_settlementsSummaryProvider =
    FutureProvider.autoDispose<List<WifiSettlementSummaryRow>>(
      (ref) => ref.watch(platformServiceProvider).wifiSettlementsSummary(),
    );
