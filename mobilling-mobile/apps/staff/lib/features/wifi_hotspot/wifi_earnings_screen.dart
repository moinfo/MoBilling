import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmMetaLine, FilterStrip;
import 'wifi_hotspot_providers.dart';

/// Money MoBilling collected on the tenant's behalf for platform-collected
/// WiFi voucher sales, and what's still owed back.
class WifiEarningsScreen extends ConsumerStatefulWidget {
  const WifiEarningsScreen({super.key});

  @override
  ConsumerState<WifiEarningsScreen> createState() =>
      _WifiEarningsScreenState();
}

class _WifiEarningsScreenState extends ConsumerState<WifiEarningsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _settled;
  bool _requestingPayout = false;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('false', 'Unsettled'),
    ('true', 'Settled'),
  ];

  Future<void> _requestPayout() async {
    if (_requestingPayout) return;
    setState(() => _requestingPayout = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(wifiHotspotServiceProvider)
          .requestPayout();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _requestingPayout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_earningsSummaryProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'WiFi Hotspot', title: 'My Earnings'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: CrmAsyncView(
              value: summary,
              errorTitle: 'Could not load your earnings summary',
              onRetry: () => ref.invalidate(_earningsSummaryProvider),
              builder: (s) => _SummaryPanel(
                summary: s,
                requestingPayout: _requestingPayout,
                onRequestPayout: _requestPayout,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: FilterStrip(
              options: _filters,
              selected: _settled,
              onSelect: (v) {
                setState(() => _settled = v);
                _listKey.currentState?.reload();
              },
            ),
          ),
          Expanded(
            child: PagedListView<WifiEarningRow>(
              key: _listKey,
              fetch: (page) => ref
                  .read(wifiHotspotServiceProvider)
                  .earnings(
                    settled: _settled == null ? null : _settled == 'true',
                    page: page,
                  ),
              itemBuilder: (context, row) => _EarningCard(row: row),
              emptyIcon: Icons.wifi_outlined,
              emptyTitle: 'No platform-collected voucher sales yet',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.summary,
    required this.requestingPayout,
    required this.onRequestPayout,
  });

  final WifiEarningsSummary summary;
  final bool requestingPayout;
  final VoidCallback onRequestPayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Owed to you',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Money(
                    summary.owed,
                    scale: MoneyScale.headline,
                    color: status.attention,
                  ),
                  Text(
                    '${summary.unsettledCount} unsettled sale'
                    '${summary.unsettledCount == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Already paid out',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Money(
                    summary.totalSettled,
                    scale: MoneyScale.headline,
                    color: status.settled,
                  ),
                  const SizedBox(height: Spacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: requestingPayout
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payments_outlined, size: 16),
                      label: Text(
                        requestingPayout ? 'Sending…' : 'Request payout',
                      ),
                      onPressed: (summary.owed <= 0 || requestingPayout)
                          ? null
                          : onRequestPayout,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EarningCard extends StatelessWidget {
  const _EarningCard({required this.row});

  final WifiEarningRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;

    return Card(
      child: ListTile(
        title: Text(r.customerPhone),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CrmMetaLine(
            [
              if (r.routerName != null) r.routerName!,
              if (r.completedAt != null) Formatting.date(r.completedAt),
              if (r.commissionAmount != null)
                '−${Formatting.currency(r.commissionAmount)} commission',
            ].join(' · '),
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Money(r.netAmount ?? r.amount),
            const SizedBox(height: 2),
            StatusChip(r.isSettled ? 'settled' : 'owed', dense: true),
          ],
        ),
      ),
    );
  }
}

final AutoDisposeFutureProvider<WifiEarningsSummary> _earningsSummaryProvider =
    FutureProvider.autoDispose<WifiEarningsSummary>(
      (ref) => ref.watch(wifiHotspotServiceProvider).earningsSummary(),
    );
