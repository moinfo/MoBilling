import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_money/billing_money_providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import 'billing_catalog_providers.dart';

/// The catalog screens are all read-only browsers over reference data —
/// products, add-ons, configurable options and coupons. Editing them is
/// genuinely desk work (long forms, product linking), so mobile shows what is
/// configured and leaves authoring to the web.

// ---------------------------------------------------------------------------
// Products & services
// ---------------------------------------------------------------------------

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Products & services')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search name or code',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) =>
                  ref.read(billingCatalogServiceProvider).products(
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                        page: page,
                      ),
              itemBuilder: (context, product) => Card(
                child: ListTile(
                  title: Text(product.name),
                  subtitle: Text(
                    [
                      if (product.category != null) product.category!,
                      if (product.code != null) product.code!,
                      if (product.isRecurring)
                        product.billingCycle!.replaceAll('_', ' '),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Money(product.price),
                      if (!product.isActive)
                        const StatusChip('draft', dense: true),
                    ],
                  ),
                ),
              ),
              emptyIcon: Icons.inventory_2_outlined,
              emptyTitle: 'No products found',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product add-ons
// ---------------------------------------------------------------------------

class ProductAddonsScreen extends ConsumerWidget {
  const ProductAddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonsProvider(null));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Product add-ons')),
      body: CrmAsyncView(
        value: addons,
        errorTitle: 'Could not load add-ons',
        onRetry: () => ref.invalidate(addonsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.add_box_outlined,
                title: 'No add-ons configured',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final addon = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(addon.name,
                                    style: theme.textTheme.titleSmall),
                              ),
                              Money(addon.price),
                            ],
                          ),
                          if (addon.description != null) ...[
                            const SizedBox(height: 2),
                            Text(addon.description!,
                                style: theme.textTheme.bodySmall),
                          ],
                          const SizedBox(height: Spacing.xs),
                          Text(
                            [
                              if (addon.billingCycle != null)
                                addon.billingCycle!.replaceAll('_', ' '),
                              addon.productNames.isEmpty
                                  ? 'not linked to any product'
                                  : 'on ${addon.productNames.join(', ')}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (!addon.isActive) ...[
                            const SizedBox(height: Spacing.xs),
                            const StatusChip('draft', dense: true),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Configurable options
// ---------------------------------------------------------------------------

class ConfigOptionsScreen extends ConsumerWidget {
  const ConfigOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(configGroupsProvider(null));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurable options')),
      body: CrmAsyncView(
        value: groups,
        errorTitle: 'Could not load option groups',
        onRetry: () => ref.invalidate(configGroupsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.settings_input_component_outlined,
                title: 'No option groups configured',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final group = items[index];
                  return Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(group.name),
                      subtitle: Text(
                        [
                          '${group.options.length} option${group.options.length == 1 ? '' : 's'}',
                          if (group.productNames.isNotEmpty)
                            'on ${group.productNames.join(', ')}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: group.isActive
                          ? null
                          : const StatusChip('draft', dense: true),
                      childrenPadding: const EdgeInsets.fromLTRB(
                          Spacing.md, 0, Spacing.md, Spacing.sm),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final option in group.options) ...[
                          Text(
                            '${option.name}  ·  ${option.optionType}',
                            style: theme.textTheme.labelMedium,
                          ),
                          if (option.unitPrice != null)
                            Text(
                              '${Formatting.currency(option.unitPrice)} per unit',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          for (final choice in option.choices)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: Spacing.md, bottom: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(choice.label,
                                        style: theme.textTheme.bodySmall),
                                  ),
                                  Text(
                                    choice.price == 0
                                        ? 'included'
                                        : '+${Formatting.currency(choice.price)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: Spacing.xs),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Coupons
// ---------------------------------------------------------------------------

class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider(null));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Promotions / coupons')),
      body: CrmAsyncView(
        value: coupons,
        errorTitle: 'Could not load coupons',
        onRetry: () => ref.invalidate(couponsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.local_offer_outlined,
                title: 'No coupons configured',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) {
                  final coupon = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  coupon.code,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontFamily: 'monospace',
                                      letterSpacing: 1),
                                ),
                              ),
                              Text(
                                // Percent renders itself; a fixed amount needs
                                // the tenant's currency.
                                coupon.percentLabel ??
                                    Formatting.currency(coupon.value),
                                style: theme.textTheme.labelLarge
                                    ?.copyWith(color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: Spacing.sm),
                              StatusChip(coupon.status, dense: true),
                            ],
                          ),
                          if (coupon.description != null) ...[
                            const SizedBox(height: 2),
                            Text(coupon.description!,
                                style: theme.textTheme.bodySmall),
                          ],
                          const SizedBox(height: Spacing.xs),
                          Text(
                            [
                              coupon.maxUses == null
                                  ? '${coupon.uses} use${coupon.uses == 1 ? '' : 's'}'
                                  : '${coupon.uses}/${coupon.maxUses} used',
                              if (coupon.recurring) 'recurring',
                              if (coupon.minOrder != null)
                                'min ${Formatting.amount(coupon.minOrder)}',
                              if (coupon.expiresAt != null)
                                'expires ${Formatting.date(coupon.expiresAt)}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          if (coupon.productNames.isNotEmpty) ...[
                            const SizedBox(height: Spacing.xs),
                            Text('on ${coupon.productNames.join(', ')}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions (staff, tenant-wide)
// ---------------------------------------------------------------------------

class StaffSubscriptionsScreen extends ConsumerStatefulWidget {
  const StaffSubscriptionsScreen({super.key});

  @override
  ConsumerState<StaffSubscriptionsScreen> createState() =>
      _StaffSubscriptionsScreenState();
}

class _StaffSubscriptionsScreenState
    extends ConsumerState<StaffSubscriptionsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('suspended', 'Suspended'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGenerate = ref.watch(sessionControllerProvider).session?.can(
              BillingMoneyPermissions.subscriptionsCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search client or product',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              itemCount: _filters.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return FilterChip(
                  label: Text(label),
                  selected: _status == value,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _status = value);
                    _listKey.currentState?.reload();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) =>
                  ref.read(billingCatalogServiceProvider).subscriptions(
                        status: _status,
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                        page: page,
                      ),
              itemBuilder: (context, sub) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(sub.clientName ?? '—',
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          StatusChip(sub.status, dense: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          sub.productName ?? 'Service',
                          if (sub.label != null) sub.label!,
                        ].join(' — '),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                Formatting.currency(sub.lineTotal),
                                if (sub.billingCycle != null &&
                                    sub.billingCycle != 'once')
                                  sub.billingCycle!.replaceAll('_', ' '),
                                if (sub.expireDate != null)
                                  'expires ${Formatting.date(sub.expireDate)}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          if (canGenerate && sub.status == 'active')
                            TextButton(
                              onPressed: () => _generateInvoice(sub),
                              child: const Text('Bill now'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              emptyIcon: Icons.autorenew_outlined,
              emptyTitle: 'No subscriptions found',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateInvoice(StaffSubscription sub) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Reuses the money service — the same endpoint the Next Bills screen
      // calls, so behaviour stays identical wherever staff trigger it.
      final invoice = await ref
          .read(billingMoneyServiceProvider)
          .generateInvoice(sub.id);
      ref.invalidate(dashboardProvider);
      _listKey.currentState?.reload();
      messenger.showSnackBar(SnackBar(content: Text(invoice.message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
