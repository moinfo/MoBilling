import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Order new services: the grouped product catalog.
class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Order services')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the catalog',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(catalogProvider),
        ),
        data: (groups) => groups.isEmpty
            ? const StateMessage(
                icon: Icons.storefront_outlined,
                title: 'Nothing to order yet',
              )
            : ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  for (final group in groups) ...[
                    Text(group.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: Spacing.sm),
                    for (final product in group.products) ...[
                      Card(
                        child: InkWell(
                          borderRadius: Radii.card,
                          onTap: () => context.push(Routes.configureOrder,
                              extra: product),
                          child: Padding(
                            padding: const EdgeInsets.all(Spacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(product.name,
                                          style: theme.textTheme.titleSmall),
                                    ),
                                    Text(
                                      '${Formatting.currency(product.price)}'
                                      '${product.billingCycle == null || product.billingCycle == 'once' ? '' : ' / ${product.billingCycle!.replaceAll('_', ' ')}'}',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                              color:
                                                  theme.colorScheme.primary),
                                    ),
                                  ],
                                ),
                                if (product.features.isNotEmpty) ...[
                                  const SizedBox(height: Spacing.sm),
                                  // Show the first few features; the configure
                                  // screen has the full list.
                                  for (final feature
                                      in product.features.take(4))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 2),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.check,
                                              size: 14,
                                              color: context
                                                  .statusColors.settled),
                                          const SizedBox(width: Spacing.xs),
                                          Expanded(
                                            child: Text(feature,
                                                style: theme
                                                    .textTheme.bodySmall),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (product.features.length > 4)
                                    Text('+${product.features.length - 4} more',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                    ],
                    const SizedBox(height: Spacing.md),
                  ],
                ],
              ),
      ),
    );
  }
}
