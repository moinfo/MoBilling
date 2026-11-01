import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<EmployeeOfMonthService> eotmServiceProvider = Provider<EmployeeOfMonthService>(
  (ref) => EmployeeOfMonthService(ref.watch(apiClientProvider)),
);

/// Null means the tenant hasn't enabled Employee of the Month, or no cycle
/// exists yet — the dashboard card renders nothing in either case.
final AutoDisposeFutureProvider<EotmCurrent?> eotmCurrentProvider =
    FutureProvider.autoDispose<EotmCurrent?>(
  (ref) => ref.watch(eotmServiceProvider).current(),
);
