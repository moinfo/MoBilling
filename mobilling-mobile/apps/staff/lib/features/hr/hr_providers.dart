import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<HrService> hrServiceProvider = Provider<HrService>(
  (ref) => HrService(ref.watch(apiClientProvider)),
);

// ── Leave ────────────────────────────────────────────────────────────────

final AutoDisposeFutureProvider<List<LeaveType>> leaveTypesProvider =
    FutureProvider.autoDispose<List<LeaveType>>(
      (ref) => ref.watch(hrServiceProvider).leaveTypes(),
    );

final AutoDisposeFutureProvider<List<MyLeaveBalance>> myLeaveBalanceProvider =
    FutureProvider.autoDispose<List<MyLeaveBalance>>(
      (ref) => ref.watch(hrServiceProvider).myLeaveBalance(),
    );

/// Leave requests keyed by status filter (null = all). Scope is the
/// server's call — own, team, or tenant — so one provider serves the "My
/// requests" and "Team" views alike.
final AutoDisposeFutureProviderFamily<List<LeaveRequest>, String?>
leaveRequestsProvider = FutureProvider.autoDispose
    .family<List<LeaveRequest>, String?>(
      (ref, status) =>
          ref.watch(hrServiceProvider).leaveRequests(status: status),
    );

/// Every employee's explicit allocations for a year (HR view).
final AutoDisposeFutureProviderFamily<LeaveBalancesPage, int>
leaveBalancesProvider = FutureProvider.autoDispose
    .family<LeaveBalancesPage, int>(
      (ref, year) => ref.watch(hrServiceProvider).leaveBalances(year: year),
    );

// ── Payroll ──────────────────────────────────────────────────────────────

final AutoDisposeFutureProvider<List<PayrollRun>> payrollRunsProvider =
    FutureProvider.autoDispose<List<PayrollRun>>(
      (ref) => ref.watch(hrServiceProvider).payrollRuns(),
    );

final AutoDisposeFutureProviderFamily<PayrollRun, String> payrollRunProvider =
    FutureProvider.autoDispose.family<PayrollRun, String>(
      (ref, id) => ref.watch(hrServiceProvider).payrollRun(id),
    );

final AutoDisposeFutureProvider<List<Payslip>> myPayslipsProvider =
    FutureProvider.autoDispose<List<Payslip>>(
      (ref) => ref.watch(hrServiceProvider).myPayslips(),
    );

final AutoDisposeFutureProvider<List<StaffSalary>> salariesProvider =
    FutureProvider.autoDispose<List<StaffSalary>>(
      (ref) => ref.watch(hrServiceProvider).salaries(),
    );

final AutoDisposeFutureProvider<List<Loan>> loansProvider =
    FutureProvider.autoDispose<List<Loan>>(
      (ref) => ref.watch(hrServiceProvider).loans(),
    );

final AutoDisposeFutureProviderFamily<List<LoanPayment>, String>
loanPaymentsProvider = FutureProvider.autoDispose
    .family<List<LoanPayment>, String>(
      (ref, loanId) => ref.watch(hrServiceProvider).loanPayments(loanId),
    );

final AutoDisposeFutureProvider<List<SalaryAdvance>> salaryAdvancesProvider =
    FutureProvider.autoDispose<List<SalaryAdvance>>(
      (ref) => ref.watch(hrServiceProvider).salaryAdvances(),
    );
