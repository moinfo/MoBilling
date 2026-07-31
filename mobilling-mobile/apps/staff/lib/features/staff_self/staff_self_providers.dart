import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<StaffSelfService> staffSelfServiceProvider =
    Provider<StaffSelfService>(
  (ref) => StaffSelfService(ref.watch(apiClientProvider)),
);

final AutoDisposeFutureProvider<MyAttendance> myAttendanceProvider =
    FutureProvider.autoDispose<MyAttendance>(
  (ref) => ref.watch(staffSelfServiceProvider).myAttendance(),
);

/// Reports keyed by type filter (null = all).
final AutoDisposeFutureProviderFamily<List<StaffReport>, String?>
    staffReportsProvider =
    FutureProvider.autoDispose.family<List<StaffReport>, String?>(
  (ref, reportType) =>
      ref.watch(staffSelfServiceProvider).staffReports(reportType: reportType),
);

final AutoDisposeFutureProviderFamily<List<StaffTarget>, String?>
    staffTargetsProvider =
    FutureProvider.autoDispose.family<List<StaffTarget>, String?>(
  (ref, status) =>
      ref.watch(staffSelfServiceProvider).staffTargets(status: status),
);

final AutoDisposeFutureProvider<List<SystemVerification>>
    systemVerificationsProvider =
    FutureProvider.autoDispose<List<SystemVerification>>(
  (ref) => ref.watch(staffSelfServiceProvider).systemVerifications(),
);
