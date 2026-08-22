/// HR models: leave (Phase 1) and payroll (Phases 2–3).
///
/// Shapes follow `LeaveTypeController`, `LeaveRequestController`,
/// `PayrollRunController`, `PayslipController`, `StaffSalaryController`,
/// `LoanController` and `SalaryAdvanceController`, and the web's
/// `src/api/leave.ts` / `src/api/payroll.ts`.
library;

import '../json.dart';

/// `{id, name}` — the shape every HR endpoint uses for a related user.
class NamedUser {
  const NamedUser({required this.id, required this.name});

  final String id;
  final String name;

  factory NamedUser.fromJson(Map<String, dynamic> json) => NamedUser(
        id: json.id(),
        name: json.strOr('name', '—'),
      );
}

// ---------------------------------------------------------------------------
// Leave
// ---------------------------------------------------------------------------

class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    required this.daysPerYear,
    required this.isPaid,
    required this.isActive,
    this.color,
  });

  final String id;
  final String name;
  final int daysPerYear;
  final bool isPaid;
  final bool isActive;

  /// A hex colour chosen on the web; purely decorative.
  final String? color;

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
        id: json.id(),
        name: json.strOr('name', '—'),
        daysPerYear: json.count('days_per_year'),
        isPaid: json.flag('is_paid', fallback: true),
        isActive: json.flag('is_active', fallback: true),
        color: json.str('color'),
      );
}

/// One row of `GET /leave-requests/my-balance`: the signed-in user's
/// allocation, usage and remainder for a leave type this year.
class MyLeaveBalance {
  const MyLeaveBalance({
    required this.leaveType,
    required this.allocatedDays,
    required this.usedDays,
    required this.remainingDays,
  });

  final LeaveType leaveType;
  final int allocatedDays;
  final int usedDays;
  final int remainingDays;

  factory MyLeaveBalance.fromJson(Map<String, dynamic> json) => MyLeaveBalance(
        leaveType: LeaveType.fromJson(json.object('leave_type') ?? const {}),
        allocatedDays: json.count('allocated_days'),
        usedDays: json.count('used_days'),
        remainingDays: json.count('remaining_days'),
      );
}

/// An explicit per-employee allocation (overrides the type's default
/// `days_per_year` for that year).
class LeaveAllocation {
  const LeaveAllocation({
    required this.id,
    required this.userId,
    required this.leaveTypeId,
    required this.year,
    required this.allocatedDays,
    this.leaveType,
  });

  final String id;
  final String userId;
  final String leaveTypeId;
  final int year;
  final int allocatedDays;
  final LeaveType? leaveType;

  factory LeaveAllocation.fromJson(Map<String, dynamic> json) =>
      LeaveAllocation(
        id: json.id(),
        userId: json.id('user_id'),
        leaveTypeId: json.id('leave_type_id'),
        year: json.count('year'),
        allocatedDays: json.count('allocated_days'),
        leaveType: json.object('leave_type') == null
            ? null
            : LeaveType.fromJson(json.object('leave_type')!),
      );
}

/// `GET /leave-balances` — every active employee plus the explicit
/// allocations on file for [year]. An employee with no allocation row for a
/// type falls back to that type's `days_per_year`.
class LeaveBalancesPage {
  const LeaveBalancesPage({
    required this.year,
    required this.users,
    required this.allocations,
  });

  final int year;
  final List<NamedUser> users;
  final List<LeaveAllocation> allocations;

  factory LeaveBalancesPage.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return LeaveBalancesPage(
      year: data.count('year', fallback: DateTime.now().year),
      users: data.list('users', NamedUser.fromJson),
      allocations: data.list('balances', LeaveAllocation.fromJson),
    );
  }

  /// The allocation for one employee/type, or null when the default applies.
  LeaveAllocation? allocationFor(String userId, String leaveTypeId) {
    for (final a in allocations) {
      if (a.userId == userId && a.leaveTypeId == leaveTypeId) return a;
    }
    return null;
  }
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.userId,
    required this.leaveTypeId,
    required this.days,
    required this.status,
    this.startDate,
    this.endDate,
    this.reason,
    this.reviewedAt,
    this.reviewNote,
    this.createdAt,
    this.user,
    this.leaveType,
    this.reviewer,
  });

  final String id;
  final String userId;
  final String leaveTypeId;
  final int days;

  /// pending | approved | rejected | cancelled.
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? reason;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime? createdAt;
  final NamedUser? user;
  final LeaveType? leaveType;
  final NamedUser? reviewer;

  bool get isPending => status == 'pending';

  String get userName => user?.name ?? '—';
  String get typeName => leaveType?.name ?? '—';

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: json.id(),
        userId: json.id('user_id'),
        leaveTypeId: json.id('leave_type_id'),
        days: json.count('days'),
        status: json.strOr('status', 'pending'),
        startDate: json.date('start_date'),
        endDate: json.date('end_date'),
        reason: json.str('reason'),
        reviewedAt: json.date('reviewed_at'),
        reviewNote: json.str('review_note'),
        createdAt: json.date('created_at'),
        user: json.object('user') == null
            ? null
            : NamedUser.fromJson(json.object('user')!),
        leaveType: json.object('leave_type') == null
            ? null
            : LeaveType.fromJson(json.object('leave_type')!),
        reviewer: json.object('reviewer') == null
            ? null
            : NamedUser.fromJson(json.object('reviewer')!),
      );
}

// ---------------------------------------------------------------------------
// Payroll
// ---------------------------------------------------------------------------

/// One labelled amount inside a payslip breakdown (`{name, amount}`).
class BreakdownLine {
  const BreakdownLine({required this.name, required this.amount});

  final String name;
  final double amount;

  factory BreakdownLine.fromJson(Map<String, dynamic> json) => BreakdownLine(
        name: json.strOr('name', '—'),
        amount: json.money('amount'),
      );
}

class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.monthKey,
    required this.status,
    required this.payslipsCount,
    required this.payslips,
    this.generatedAt,
    this.finalizedAt,
    this.generatedBy,
    this.finalizedBy,
  });

  final String id;

  /// `YYYY-MM`.
  final String monthKey;

  /// draft | finalized.
  final String status;

  /// From `withCount` on the list; on the detail it is the loaded list's
  /// length.
  final int payslipsCount;
  final List<Payslip> payslips;
  final DateTime? generatedAt;
  final DateTime? finalizedAt;
  final NamedUser? generatedBy;
  final NamedUser? finalizedBy;

  bool get isDraft => status == 'draft';
  bool get isFinalized => status == 'finalized';

  double get netPayTotal =>
      payslips.fold<double>(0, (sum, p) => sum + p.netPay);
  double get employerCostTotal =>
      payslips.fold<double>(0, (sum, p) => sum + p.employerCostTotal);

  factory PayrollRun.fromJson(Map<String, dynamic> json) {
    final payslips = json.list('payslips', Payslip.fromJson);
    return PayrollRun(
      id: json.id(),
      monthKey: json.strOr('month_key', '—'),
      status: json.strOr('status', 'draft'),
      payslipsCount: json['payslips_count'] == null
          ? payslips.length
          : json.count('payslips_count'),
      payslips: payslips,
      generatedAt: json.date('generated_at'),
      finalizedAt: json.date('finalized_at'),
      generatedBy: json.object('generated_by') == null
          ? null
          : NamedUser.fromJson(json.object('generated_by')!),
      finalizedBy: json.object('finalized_by') == null
          ? null
          : NamedUser.fromJson(json.object('finalized_by')!),
    );
  }
}

class Payslip {
  const Payslip({
    required this.id,
    required this.payrollRunId,
    required this.userId,
    required this.basicSalary,
    required this.allowancesTotal,
    required this.allowancesBreakdown,
    required this.grossPay,
    required this.statutoryEmployeeTotal,
    required this.statutoryEmployeeBreakdown,
    required this.taxableIncome,
    required this.payeAmount,
    required this.otherDeductionsTotal,
    required this.deductionsBreakdown,
    required this.netPay,
    required this.statutoryEmployerTotal,
    required this.statutoryEmployerBreakdown,
    required this.employerCostTotal,
    this.user,
    this.runMonthKey,
    this.runStatus,
    this.createdAt,
  });

  final String id;
  final String payrollRunId;
  final String userId;
  final double basicSalary;
  final double allowancesTotal;
  final List<BreakdownLine> allowancesBreakdown;
  final double grossPay;
  final double statutoryEmployeeTotal;
  final List<BreakdownLine> statutoryEmployeeBreakdown;
  final double taxableIncome;
  final double payeAmount;
  final double otherDeductionsTotal;
  final List<BreakdownLine> deductionsBreakdown;
  final double netPay;
  final double statutoryEmployerTotal;
  final List<BreakdownLine> statutoryEmployerBreakdown;
  final double employerCostTotal;
  final NamedUser? user;

  /// Present on `/payslips/mine` (run loaded) — the month this pays.
  final String? runMonthKey;
  final String? runStatus;
  final DateTime? createdAt;

  String get userName => user?.name ?? '—';

  factory Payslip.fromJson(Map<String, dynamic> json) {
    final run = json.object('payroll_run');
    return Payslip(
      id: json.id(),
      payrollRunId: json.id('payroll_run_id'),
      userId: json.id('user_id'),
      basicSalary: json.money('basic_salary'),
      allowancesTotal: json.money('allowances_total'),
      allowancesBreakdown:
          json.list('allowances_breakdown', BreakdownLine.fromJson),
      grossPay: json.money('gross_pay'),
      statutoryEmployeeTotal: json.money('statutory_employee_total'),
      statutoryEmployeeBreakdown:
          json.list('statutory_employee_breakdown', BreakdownLine.fromJson),
      taxableIncome: json.money('taxable_income'),
      payeAmount: json.money('paye_amount'),
      otherDeductionsTotal: json.money('other_deductions_total'),
      deductionsBreakdown:
          json.list('deductions_breakdown', BreakdownLine.fromJson),
      netPay: json.money('net_pay'),
      statutoryEmployerTotal: json.money('statutory_employer_total'),
      statutoryEmployerBreakdown:
          json.list('statutory_employer_breakdown', BreakdownLine.fromJson),
      employerCostTotal: json.money('employer_cost_total'),
      user: json.object('user') == null
          ? null
          : NamedUser.fromJson(json.object('user')!),
      runMonthKey: run?.str('month_key'),
      runStatus: run?.str('status'),
      createdAt: json.date('created_at'),
    );
  }
}

class StaffSalary {
  const StaffSalary({
    required this.id,
    required this.userId,
    required this.basicSalary,
    this.effectiveFrom,
    this.notes,
    this.user,
  });

  final String id;
  final String userId;
  final double basicSalary;
  final DateTime? effectiveFrom;
  final String? notes;
  final NamedUser? user;

  String get userName => user?.name ?? '—';

  factory StaffSalary.fromJson(Map<String, dynamic> json) => StaffSalary(
        id: json.id(),
        userId: json.id('user_id'),
        basicSalary: json.money('basic_salary'),
        effectiveFrom: json.date('effective_from'),
        notes: json.str('notes'),
        user: json.object('user') == null
            ? null
            : NamedUser.fromJson(json.object('user')!),
      );
}

class Loan {
  const Loan({
    required this.id,
    required this.userId,
    required this.principal,
    required this.balance,
    required this.monthlyInstallment,
    required this.status,
    this.issuedDate,
    this.notes,
    this.user,
  });

  final String id;
  final String userId;
  final double principal;
  final double balance;
  final double monthlyInstallment;

  /// active | paid_off | cancelled.
  final String status;
  final DateTime? issuedDate;
  final String? notes;
  final NamedUser? user;

  String get userName => user?.name ?? '—';
  bool get isActive => status == 'active';

  factory Loan.fromJson(Map<String, dynamic> json) => Loan(
        id: json.id(),
        userId: json.id('user_id'),
        principal: json.money('principal'),
        balance: json.money('balance'),
        monthlyInstallment: json.money('monthly_installment'),
        status: json.strOr('status', 'active'),
        issuedDate: json.date('issued_date'),
        notes: json.str('notes'),
        user: json.object('user') == null
            ? null
            : NamedUser.fromJson(json.object('user')!),
      );
}

class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    this.notes,
    this.createdAt,
    this.runMonthKey,
  });

  final String id;
  final double amount;
  final double balanceAfter;
  final String? notes;
  final DateTime? createdAt;

  /// The payroll month that collected it; null for manual entries.
  final String? runMonthKey;

  factory LoanPayment.fromJson(Map<String, dynamic> json) => LoanPayment(
        id: json.id(),
        amount: json.money('amount'),
        balanceAfter: json.money('balance_after'),
        notes: json.str('notes'),
        createdAt: json.date('created_at'),
        runMonthKey: json.object('payroll_run')?.str('month_key'),
      );
}

class SalaryAdvance {
  const SalaryAdvance({
    required this.id,
    required this.userId,
    required this.amount,
    required this.recoveryMonthKey,
    required this.status,
    this.issuedDate,
    this.notes,
    this.user,
  });

  final String id;
  final String userId;
  final double amount;

  /// `YYYY-MM` of the payroll that recovers it.
  final String recoveryMonthKey;

  /// pending | recovered | cancelled.
  final String status;
  final DateTime? issuedDate;
  final String? notes;
  final NamedUser? user;

  String get userName => user?.name ?? '—';
  bool get isPending => status == 'pending';

  factory SalaryAdvance.fromJson(Map<String, dynamic> json) => SalaryAdvance(
        id: json.id(),
        userId: json.id('user_id'),
        amount: json.money('amount'),
        recoveryMonthKey: json.strOr('recovery_month_key', '—'),
        status: json.strOr('status', 'pending'),
        issuedDate: json.date('issued_date'),
        notes: json.str('notes'),
        user: json.object('user') == null
            ? null
            : NamedUser.fromJson(json.object('user')!),
      );
}