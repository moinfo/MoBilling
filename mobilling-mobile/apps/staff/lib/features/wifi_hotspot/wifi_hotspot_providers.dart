import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<WifiHotspotService> wifiHotspotServiceProvider =
    Provider<WifiHotspotService>(
      (ref) => WifiHotspotService(ref.watch(apiClientProvider)),
    );

/// Every router, for the pickers in the plan and voucher-sale forms — small
/// per-tenant lists, so unpaginated in practice even though the endpoint
/// itself paginates.
final AutoDisposeFutureProvider<List<MikrotikRouter>> allRoutersProvider =
    FutureProvider.autoDispose<List<MikrotikRouter>>(
      (ref) => ref
          .watch(wifiHotspotServiceProvider)
          .routers(perPage: 200)
          .then((p) => p.items),
    );

/// A router's active plans, for the "sell a voucher" form — refetched per
/// selected router.
final AutoDisposeFutureProviderFamily<List<WifiPlan>, String>
plansForRouterProvider = FutureProvider.autoDispose.family<List<WifiPlan>, String>(
  (ref, routerId) => ref
      .watch(wifiHotspotServiceProvider)
      .plans(mikrotikRouterId: routerId, perPage: 100)
      .then((p) => p.items.where((plan) => plan.isActive).toList()),
);
