import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../paginated.dart';
import 'hr_models.dart';

/// HR: leave requests and payroll.
///
/// Permission checks for these routes live in the controllers rather than
/// route middleware (`authorizePermission(...)`), so a 403 here arrives as a
/// normal [ApiException] — the screens gate buttons on the same names via
/// [HrPermissions] to avoid showing actions that will only fail.
class HrService {
  const HrService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Leave
  // ---------------------------------------------------------------------

  /// GET /leave-types — active types only; open to anyone who can reach
  /// /leave so the request form can populate.
  Future<List<LeaveType>> leaveTypes() async {
    final body = await _api.get<dynamic>('/leave-types');
    return Paginated.fromJson(body, LeaveType.fromJson).items;
  }

  /// POST /leave-types — needs `leave.manage`.
  Future<LeaveType> createLeaveType({
    required String name,
    required int daysPerYear,
    bool isPaid = true,
    String? color,
  }) async {
    final body = await _api.post<Map<String, dynamic>>('/leave-types', body: {
      'name': name,
      'days_per_year': daysPerYear,
      'is_paid': isPaid,
      'color': ?color,
    });
    return LeaveType.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// PUT /leave-types/{id} — needs `leave.manage`.
  Future<LeaveType> updateLeaveType(
    String id, {
    required String name,
    required int daysPerYear,
    bool isPaid = true,
    bool isActive = true,
    String? color,
  }) async {
    final body =
        await _api.put<Map<String, dynamic>>('/leave-types/$id', body: {
      'name': name,
      'days_per_year': daysPerYear,
      'is_paid': isPaid,
      'is_active': isActive,
      'color': ?color,
    });
    return LeaveType.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// DELETE /leave-types/{id} — needs `leave.manage`.
  Future<void> deleteLeaveType(String id) =>
      _api.delete<dynamic>('/leave-types/$id');

  /// GET /leave-balances?year= — the HR view of every employee's explicit
  /// allocations. Needs `leave.manage`.
  Future<LeaveBalancesPage> leaveBalances({int? year}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/leave-balances',
      query: {'year': year},
    );
    return LeaveBalancesPage.fromJson(body);
  }

  /// POST /leave-balances — upsert one employee's allocation for a type/year.
  /// Needs `leave.manage`.
  Future<void> setLeaveBalance({
    required String userId,
    required String leaveTypeId,
    required int year,
    required int allocatedDays,
  }) =>
      _api.post<dynamic>('/leave-balances', body: {
        'user_id': userId,
        'leave_type_id': leaveTypeId,
        'year': year,
        'allocated_days': allocatedDays,
      });

  /// GET /leave-requests — scope is decided server-side: `leave.view_all`
  /// sees the tenant, `leave.review` sees self + direct reports, everyone
  /// else sees only their own.
  Future<List<LeaveRequest>> leaveRequests({
    String? status,
    String? userId,
  }) async {
    final body = await _api.get<dynamic>(
      '/leave-requests',
      query: {'status': status, 'user_id': userId},
    );
    return Paginated.fromJson(body, LeaveRequest.fromJson).items;
  }

  /// GET /leave-requests/my-balance?year=
  Future<List<MyLeaveBalance>> myLeaveBalance({int? year}) async {
    final body = await _api.get<dynamic>(
      '/leave-requests/my-balance',
      query: {'year': year},
    );
    return Paginated.fromJson(body, MyLeaveBalance.fromJson).items;
  }

  /// POST /leave-requests — request your own leave. The server counts the
  /// days (inclusive) and notifies your supervisor.
  Future<LeaveRequest> requestLeave({
    required String leaveTypeId,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    final body =
        await _api.post<Map<String, dynamic>>('/leave-requests', body: {
      'leave_type_id': leaveTypeId,
      'start_date': ymd(startDate),
      'end_date': ymd(endDate),
      'reason': ?reason,
    });
    return LeaveRequest.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// POST /leave-requests/{id}/cancel — only your own, only while pending.
  Future<void> cancelLeaveRequest(String id) =>
      _api.post<dynamic>('/leave-requests/$id/cancel');

  /// POST /leave-requests/{id}/review — approve or reject. Needs
  /// `leave.review` (own direct reports) or `leave.view_all`. Approval also
  /// marks the days excused in attendance.
  Future<void> reviewLeaveRequest(
    String id, {
    required bool approve,
    String? note,
  }) =>
      _api.post<dynamic>('/leave-requests/$id/review', body: {
        'decision': approve ? 'approved' : 'rejected',
        'review_note': ?note,
      });

  // ---------------------------------------------------------------------
  // Payroll runs & payslips
  // ---------------------------------------------------------------------

  /// GET /payroll-runs — newest month first, with payslip counts. Needs
  /// `payroll.manage` or `payroll.view`.
  Future<List<PayrollRun>> payrollRuns() async {
    final body = await _api.get<dynamic>('/payroll-runs');
    return Paginated.fromJson(body, PayrollRun.fromJson).items;
  }

  /// GET /payroll-runs/{id} — with every payslip and its employee.
  Future<PayrollRun> payrollRun(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/payroll-runs/$id');
    return PayrollRun.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// POST /payroll-runs/generate — create (or regenerate while draft) the
  /// run for [monthKey] (`YYYY-MM`). Needs `payroll.manage`. Returns the
  /// server's message, e.g. "Generated 12 payslip(s) for 2026-08.".
  Future<String?> generatePayrollRun(String monthKey) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/payroll-runs/generate',
      body: {'month_key': monthKey},
    );
    return body['message']?.toString();
  }

  /// POST /payroll-runs/{id}/finalize — locks the run and collects loan
  /// instalments / advance recoveries. Irreversible. Needs `payroll.manage`.
  Future<void> finalizePayrollRun(String id) =>
      _api.post<dynamic>('/payroll-runs/$id/finalize');

  /// DELETE /payroll-runs/{id} — draft runs only.
  Future<void> deletePayrollRun(String id) =>
      _api.delete<dynamic>('/payroll-runs/$id');

  /// GET /payslips/{id}
  Future<Payslip> payslip(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/payslips/$id');
    return Payslip.fromJson(body['data'] as Map<String, dynamic>);
  }

  /// GET /payslips/{id}/pdf — bytes, for the share sheet. Needs
  /// `payroll.manage`/`payroll.view`.
  Future<Uint8List> payslipPdf(String id) => _download('/payslips/$id/pdf');

  /// GET /payslips/mine — the signed-in employee's own payslips, any user.
  Future<List<Payslip>> myPayslips() async {
    final body = await _api.get<dynamic>('/payslips/mine');
    return Paginated.fromJson(body, Payslip.fromJson).items;
  }

  /// GET /payslips/mine/{id}/pdf
  Future<Uint8List> myPayslipPdf(String id) =>
      _download('/payslips/mine/$id/pdf');

  // ---------------------------------------------------------------------
  // Salaries, loans, advances
  // ---------------------------------------------------------------------

  /// GET /staff-salaries — newest effective date first.
  Future<List<StaffSalary>> salaries({String? userId}) async {
    final body = await _api.get<dynamic>(
      '/staff-salaries',
      query: {'user_id': userId},
    );
    return Paginated.fromJson(body, StaffSalary.fromJson).items;
  }

  /// POST /staff-salaries — a new basic salary effective from a date; the
  /// latest effective row wins at payroll time. Needs `payroll.manage`.
  Future<void> createSalary({
    required String userId,
    required double basicSalary,
    required DateTime effectiveFrom,
    String? notes,
  }) =>
      _api.post<dynamic>('/staff-salaries', body: {
        'user_id': userId,
        'basic_salary': basicSalary,
        'effective_from': ymd(effectiveFrom),
        'notes': ?notes,
      });

  /// DELETE /staff-salaries/{id}
  Future<void> deleteSalary(String id) =>
      _api.delete<dynamic>('/staff-salaries/$id');

  /// GET /loans
  Future<List<Loan>> loans({String? userId}) async {
    final body = await _api.get<dynamic>('/loans', query: {'user_id': userId});
    return Paginated.fromJson(body, Loan.fromJson).items;
  }

  /// POST /loans — needs `payroll.manage`.
  Future<void> createLoan({
    required String userId,
    required double principal,
    required double monthlyInstallment,
    required DateTime issuedDate,
    String? notes,
  }) =>
      _api.post<dynamic>('/loans', body: {
        'user_id': userId,
        'principal': principal,
        'monthly_installment': monthlyInstallment,
        'issued_date': ymd(issuedDate),
        'notes': ?notes,
      });

  /// GET /loans/{id}/payments — the repayment ledger.
  Future<List<LoanPayment>> loanPayments(String id) async {
    final body = await _api.get<dynamic>('/loans/$id/payments');
    return Paginated.fromJson(body, LoanPayment.fromJson).items;
  }

  /// POST /loans/{id}/cancel
  Future<void> cancelLoan(String id) => _api.post<dynamic>('/loans/$id/cancel');

  /// GET /salary-advances
  Future<List<SalaryAdvance>> salaryAdvances({String? userId}) async {
    final body = await _api.get<dynamic>(
      '/salary-advances',
      query: {'user_id': userId},
    );
    return Paginated.fromJson(body, SalaryAdvance.fromJson).items;
  }

  /// POST /salary-advances — recovered in full by the payroll for
  /// [recoveryMonthKey]. Needs `payroll.manage`.
  Future<void> createSalaryAdvance({
    required String userId,
    required double amount,
    required DateTime issuedDate,
    required String recoveryMonthKey,
    String? notes,
  }) =>
      _api.post<dynamic>('/salary-advances', body: {
        'user_id': userId,
        'amount': amount,
        'issued_date': ymd(issuedDate),
        'recovery_month_key': recoveryMonthKey,
        'notes': ?notes,
      });

  /// POST /salary-advances/{id}/cancel
  Future<void> cancelSalaryAdvance(String id) =>
      _api.post<dynamic>('/salary-advances/$id/cancel');

  Future<Uint8List> _download(String path) async {
    try {
      final response = await _api.raw.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// `YYYY-MM-DD`, the only date format these endpoints validate.
  static String ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// `YYYY-MM` — payroll's month key.
  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';
}

/// Permission names the HR screens gate on, verbatim from the controllers.
abstract final class HrPermissions {
  static const leaveManage = 'leave.manage';
  static const leaveReview = 'leave.review';
  static const leaveViewAll = 'leave.view_all';
  static const payrollManage = 'payroll.manage';
  static const payrollView = 'payroll.view';
}
