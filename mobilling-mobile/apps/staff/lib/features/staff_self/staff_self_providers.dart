import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';
import '../admin/admin_providers.dart';

/// One calendar month, the key both deduction ledgers and the attendance
/// report are fetched by.
typedef MonthKey = ({int year, int month});

MonthKey monthKeyOf(DateTime date) => (year: date.year, month: date.month);

final Provider<StaffSelfService> staffSelfServiceProvider =
    Provider<StaffSelfService>(
      (ref) => StaffSelfService(ref.watch(apiClientProvider)),
    );

final AutoDisposeFutureProvider<MyAttendance> myAttendanceProvider =
    FutureProvider.autoDispose<MyAttendance>(
      (ref) => ref.watch(staffSelfServiceProvider).myAttendance(),
    );

/// GET /attendance/my-report — my own month, day by day.
final AutoDisposeFutureProviderFamily<AttendanceReport, MonthKey>
myAttendanceReportProvider = FutureProvider.autoDispose
    .family<AttendanceReport, MonthKey>(
      (ref, month) => ref
          .watch(staffSelfServiceProvider)
          .myAttendanceReport(month: month.month, year: month.year),
    );

/// GET /attendance/day, keyed by `Y-m-d`. Needs `attendance.manage`.
final AutoDisposeFutureProviderFamily<AttendanceBoard, String>
attendanceBoardProvider = FutureProvider.autoDispose
    .family<AttendanceBoard, String>(
      (ref, date) => ref
          .watch(staffSelfServiceProvider)
          .attendanceBoard(date: DateTime.parse(date)),
    );

/// GET /attendance/dashboard. Needs `attendance.manage`.
final AutoDisposeFutureProvider<AttendanceOverview> attendanceOverviewProvider =
    FutureProvider.autoDispose<AttendanceOverview>(
      (ref) => ref.watch(staffSelfServiceProvider).attendanceOverview(),
    );

/// GET /attendance/penalties. Needs `attendance.manage`.
final AutoDisposeFutureProviderFamily<PenaltyLedger, MonthKey>
attendancePenaltiesProvider = FutureProvider.autoDispose
    .family<PenaltyLedger, MonthKey>(
      (ref, month) => ref
          .watch(staffSelfServiceProvider)
          .attendancePenalties(month: month.month, year: month.year),
    );

/// Reports keyed by type filter (null = all).
final AutoDisposeFutureProviderFamily<List<StaffReport>, String?>
staffReportsProvider = FutureProvider.autoDispose
    .family<List<StaffReport>, String?>(
      (ref, reportType) => ref
          .watch(staffSelfServiceProvider)
          .staffReports(reportType: reportType),
    );

/// GET /staff-reports/dashboard — my cadence, plus the team block reviewers
/// get.
final AutoDisposeFutureProvider<StaffReportsDashboard>
staffReportsDashboardProvider =
    FutureProvider.autoDispose<StaffReportsDashboard>(
      (ref) => ref.watch(staffSelfServiceProvider).staffReportsDashboard(),
    );

/// GET /staff-reports/penalties. Needs `staff_reports.review`.
final AutoDisposeFutureProviderFamily<PenaltyLedger, MonthKey>
staffReportPenaltiesProvider = FutureProvider.autoDispose
    .family<PenaltyLedger, MonthKey>(
      (ref, month) => ref
          .watch(staffSelfServiceProvider)
          .staffReportPenalties(month: month.month, year: month.year),
    );

/// The tenant's active staff, from `/staff-reports/supervisors`. Needs
/// `staff_reports.review`; only the target form asks for it.
final AutoDisposeFutureProvider<List<StaffColleague>> colleaguesProvider =
    FutureProvider.autoDispose<List<StaffColleague>>(
      (ref) => ref.watch(staffSelfServiceProvider).colleagues(),
    );

final AutoDisposeFutureProviderFamily<List<StaffTarget>, String?>
staffTargetsProvider = FutureProvider.autoDispose
    .family<List<StaffTarget>, String?>(
      (ref, status) =>
          ref.watch(staffSelfServiceProvider).staffTargets(status: status),
    );

/// GET /staff-targets/summary — commission earned on verified targets.
final AutoDisposeFutureProvider<List<TargetCommission>>
targetCommissionsProvider = FutureProvider.autoDispose<List<TargetCommission>>(
  (ref) => ref.watch(staffSelfServiceProvider).targetCommissions(),
);

final AutoDisposeFutureProvider<List<SystemVerification>>
systemVerificationsProvider =
    FutureProvider.autoDispose<List<SystemVerification>>(
      (ref) => ref.watch(staffSelfServiceProvider).systemVerifications(),
    );

/// The three reference lists the system-record form picks from. Each is a
/// separate permission on the API, so the form reports whichever one 403s
/// rather than failing as a whole.
final AutoDisposeFutureProvider<List<SystemOption>> systemsProvider =
    FutureProvider.autoDispose<List<SystemOption>>(
      (ref) => ref.watch(staffSelfServiceProvider).systems(),
    );

final AutoDisposeFutureProvider<List<SystemOption>> systemPropertiesProvider =
    FutureProvider.autoDispose<List<SystemOption>>(
      (ref) => ref.watch(staffSelfServiceProvider).systemProperties(),
    );

final AutoDisposeFutureProvider<List<BankAccount>> recordBankAccountsProvider =
    FutureProvider.autoDispose<List<BankAccount>>((ref) async {
      final page = await ref
          .watch(adminServiceProvider)
          .bankAccounts(perPage: 200);
      return page.items.where((a) => a.isActive).toList();
    });
