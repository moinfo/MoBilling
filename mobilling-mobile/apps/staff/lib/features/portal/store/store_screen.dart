import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Order new services: the grouped product catalog.
///
/// The one surface in the portal that has something to sell, so it is the one
/// place a price is set as a figure to be read rather than as a column to be
/// audited: the handoff's price card — a tinted icon tile, the product name,
/// the amount at headline scale with its cadence beside it, and the features
/// underneath. Still paper cards on paper; the selling is done by hierarchy,
/// not by colour.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(portalCatalogProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Store', title: 'Order services'),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the catalog',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalCatalogProvider),
        ),
        data: (groups) => groups.isEmpty
            ? StateMessage(
                icon: Icons.storefront_outlined,
                title: 'Nothing to order yet',
                message:
                    'When your provider publishes a plan it will appear here.',
                actionLabel: 'Get a domain',
                onAction: () => context.push(PortalRoutes.domainSearch),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(portalCatalogProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  children: [
                    for (final (g, group) in groups.indexed) ...[
                      if (g > 0) const SizedBox(height: Spacing.lg),
                      SectionHeader(group.name),
                      const SizedBox(height: Spacing.sm),
                      for (final (i, product) in group.products.indexed) ...[
                        if (i > 0) const SizedBox(height: Spacing.sm),
                        _ProductCard(product: product),
                      ],
                    ],
                    const SizedBox(height: Spacing.xl),
                  ],
                ),
              ),
      ),
    );
  }
}

/// One product, as the handoff's price card.
class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final CatalogProduct product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settled = context.statusColors.settled;
    final extra = product.features.length - 4;

    return Card(
      child: InkWell(
        borderRadius: Radii.card,
        onTap: () => context.push(PortalRoutes.configureOrder, extra: product),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconTile(
                    product.needsDomain
                        ? Icons.dns_outlined
                        : Icons.inventory_2_outlined,
                  ),
                  const SizedBox(width: Spacing.md - 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Spacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Money(
                                  product.price,
                                  scale: MoneyScale.headline,
                                ),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            _Cadence(_cadence(product.billingCycle)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Icon(Icons.chevron_right, color: scheme.outline),
                  ),
                ],
              ),
              if (product.features.isNotEmpty) ...[
                const Divider(height: Spacing.lg),
                // The first few features only; the configure screen carries
                // the full list.
                for (final feature in product.features.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(Icons.check, size: 14, color: settled),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            feature,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (extra > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: Text(
                      '$extra more included',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The handoff's 44×44 radius-12 tinted icon tile.
class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Icon(icon, size: 22, color: scheme.primary),
    );
  }
}

/// The mono cadence beside a price — `PER MONTH`.
class _Cadence extends StatelessWidget {
  const _Cadence(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// `monthly` → `per month`, as the handoff's price-card cadence. Upper-cased
/// by whoever sets it.
String _cadence(String? cycle) => switch (cycle) {
  null || 'once' => 'one-time',
  'monthly' => 'per month',
  'quarterly' => 'per quarter',
  'semi_annually' || 'semiannually' => 'per 6 months',
  'annually' || 'yearly' => 'per year',
  'biennially' => 'per 2 years',
  'triennially' => 'per 3 years',
  final c => c.replaceAll('_', ' '),
};
