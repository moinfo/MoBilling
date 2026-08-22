import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<OpsService> opsServiceProvider = Provider<OpsService>(
  (ref) => OpsService(ref.watch(apiClientProvider)),
);

/// Filter for the sessions list. Plain value object so the provider family
/// can key on it.
class SessionsFilter {
  const SessionsFilter({this.type, this.active, this.search});

  final String? type;
  final bool? active;
  final String? search;

  @override
  bool operator ==(Object other) =>
      other is SessionsFilter &&
      other.type == type &&
      other.active == active &&
      other.search == search;

  @override
  int get hashCode => Object.hash(type, active, search);
}

final AutoDisposeFutureProviderFamily<SessionsPage, SessionsFilter>
    sessionsProvider =
    FutureProvider.autoDispose.family<SessionsPage, SessionsFilter>(
  (ref, filter) => ref.watch(opsServiceProvider).sessions(
        type: filter.type,
        active: filter.active,
        search: filter.search,
      ),
);

/// The live WHM listing. Keyed by the "imported" filter only; search and
/// server are narrowed client-side so a keystroke never re-polls WHM.
final AutoDisposeFutureProviderFamily<DiscoveryResult, bool?>
    discoveryProvider =
    FutureProvider.autoDispose.family<DiscoveryResult, bool?>(
  (ref, imported) =>
      ref.watch(opsServiceProvider).discoverAccounts(imported: imported),
);

final AutoDisposeFutureProvider<List<CatalogGroup>> orderCatalogProvider =
    FutureProvider.autoDispose<List<CatalogGroup>>(
  (ref) => ref.watch(opsServiceProvider).orderCatalog(),
);

final AutoDisposeFutureProvider<List<TldPricing>> orderTldsProvider =
    FutureProvider.autoDispose<List<TldPricing>>(
  (ref) => ref.watch(opsServiceProvider).orderTlds(),
);
