import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<BillingCatalogService> billingCatalogServiceProvider =
    Provider<BillingCatalogService>(
      (ref) => BillingCatalogService(ref.watch(apiClientProvider)),
    );

final AutoDisposeFutureProviderFamily<StaffDocument, String>
staffDocumentProvider = FutureProvider.autoDispose
    .family<StaffDocument, String>(
      (ref, id) => ref.watch(billingCatalogServiceProvider).document(id),
    );

/// Add-ons, config groups and coupons are all unpaginated, keyed by search.
final AutoDisposeFutureProviderFamily<List<StaffProductAddon>, String?>
addonsProvider = FutureProvider.autoDispose
    .family<List<StaffProductAddon>, String?>(
      (ref, search) =>
          ref.watch(billingCatalogServiceProvider).addons(search: search),
    );

final AutoDisposeFutureProviderFamily<List<StaffConfigGroup>, String?>
configGroupsProvider = FutureProvider.autoDispose
    .family<List<StaffConfigGroup>, String?>(
      (ref, search) =>
          ref.watch(billingCatalogServiceProvider).configGroups(search: search),
    );

final AutoDisposeFutureProviderFamily<List<StaffCoupon>, String?>
couponsProvider = FutureProvider.autoDispose.family<List<StaffCoupon>, String?>(
  (ref, search) =>
      ref.watch(billingCatalogServiceProvider).coupons(search: search),
);
