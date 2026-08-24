import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_money/billing_money_providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmCardList, CrmMetaLine, CrmStatusLine, FilterStrip;
import 'billing_catalog_providers.dart';

/// The catalog screens are all read-only browsers over reference data —
/// products, add-ons, configurable options and coupons. Editing them is
/// genuinely desk work (long forms, product linking), so mobile shows what is
/// configured and leaves authoring to the web.
///
/// Because they are reference data rather than money in motion, they are set
/// quietly: the price is the only figure, in the money readout; everything
/// that names it — cycle, code, what it is attached to — sits in the mono
/// eyebrow register underneath.

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
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Products & services',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name or code',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) => ref
            .read(billingCatalogServiceProvider)
            .products(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        itemBuilder: (context, product) => _ProductRow(product: product),
        emptyIcon: Icons.inventory_2_outlined,
        emptyTitle: 'No products found',
        emptyMessage: 'Try another name or product code.',
      ),
    );
  }
}

/// One catalogue line: what it is called, what it costs, and how it repeats.
///
/// Retired products keep their place in the list — they are still on old
/// invoices — so the draft chip, not absence, is what says "not on sale".
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final ProductService product;

  @override
  Widget build(BuildContext context) {
    // Cycle first: on a row this narrow the tail is what gets ellipsed, and
    // "does this bill again?" is the question a catalogue row is asked.
    final meta = [
      if (product.isRecurring) product.billingCycle!.replaceAll('_', ' '),
      if (product.unit != null) 'per ${product.unit}',
      if (product.code != null) product.code!,
      if (product.category != null) product.category!,
    ].join(' · ');

    return Card(
      child: ListTile(
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: product.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ),
        trailing: Money(product.price),
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

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Product add-ons'),
      body: CrmAsyncView(
        value: addons,
        errorTitle: 'Could not load add-ons',
        onRetry: () => ref.invalidate(addonsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.add_box_outlined,
                title: 'No add-ons configured',
                message: 'Extras sold alongside a product appear here.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(addonsProvider(null).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  children: [
                    CrmCardList(
                      children: [
                        for (final addon in items) _AddonTile(addon: addon),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// An add-on is only meaningful next to the products that offer it, so the
/// linking — or the absence of any — is the line under the name.
class _AddonTile extends StatelessWidget {
  const _AddonTile({required this.addon});

  final StaffProductAddon addon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (addon.billingCycle != null) addon.billingCycle!.replaceAll('_', ' '),
      addon.productNames.isEmpty
          ? 'not linked to a product'
          : 'on ${addon.productNames.join(', ')}',
    ].join(' · ');

    return ListTile(
      title: Text(addon.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (addon.description != null) ...[
            const SizedBox(height: 2),
            Text(
              addon.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          addon.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ],
      ),
      trailing: Money(addon.price),
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

    return Scaffold(
      appBar: const ShellTopBar(
        eyebrow: 'Billing',
        title: 'Configurable options',
      ),
      body: CrmAsyncView(
        value: groups,
        errorTitle: 'Could not load option groups',
        onRetry: () => ref.invalidate(configGroupsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.settings_input_component_outlined,
                title: 'No option groups configured',
                message: 'Choices offered while ordering a product show here.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(configGroupsProvider(null).future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _ConfigGroupCard(group: items[index]),
                ),
              ),
      ),
    );
  }
}

/// A group collapsed to its name and shape; the choices and their prices are
/// one tap away, because a screen that expands every group at once is a wall
/// of prices nobody is reading yet.
class _ConfigGroupCard extends StatelessWidget {
  const _ConfigGroupCard({required this.group});

  final StaffConfigGroup group;

  @override
  Widget build(BuildContext context) {
    final count = group.options.length;
    final meta = [
      '$count option${count == 1 ? '' : 's'}',
      if (group.productNames.isNotEmpty) 'on ${group.productNames.join(', ')}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: group.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, option) in group.options.indexed) ...[
            if (i > 0) const Divider(height: Spacing.lg),
            _OptionBlock(option: option),
          ],
        ],
      ),
    );
  }
}

class _OptionBlock extends StatelessWidget {
  const _OptionBlock({required this.option});

  final StaffConfigOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(option.name, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        CrmMetaLine(option.optionType),
        // A per-unit price and a choice's price are the same kind of figure,
        // so they are set as the same row rather than one of them hiding in
        // the caption above.
        if (option.unitPrice != null)
          _PriceRow(label: 'Per unit', price: option.unitPrice!),
        for (final choice in option.choices)
          _PriceRow(label: choice.label, price: choice.price),
      ],
    );
  }
}

/// A named price inside an option group: what the choice is called, what it
/// adds. The currency code is left off — the card is all one currency, and
/// repeating it down a column of small figures is noise.
class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.price});

  final String label;
  final double price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // "Included" is the news when a choice costs nothing; a 0.00 in the
          // money column would say it less clearly.
          if (price == 0)
            const CrmMetaLine('included')
          else
            Money(price, scale: MoneyScale.dense, showCode: false),
        ],
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

    return Scaffold(
      appBar: const ShellTopBar(
        eyebrow: 'Billing',
        title: 'Promotions & coupons',
      ),
      body: CrmAsyncView(
        value: coupons,
        errorTitle: 'Could not load coupons',
        onRetry: () => ref.invalidate(couponsProvider(null)),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.local_offer_outlined,
                title: 'No coupons configured',
                message: 'Discount codes clients can redeem appear here.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(couponsProvider(null).future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _CouponCard(coupon: items[index]),
                ),
              ),
      ),
    );
  }
}

/// A coupon reads as the code first — that is the thing a client quotes down
/// the phone — with the discount beside it and the conditions that make it
/// usable (or not) in the eyebrow line underneath.
class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.coupon});

  final StaffCoupon coupon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    coupon.code.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The one place a code is set in the utility face at
                    // reading size: it is a string to be typed, not read.
                    style: Type.mono(
                      15,
                      weight: FontWeight.w600,
                      tracking: 0.06,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                // A percentage renders itself; a fixed amount is money, and
                // is set as money.
                if (coupon.percentLabel != null)
                  Text(
                    coupon.percentLabel!,
                    style: TextStyle(
                      fontSize: MoneyScale.row.size,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: scheme.onSurface,
                      fontFeatures: Type.figures,
                    ),
                  )
                else
                  Money(coupon.value),
              ],
            ),
            if (coupon.description != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                coupon.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            CrmStatusLine(
              status: coupon.status,
              meta: [
                coupon.maxUses == null
                    ? '${coupon.uses} use${coupon.uses == 1 ? '' : 's'}'
                    : '${coupon.uses}/${coupon.maxUses} used',
                if (coupon.recurring) 'recurring',
                if (coupon.minOrder != null)
                  'min ${Formatting.amount(coupon.minOrder)}',
                if (coupon.expiresAt != null)
                  'expires ${Formatting.date(coupon.expiresAt)}',
              ].join(' · '),
            ),
            if (coupon.productNames.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              CrmMetaLine('on ${coupon.productNames.join(', ')}'),
            ],
          ],
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
  final Set<String> _billing = {};

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('suspended', 'Suspended'),
    ('cancelled', 'Cancelled'),
    ('terminated', 'Terminated'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingMoneyPermissions.subscriptionsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Subscriptions',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search client or product',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (value) {
              setState(() => _status = value);
              _listKey.currentState?.reload();
            },
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref
                  .read(billingCatalogServiceProvider)
                  .subscriptions(
                    status: _status,
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                Spacing.xl,
              ),
              itemBuilder: (context, sub) => _SubscriptionCard(
                subscription: sub,
                canGenerate: canGenerate,
                busy: _billing.contains(sub.id),
                onGenerate: () => _generateInvoice(sub),
              ),
              emptyIcon: Icons.autorenew_outlined,
              emptyTitle: 'No subscriptions found',
              emptyMessage: 'Try another client, product or filter.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateInvoice(StaffSubscription sub) async {
    if (_billing.contains(sub.id)) return;
    setState(() => _billing.add(sub.id));

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
    } finally {
      if (mounted) setState(() => _billing.remove(sub.id));
    }
  }
}

/// One subscription: whose it is, what it renews, and what it is worth per
/// cycle. Billing it early is an action with consequences, so it sits on its
/// own line under the row rather than inside the reading path.
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.canGenerate,
    required this.busy,
    required this.onGenerate,
  });

  final StaffSubscription subscription;
  final bool canGenerate;
  final bool busy;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final sub = subscription;
    final cycle = sub.billingCycle;
    final expiring = Formatting.daysUntil(sub.expireDate);
    final lapsed = expiring != null && expiring < 0;
    final billable = canGenerate && sub.status == 'active';

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              sub.clientName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  [
                    sub.productName ?? 'Service',
                    if (sub.label != null) sub.label!,
                  ].join(' — '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                CrmStatusLine(
                  status: sub.status,
                  // An expiry that has passed is the one thing on this row
                  // worth colouring.
                  tone: lapsed ? status.overdue : null,
                  // The renewal date leads and is left unlabelled: the tail of
                  // this line is what gets ellipsed on a phone, and on a
                  // subscription row the only date there is is the one it
                  // runs out on. Past it, the whole line turns red.
                  meta: [
                    if (sub.expireDate != null) Formatting.date(sub.expireDate),
                    if (cycle != null && cycle != 'once')
                      cycle.replaceAll('_', ' '),
                    if (sub.quantity > 1) '×${sub.quantity}',
                  ].join(' · '),
                ),
              ],
            ),
            trailing: Money(sub.lineTotal),
          ),
          if (billable)
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
                  label: Text(busy ? 'Billing…' : 'Bill now'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
