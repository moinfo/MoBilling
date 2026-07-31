/// Self-service for the signed-in staff member: their attendance, their
/// reports, their targets, and the system checks assigned to them.
///
/// `/attendance/mine` and `/staff-reports` are personal by default — the
/// staff-reports index widens to subordinates with `staff_reports.review` and
/// to the whole tenant with the manage permission, all decided server-side.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Attendance — AttendanceController::mine
// ---------------------------------------------------------------------------

class MyAttendance {
  const MyAttendance({
    required this.monthLabel,
    required this.presentDays,
    required this.deductionTotal,
    required this.monthRecords,
    required this.deductions,
    required this.settings,
    this.today,
  });

  final String monthLabel;
  final int presentDays;

  /// Money docked this month for lateness/absence, when penalties are on.
  final double deductionTotal;
  final List<AttendanceDay> monthRecords;
  final List<AttendancePenalty> deductions;
  final AttendanceSettings settings;

  /// Null before the first check-in of the day.
  final AttendanceDay? today;

  factory MyAttendance.fromJson(Map<String, dynamic> json) {
    // The controller wraps everything in `data`.
    final data = json.object('data') ?? json;
    final today = data.object('today');
    return MyAttendance(
      monthLabel: data.strOr('month_label', ''),
      presentDays: data.count('present_days'),
      deductionTotal: data.money('deduction_total'),
      monthRecords: data.list('month_records', AttendanceDay.fromJson),
      deductions: data.list('deductions', AttendancePenalty.fromJson),
      settings:
          AttendanceSettings.fromJson(data.object('settings') ?? const {}),
      today: today == null ? null : AttendanceDay.fromJson(today),
    );
  }
}

/// One day's attendance. The flags are computed server-side against the
/// tenant's configured hours, so the app never re-derives lateness.
class AttendanceDay {
  const AttendanceDay({
    required this.id,
    required this.absent,
    required this.late,
    required this.leftEarly,
    required this.noCheckout,
    this.date,
    this.status,
    this.statusNote,
    this.checkInAt,
    this.checkOutAt,
  });

  final String id;
  final bool absent;
  final bool late;
  final bool leftEarly;
  final bool noCheckout;
  final DateTime? date;

  /// null | leave | sick | field — an excused day, which suppresses all flags.
  final String? status;
  final String? statusNote;

  /// 'HH:mm' strings, not timestamps.
  final String? checkInAt;
  final String? checkOutAt;

  bool get isExcused => status != null && status!.isNotEmpty;
  bool get isClean =>
      !absent && !late && !leftEarly && !noCheckout;

  /// Status word for the shared chip.
  String get chipStatus {
    if (isExcused) return 'pending';
    if (absent) return 'overdue';
    if (late || leftEarly || noCheckout) return 'partial';
    return 'active';
  }

  /// Short human summary of the day.
  String get summary {
    if (isExcused) return statusNote ?? status!;
    if (absent) return 'Absent';
    return [
      if (checkInAt != null) 'in $checkInAt',
      if (checkOutAt != null) 'out $checkOutAt',
      if (late) 'late',
      if (leftEarly) 'left early',
      if (noCheckout) 'no check-out',
    ].join(' · ');
  }

  factory AttendanceDay.fromJson(Map<String, dynamic> json) => AttendanceDay(
        id: json.id(),
        absent: json.flag('absent'),
        late: json.flag('late'),
        leftEarly: json.flag('left_early'),
        noCheckout: json.flag('no_checkout'),
        date: json.date('date'),
        status: json.str('status'),
        statusNote: json.str('status_note'),
        checkInAt: json.str('check_in_at'),
        checkOutAt: json.str('check_out_at'),
      );
}

class AttendancePenalty {
  const AttendancePenalty({
    required this.id,
    required this.penaltyType,
    required this.amount,
    this.date,
    this.notes,
  });

  final String id;

  /// absent | late | left_early | no_checkout.
  final String penaltyType;
  final double amount;
  final DateTime? date;
  final String? notes;

  String get label => switch (penaltyType) {
        'absent' => 'Absent',
        'late' => 'Late arrival',
        'left_early' => 'Left early',
        'no_checkout' => 'No check-out',
        _ => penaltyType.replaceAll('_', ' '),
      };

  factory AttendancePenalty.fromJson(Map<String, dynamic> json) =>
      AttendancePenalty(
        id: json.id(),
        penaltyType: json.strOr('penalty_type', 'absent'),
        amount: json.money('amount'),
        date: json.date('date'),
        notes: json.str('notes'),
      );
}

class AttendanceSettings {
  const AttendanceSettings({
    required this.penaltiesEnabled,
    this.checkInTime,
    this.checkOutTime,
  });

  final bool penaltiesEnabled;
  final String? checkInTime;
  final String? checkOutTime;

  factory AttendanceSettings.fromJson(Map<String, dynamic> json) =>
      AttendanceSettings(
        penaltiesEnabled: json.flag('penalties_enabled'),
        checkInTime: json.str('check_in_time'),
        checkOutTime: json.str('check_out_time'),
      );
}

// ---------------------------------------------------------------------------
// Staff reports — StaffReportsController::format
// ---------------------------------------------------------------------------

class StaffReport {
  const StaffReport({
    required this.id,
    required this.reportType,
    required this.periodLabel,
    required this.status,
    required this.isLate,
    required this.replies,
    this.userName,
    this.userId,
    this.achievements,
    this.challenges,
    this.plans,
    this.notes,
    this.reviewerName,
    this.reviewedAt,
    this.reviewNotes,
    this.rating,
    this.periodDate,
  });

  final String id;

  /// daily | weekly | monthly.
  final String reportType;

  /// Server-composed, e.g. 'Week 31, 2026'.
  final String periodLabel;
  final String status;

  /// Submitted after the deadline — may attract a penalty.
  final bool isLate;
  final List<StaffReportReply> replies;
  final String? userName;
  final String? userId;
  final String? achievements;
  final String? challenges;
  final String? plans;
  final String? notes;
  final String? reviewerName;
  final DateTime? reviewedAt;
  final String? reviewNotes;
  final int? rating;
  final DateTime? periodDate;

  bool get isReviewed => reviewerName != null;

  factory StaffReport.fromJson(Map<String, dynamic> json) {
    final user = json.object('user');
    final reviewer = json.object('reviewer');
    return StaffReport(
      id: json.id(),
      reportType: json.strOr('report_type', 'daily'),
      periodLabel: json.strOr('period_label', ''),
      status: json.strOr('status', 'submitted'),
      isLate: json.flag('is_late'),
      replies: json.list('replies', StaffReportReply.fromJson),
      userName: user?.str('name'),
      userId: user?.str('id'),
      achievements: json.str('achievements'),
      challenges: json.str('challenges'),
      plans: json.str('plans'),
      notes: json.str('notes'),
      reviewerName: reviewer?.str('name'),
      reviewedAt: json.date('reviewed_at'),
      reviewNotes: json.str('review_notes'),
      rating: json['rating'] == null ? null : json.count('rating'),
      periodDate: json.date('period_date'),
    );
  }
}

class StaffReportReply {
  const StaffReportReply({
    required this.id,
    required this.message,
    required this.isReviewer,
    this.userName,
    this.createdAt,
  });

  final String id;
  final String message;

  /// True when written by someone other than the report's author.
  final bool isReviewer;
  final String? userName;
  final DateTime? createdAt;

  factory StaffReportReply.fromJson(Map<String, dynamic> json) =>
      StaffReportReply(
        id: json.id(),
        message: json.strOr('message', ''),
        isReviewer: json.flag('is_reviewer'),
        userName: json.object('user')?.str('name'),
        createdAt: json.date('created_at'),
      );
}

// ---------------------------------------------------------------------------
// Staff targets — StaffTargetsController
// ---------------------------------------------------------------------------

/// A performance target with one or more measurable criteria.
///
/// Flow: assigned (`active`) → staff enters achieved values
/// (`self_reported`) → supervisor confirms (`verified`). Commission is only
/// real once verified, which is why [totalCommission] is shown with that
/// caveat in the UI.
class StaffTarget {
  const StaffTarget({
    required this.id,
    required this.title,
    required this.status,
    required this.criteria,
    required this.grossCommission,
    required this.totalCommission,
    this.userName,
    this.assignedByName,
    this.description,
    this.periodStart,
    this.periodEnd,
    this.supervisorNotes,
    this.verifiedByName,
    this.verifiedAt,
    this.allGoalsMet,
    this.salaryDeduction,
  });

  final String id;
  final String title;

  /// active | self_reported | verified | cancelled.
  final String status;
  final List<TargetCriterion> criteria;
  final double grossCommission;
  final double totalCommission;
  final String? userName;
  final String? assignedByName;
  final String? description;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? supervisorNotes;
  final String? verifiedByName;
  final DateTime? verifiedAt;
  final bool? allGoalsMet;

  /// Docked when goals were missed and the target has deduct-on-failure set.
  final double? salaryDeduction;

  bool get isVerified => status == 'verified';
  bool get awaitingSelfReport => status == 'active';
  bool get awaitingVerification => status == 'self_reported';

  /// Status word for the shared chip.
  String get chipStatus => switch (status) {
        'verified' => 'active',
        'self_reported' => 'pending',
        'cancelled' => 'cancelled',
        _ => 'sent',
      };

  factory StaffTarget.fromJson(Map<String, dynamic> json) => StaffTarget(
        id: json.id(),
        title: json.strOr('title', '—'),
        status: json.strOr('status', 'active'),
        criteria: json.list('criteria', TargetCriterion.fromJson),
        grossCommission: json.money('gross_commission'),
        totalCommission: json.money('total_commission'),
        userName: json.object('user')?.str('name'),
        assignedByName: json.object('assigned_by')?.str('name'),
        description: json.str('description'),
        periodStart: json.date('period_start'),
        periodEnd: json.date('period_end'),
        supervisorNotes: json.str('supervisor_notes'),
        verifiedByName: json.object('verified_by')?.str('name'),
        verifiedAt: json.date('verified_at'),
        allGoalsMet: json['all_goals_met'] == null
            ? null
            : json.flag('all_goals_met'),
        salaryDeduction: json['salary_deduction_earned'] == null
            ? null
            : json.money('salary_deduction_earned'),
      );
}

class TargetCriterion {
  const TargetCriterion({
    required this.id,
    required this.label,
    required this.type,
    required this.goalValue,
    this.unit,
    this.achievedValue,
    this.verifiedValue,
    this.goalMet,
    this.commissionEarned,
  });

  final String id;
  final String label;

  /// customer_count | revenue | item_sales | custom.
  final String type;
  final double goalValue;
  final String? unit;

  /// What the staff member reported.
  final double? achievedValue;

  /// What the supervisor confirmed — this is what pays.
  final double? verifiedValue;
  final bool? goalMet;
  final double? commissionEarned;

  /// Verified beats self-reported when both exist.
  double? get effectiveValue => verifiedValue ?? achievedValue;

  double get progress =>
      goalValue <= 0 ? 0 : ((effectiveValue ?? 0) / goalValue).clamp(0.0, 1.0);

  factory TargetCriterion.fromJson(Map<String, dynamic> json) =>
      TargetCriterion(
        id: json.id(),
        label: json.strOr('label', '—'),
        type: json.strOr('type', 'custom'),
        goalValue: json.money('goal_value'),
        unit: json.str('unit'),
        achievedValue: json['achieved_value'] == null
            ? null
            : json.money('achieved_value'),
        verifiedValue: json['verified_value'] == null
            ? null
            : json.money('verified_value'),
        goalMet: json['goal_met'] == null ? null : json.flag('goal_met'),
        commissionEarned: json['commission_earned'] == null
            ? null
            : json.money('commission_earned'),
      );
}

// ---------------------------------------------------------------------------
// System verifications & records
// ---------------------------------------------------------------------------

/// A system someone is responsible for checking daily.
class SystemVerification {
  const SystemVerification({
    required this.id,
    required this.name,
    required this.isActive,
    this.domainName,
    this.clientName,
    this.assignedUserName,
    this.assignedUserId,
    this.todayStatus,
    this.todayNotes,
    this.todaySubmittedAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final String? domainName;
  final String? clientName;
  final String? assignedUserName;
  final String? assignedUserId;

  /// 'ok' | 'issue' — null when today's check has not been submitted.
  final String? todayStatus;
  final String? todayNotes;
  final DateTime? todaySubmittedAt;

  bool get checkedToday => todayStatus != null;
  bool get hasIssueToday => todayStatus == 'issue';

  factory SystemVerification.fromJson(Map<String, dynamic> json) {
    final today = json.object('todays_report');
    return SystemVerification(
      id: json.id(),
      name: json.strOr('name', '—'),
      isActive: json.flag('is_active', fallback: true),
      domainName: json.str('domain_name'),
      clientName: json.object('client')?.str('name'),
      assignedUserName: json.object('assigned_user')?.str('name'),
      assignedUserId: json.str('assigned_user_id'),
      todayStatus: today?.str('status'),
      todayNotes: today?.str('notes'),
      todaySubmittedAt: today?.date('submitted_at'),
    );
  }
}

class SystemVerificationReport {
  const SystemVerificationReport({
    required this.id,
    required this.status,
    this.systemName,
    this.userName,
    this.notes,
    this.reportDate,
  });

  final String id;
  final String status;
  final String? systemName;
  final String? userName;
  final String? notes;
  final DateTime? reportDate;

  factory SystemVerificationReport.fromJson(Map<String, dynamic> json) =>
      SystemVerificationReport(
        id: json.id(),
        status: json.strOr('status', 'ok'),
        systemName: json.object('system')?.str('name'),
        userName: json.object('user')?.str('name'),
        notes: json.str('notes'),
        reportDate: json.date('report_date'),
      );
}

/// A money/metric record logged against a system property.
class SystemRecord {
  const SystemRecord({
    required this.id,
    required this.amount,
    this.systemName,
    this.propertyName,
    this.bankName,
    this.recordDate,
    this.notes,
    this.createdByName,
  });

  final String id;
  final double amount;
  final String? systemName;
  final String? propertyName;
  final String? bankName;
  final DateTime? recordDate;
  final String? notes;
  final String? createdByName;

  factory SystemRecord.fromJson(Map<String, dynamic> json) {
    final bank = json.object('bank_account');
    return SystemRecord(
      id: json.id(),
      amount: json.money('amount'),
      systemName: json.object('system')?.str('name'),
      propertyName: json.object('system_property')?.str('name'),
      bankName: bank == null
          ? null
          : [bank.str('bank_name'), bank.str('account_number')]
              .whereType<String>()
              .join(' · '),
      recordDate: json.date('record_date'),
      notes: json.str('notes'),
      createdByName: json.object('created_by')?.str('name'),
    );
  }
}
