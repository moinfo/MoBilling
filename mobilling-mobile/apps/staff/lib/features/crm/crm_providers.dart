import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<CrmService> crmServiceProvider = Provider<CrmService>(
  (ref) => CrmService(ref.watch(apiClientProvider)),
);

final AutoDisposeFutureProvider<CollectionDashboard>
    collectionDashboardProvider = FutureProvider.autoDispose<CollectionDashboard>(
  (ref) => ref.watch(crmServiceProvider).collectionDashboard(),
);

final AutoDisposeFutureProvider<FollowupDashboard> followupDashboardProvider =
    FutureProvider.autoDispose<FollowupDashboard>(
  (ref) => ref.watch(crmServiceProvider).followupDashboard(),
);

/// Full follow-up list keyed by status filter (null = all).
final AutoDisposeFutureProviderFamily<List<FollowupEntry>, String?>
    followupsProvider =
    FutureProvider.autoDispose.family<List<FollowupEntry>, String?>(
  (ref, status) => ref.watch(crmServiceProvider).followups(status: status),
);

final AutoDisposeFutureProvider<SatisfactionDashboard>
    satisfactionDashboardProvider =
    FutureProvider.autoDispose<SatisfactionDashboard>(
  (ref) => ref.watch(crmServiceProvider).satisfactionDashboard(),
);

final AutoDisposeFutureProviderFamily<List<SatisfactionCall>, String?>
    satisfactionCallsProvider =
    FutureProvider.autoDispose.family<List<SatisfactionCall>, String?>(
  (ref, status) =>
      ref.watch(crmServiceProvider).satisfactionCalls(status: status),
);

final AutoDisposeFutureProviderFamily<AppointmentPage, String?>
    appointmentsProvider =
    FutureProvider.autoDispose.family<AppointmentPage, String?>(
  (ref, status) => ref.watch(crmServiceProvider).appointments(status: status),
);

final AutoDisposeFutureProvider<List<ServedService>> servedServicesProvider =
    FutureProvider.autoDispose<List<ServedService>>(
  (ref) => ref.watch(crmServiceProvider).servedServices(),
);

final AutoDisposeFutureProvider<ServedWeeklySummary>
    servedWeeklySummaryProvider =
    FutureProvider.autoDispose<ServedWeeklySummary>(
  (ref) => ref.watch(crmServiceProvider).servedWeeklySummary(),
);

final AutoDisposeFutureProviderFamily<FieldSessionDetail, String>
    fieldSessionProvider =
    FutureProvider.autoDispose.family<FieldSessionDetail, String>(
  (ref, id) => ref.watch(crmServiceProvider).fieldSession(id),
);

final AutoDisposeFutureProvider<List<FieldTarget>> fieldTargetsProvider =
    FutureProvider.autoDispose<List<FieldTarget>>(
  (ref) => ref.watch(crmServiceProvider).fieldTargets(),
);
