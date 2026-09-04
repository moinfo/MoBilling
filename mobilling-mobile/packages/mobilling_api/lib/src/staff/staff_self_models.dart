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
      settings: AttendanceSettings.fromJson(
        data.object('settings') ?? const {},
      ),
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
  bool get isClean => !absent && !late && !leftEarly && !noCheckout;

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
    this.waived = false,
    this.waiveReason,
  });

  final String id;

  /// absent | late | left_early | no_checkout.
  final String penaltyType;
  final double amount;
  final DateTime? date;
  final String? notes;

  /// `/attendance/mine` only ever returns unwaived charges, so this is false
  /// there; the manager ledger (`/attendance/penalties`) returns both.
  final bool waived;
  final String? waiveReason;

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
        waived: json.flag('waived'),
        waiveReason: json.str('waive_reason'),
      );
}

class AttendanceSettings {
  const AttendanceSettings({
    required this.penaltiesEnabled,
    this.checkInTime,
    this.checkOutTime,
    this.workingDays = const [1, 2, 3, 4, 5],
    this.penaltyAbsent,
    this.penaltyLate,
    this.penaltyLeftEarly,
    this.penaltyNoCheckout,
  });

  final bool penaltiesEnabled;
  final String? checkInTime;
  final String? checkOutTime;

  /// ISO weekdays, 1 = Monday. Only present on `GET/PUT /attendance/settings`
  /// — [MyAttendance]'s embedded settings omit it.
  final List<int> workingDays;
  final double? penaltyAbsent;
  final double? penaltyLate;
  final double? penaltyLeftEarly;
  final double? penaltyNoCheckout;

  factory AttendanceSettings.fromJson(Map<String, dynamic> json) {
    final days = json['working_days'];
    return AttendanceSettings(
      penaltiesEnabled: json.flag('penalties_enabled'),
      checkInTime: json.str('check_in_time'),
      checkOutTime: json.str('check_out_time'),
      workingDays: days is List
          ? days.map(readInt).toList()
          : const [1, 2, 3, 4, 5],
      penaltyAbsent: json['penalty_absent'] == null
          ? null
          : json.money('penalty_absent'),
      penaltyLate: json['penalty_late'] == null
          ? null
          : json.money('penalty_late'),
      penaltyLeftEarly: json['penalty_left_early'] == null
          ? null
          : json.money('penalty_left_early'),
      penaltyNoCheckout: json['penalty_no_checkout'] == null
          ? null
          : json.money('penalty_no_checkout'),
    );
  }
}

// ---------------------------------------------------------------------------
// Attendance — iVMS import
// ---------------------------------------------------------------------------

/// `POST /attendance/import/preview` — the server's best-guess column mapping
/// plus a handful of sample rows, so the confirmation form can pre-fill.
class AttendanceImportPreview {
  const AttendanceImportPreview({
    required this.headers,
    required this.rows,
    required this.total,
    required this.guess,
  });

  final List<String> headers;

  /// The first ~8 data rows, as raw cell strings.
  final List<List<String>> rows;
  final int total;
  final AttendanceImportGuess guess;

  factory AttendanceImportPreview.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final rawRows = data['rows'];
    return AttendanceImportPreview(
      headers: data.strings('headers'),
      rows: rawRows is List
          ? [
              for (final row in rawRows)
                if (row is List) [for (final cell in row) cell.toString()],
            ]
          : const [],
      total: data.count('total'),
      guess: AttendanceImportGuess.fromJson(data.object('guess') ?? const {}),
    );
  }
}

/// The server's guess at which column is which — 0-based indexes into
/// [AttendanceImportPreview.headers]/`rows`.
class AttendanceImportGuess {
  const AttendanceImportGuess({
    required this.matchBy,
    required this.identityCol,
    required this.timeMode,
    this.dateCol,
    this.inCol,
    this.outCol,
    this.timeCol,
    this.employeeNoCol,
  });

  /// name | employee_no.
  final String matchBy;
  final int identityCol;

  /// single | inout.
  final String timeMode;
  final int? dateCol;
  final int? inCol;
  final int? outCol;
  final int? timeCol;
  final int? employeeNoCol;

  factory AttendanceImportGuess.fromJson(Map<String, dynamic> json) =>
      AttendanceImportGuess(
        matchBy: json.strOr('match_by', 'name'),
        identityCol: json.count('identity_col'),
        timeMode: json.strOr('time_mode', 'single'),
        dateCol: json['date_col'] == null ? null : json.count('date_col'),
        inCol: json['in_col'] == null ? null : json.count('in_col'),
        outCol: json['out_col'] == null ? null : json.count('out_col'),
        timeCol: json['time_col'] == null ? null : json.count('time_col'),
        employeeNoCol: json['employee_no_col'] == null
            ? null
            : json.count('employee_no_col'),
      );
}

/// `POST /attendance/import/commit` — the outcome of applying a confirmed
/// column mapping.
class AttendanceImportResult {
  const AttendanceImportResult({
    required this.days,
    required this.matchedRows,
    required this.unmatched,
    required this.skipped,
    required this.linked,
  });

  final int days;
  final int matchedRows;

  /// Identity text (a name or employee number) → how many rows it appeared
  /// on that could not be matched to a staff member.
  final Map<String, int> unmatched;
  final int skipped;
  final int linked;

  factory AttendanceImportResult.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final unmatched = data.object('unmatched') ?? const <String, dynamic>{};
    return AttendanceImportResult(
      days: data.count('days'),
      matchedRows: data.count('matched_rows'),
      unmatched: {
        for (final entry in unmatched.entries) entry.key: readInt(entry.value),
      },
      skipped: data.count('skipped'),
      linked: data.count('linked'),
    );
  }
}

// ---------------------------------------------------------------------------
// Attendance — HIKVISION device webhook
// ---------------------------------------------------------------------------

class DeviceAttendanceConfig {
  const DeviceAttendanceConfig({
    required this.name,
    required this.isActive,
    required this.webhookUrl,
    this.lastEventAt,
  });

  final String name;
  final bool isActive;
  final String webhookUrl;
  final DateTime? lastEventAt;

  factory DeviceAttendanceConfig.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return DeviceAttendanceConfig(
      name: data.strOr('name', '—'),
      isActive: data.flag('is_active'),
      webhookUrl: data.strOr('webhook_url', ''),
      lastEventAt: data.date('last_event_at'),
    );
  }
}

/// One raw webhook delivery, for troubleshooting a device that isn't
/// checking anyone in.
class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.contentType,
    required this.payload,
    this.employeeNo,
    this.eventTime,
    this.createdAt,
  });

  final String id;
  final String contentType;

  /// The raw body, truncated server-side to 20,000 characters.
  final String payload;
  final String? employeeNo;
  final DateTime? eventTime;
  final DateTime? createdAt;

  factory DeviceEvent.fromJson(Map<String, dynamic> json) => DeviceEvent(
        id: json.id(),
        contentType: json.strOr('content_type', '—'),
        payload: json.strOr('payload', ''),
        employeeNo: json.str('employee_no'),
        eventTime: json.date('event_time'),
        createdAt: json.date('created_at'),
      );
}

class DeviceStaffMapping {
  const DeviceStaffMapping({
    required this.id,
    required this.name,
    this.deviceEmployeeNo,
  });

  final String id;
  final String name;
  final String? deviceEmployeeNo;

  bool get isLinked => deviceEmployeeNo != null && deviceEmployeeNo!.isNotEmpty;

  factory DeviceStaffMapping.fromJson(Map<String, dynamic> json) =>
      DeviceStaffMapping(
        id: json.id(),
        name: json.strOr('name', '—'),
        deviceEmployeeNo: json.str('device_employee_no'),
      );
}

/// `GET /attendance/device-mappings` — every staff member's device number,
/// plus numbers seen on the wire that no one has claimed yet.
class DeviceMappings {
  const DeviceMappings({required this.staff, required this.unlinked});

  final List<DeviceStaffMapping> staff;
  final List<String> unlinked;

  factory DeviceMappings.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return DeviceMappings(
      staff: data.list('staff', DeviceStaffMapping.fromJson),
      unlinked: data.strings('unlinked'),
    );
  }
}

// ---------------------------------------------------------------------------
// Attendance — the clerk's views (all gated `attendance.manage`)
// ---------------------------------------------------------------------------

/// GET /attendance/day — every active staff member and their marks for one
/// date, which is also the surface `POST /attendance/record` writes to.
class AttendanceBoard {
  const AttendanceBoard({
    required this.date,
    required this.staff,
    this.checkInTime,
    this.checkOutTime,
  });

  /// `Y-m-d`, echoed back by the controller.
  final String date;
  final List<AttendanceBoardRow> staff;
  final String? checkInTime;
  final String? checkOutTime;

  factory AttendanceBoard.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return AttendanceBoard(
      date: data.strOr('date', ''),
      checkInTime: data.str('check_in_time'),
      checkOutTime: data.str('check_out_time'),
      staff: data.list('staff', AttendanceBoardRow.fromJson),
    );
  }
}

/// One staff member's day. The controller merges the user onto the formatted
/// day, so the same map parses as an [AttendanceDay] too.
class AttendanceBoardRow {
  const AttendanceBoardRow({
    required this.userId,
    required this.userName,
    required this.day,
  });

  final String userId;
  final String userName;
  final AttendanceDay day;

  factory AttendanceBoardRow.fromJson(Map<String, dynamic> json) {
    final user = json.object('user');
    return AttendanceBoardRow(
      userId: user?.id() ?? '',
      userName: user?.strOr('name', '—') ?? '—',
      day: AttendanceDay.fromJson(json),
    );
  }
}

/// GET /attendance/dashboard — today's snapshot plus this month's per-staff
/// summary.
class AttendanceOverview {
  const AttendanceOverview({
    required this.monthLabel,
    required this.workingDaysSoFar,
    required this.deductionTotal,
    required this.today,
    required this.byType,
    required this.staff,
  });

  final String monthLabel;
  final int workingDaysSoFar;
  final double deductionTotal;
  final AttendanceToday today;

  /// absent | late | left_early | no_checkout → how many charges this month.
  final Map<String, int> byType;
  final List<AttendanceStaffMonth> staff;

  factory AttendanceOverview.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final byType = data.object('by_type') ?? const <String, dynamic>{};
    return AttendanceOverview(
      monthLabel: data.strOr('month_label', ''),
      workingDaysSoFar: data.count('working_days_so_far'),
      deductionTotal: data.money('deduction_total'),
      today: AttendanceToday.fromJson(data.object('today') ?? const {}),
      byType: {
        for (final key in const ['absent', 'late', 'left_early', 'no_checkout'])
          key: readInt(byType[key]),
      },
      staff: data.list('staff', AttendanceStaffMonth.fromJson),
    );
  }
}

class AttendanceToday {
  const AttendanceToday({
    required this.total,
    required this.present,
    required this.late,
    required this.leftEarly,
    required this.excused,
    required this.notRecorded,
  });

  final int total;
  final int present;
  final int late;
  final int leftEarly;
  final int excused;
  final int notRecorded;

  factory AttendanceToday.fromJson(Map<String, dynamic> json) =>
      AttendanceToday(
        total: json.count('total'),
        present: json.count('present'),
        late: json.count('late'),
        leftEarly: json.count('left_early'),
        excused: json.count('excused'),
        notRecorded: json.count('not_recorded'),
      );
}

class AttendanceStaffMonth {
  const AttendanceStaffMonth({
    required this.userId,
    required this.userName,
    required this.presentDays,
    required this.deductions,
  });

  final String userId;
  final String userName;
  final int presentDays;
  final double deductions;

  factory AttendanceStaffMonth.fromJson(Map<String, dynamic> json) {
    final user = json.object('user');
    return AttendanceStaffMonth(
      userId: user?.id() ?? '',
      userName: user?.strOr('name', '—') ?? '—',
      presentDays: json.count('present_days'),
      deductions: json.money('deductions'),
    );
  }
}

/// GET /attendance/my-report — one month, day by day, with the flags and the
/// money actually docked.
class AttendanceReport {
  const AttendanceReport({
    required this.userName,
    required this.monthLabel,
    required this.days,
    required this.totals,
    this.checkInTime,
    this.checkOutTime,
  });

  final String userName;
  final String monthLabel;
  final List<AttendanceReportDay> days;
  final AttendanceReportTotals totals;
  final String? checkInTime;
  final String? checkOutTime;

  factory AttendanceReport.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return AttendanceReport(
      userName: data.object('user')?.strOr('name', '—') ?? '—',
      monthLabel: data.strOr('month_label', ''),
      checkInTime: data.str('check_in_time'),
      checkOutTime: data.str('check_out_time'),
      days: data.list('days', AttendanceReportDay.fromJson),
      totals: AttendanceReportTotals.fromJson(
        data.object('totals') ?? const {},
      ),
    );
  }
}

/// One row of [AttendanceReport]. Unlike [AttendanceDay] this exists for every
/// calendar day so far, including the ones nobody was expected to work.
class AttendanceReportDay {
  const AttendanceReportDay({
    required this.dateKey,
    required this.weekday,
    required this.working,
    required this.holiday,
    required this.absent,
    required this.late,
    required this.leftEarly,
    required this.noCheckout,
    required this.deduction,
    this.date,
    this.status,
    this.checkInAt,
    this.checkOutAt,
  });

  /// `Y-m-d` exactly as the API returned it — what `POST /attendance/record`
  /// wants back.
  final String dateKey;
  final String weekday;
  final bool working;
  final bool holiday;
  final bool absent;
  final bool late;
  final bool leftEarly;
  final bool noCheckout;
  final double deduction;
  final DateTime? date;

  /// null | leave | sick | field.
  final String? status;
  final String? checkInAt;
  final String? checkOutAt;

  bool get isExcused => status != null && status!.isNotEmpty;
  bool get isPresent => checkInAt != null && checkInAt!.isNotEmpty;

  /// Status word for the shared chip.
  String get chipStatus {
    if (isExcused) return 'pending';
    if (absent) return 'overdue';
    if (late || leftEarly || noCheckout) return 'partial';
    if (isPresent) return 'active';
    return 'draft';
  }

  String get summary {
    if (holiday) return 'Holiday';
    if (isExcused) return status!;
    if (!working && !isPresent) return 'Off day';
    if (absent) return 'Absent';
    return [
      if (checkInAt != null) 'in $checkInAt',
      if (checkOutAt != null) 'out $checkOutAt',
      if (late) 'late',
      if (leftEarly) 'left early',
      if (noCheckout) 'no check-out',
    ].join(' · ');
  }

  factory AttendanceReportDay.fromJson(Map<String, dynamic> json) =>
      AttendanceReportDay(
        dateKey: json.strOr('date', ''),
        weekday: json.strOr('weekday', ''),
        working: json.flag('working'),
        holiday: json.flag('holiday'),
        absent: json.flag('absent'),
        late: json.flag('late'),
        leftEarly: json.flag('left_early'),
        noCheckout: json.flag('no_checkout'),
        deduction: json.money('deduction'),
        date: json.date('date'),
        status: json.str('status'),
        checkInAt: json.str('check_in_at'),
        checkOutAt: json.str('check_out_at'),
      );
}

class AttendanceReportTotals {
  const AttendanceReportTotals({
    required this.present,
    required this.late,
    required this.leftEarly,
    required this.noCheckout,
    required this.absent,
    required this.excused,
    required this.deductionTotal,
  });

  final int present;
  final int late;
  final int leftEarly;
  final int noCheckout;
  final int absent;
  final int excused;
  final double deductionTotal;

  factory AttendanceReportTotals.fromJson(Map<String, dynamic> json) =>
      AttendanceReportTotals(
        present: json.count('present'),
        late: json.count('late'),
        leftEarly: json.count('left_early'),
        noCheckout: json.count('no_checkout'),
        absent: json.count('absent'),
        excused: json.count('excused'),
        deductionTotal: json.money('deduction_total'),
      );
}

// ---------------------------------------------------------------------------
// Deduction ledgers — /attendance/penalties and /staff-reports/penalties
// ---------------------------------------------------------------------------

/// The two penalty endpoints return the same shape: a month, a grand total,
/// and one group per staff member. Only the per-item date key differs
/// (`date` for attendance, `period_date` for reports), so both parse here.
class PenaltyLedger {
  const PenaltyLedger({
    required this.monthLabel,
    required this.grandTotal,
    required this.staff,
  });

  final String monthLabel;

  /// Unwaived charges only — waiving a row drops it out of this figure.
  final double grandTotal;
  final List<PenaltyGroup> staff;

  bool get isEmpty => staff.isEmpty;

  factory PenaltyLedger.fromJson(
    Map<String, dynamic> json, {
    required String dateKey,
  }) {
    final data = json.object('data') ?? json;
    return PenaltyLedger(
      monthLabel: data.strOr('month_label', ''),
      grandTotal: data.money('grand_total'),
      staff: data.list(
        'staff',
        (row) => PenaltyGroup.fromJson(row, dateKey: dateKey),
      ),
    );
  }
}

class PenaltyGroup {
  const PenaltyGroup({
    required this.userId,
    required this.userName,
    required this.total,
    required this.items,
  });

  final String userId;
  final String userName;

  /// Unwaived only.
  final double total;
  final List<PenaltyEntry> items;

  factory PenaltyGroup.fromJson(
    Map<String, dynamic> json, {
    required String dateKey,
  }) {
    final user = json.object('user');
    return PenaltyGroup(
      userId: user?.id() ?? '',
      userName: user?.strOr('name', '—') ?? '—',
      total: json.money('total'),
      items: json.list(
        'items',
        (row) => PenaltyEntry.fromJson(row, dateKey: dateKey),
      ),
    );
  }
}

class PenaltyEntry {
  const PenaltyEntry({
    required this.id,
    required this.penaltyType,
    required this.amount,
    required this.waived,
    this.reportType,
    this.date,
    this.notes,
    this.waiveReason,
  });

  final String id;

  /// absent | late | left_early | no_checkout for attendance; `late` for a
  /// staff report, where [reportType] carries the rest of the story.
  final String penaltyType;
  final double amount;
  final bool waived;

  /// daily | weekly | monthly — staff-report ledger only.
  final String? reportType;
  final DateTime? date;
  final String? notes;
  final String? waiveReason;

  String get label {
    final base = switch (penaltyType) {
      'absent' => 'Absent',
      'late' => 'Late',
      'left_early' => 'Left early',
      'no_checkout' => 'No check-out',
      _ => penaltyType.replaceAll('_', ' '),
    };
    return reportType == null ? base : '$base $reportType report';
  }

  factory PenaltyEntry.fromJson(
    Map<String, dynamic> json, {
    required String dateKey,
  }) => PenaltyEntry(
    id: json.id(),
    penaltyType: json.strOr('penalty_type', 'late'),
    amount: json.money('amount'),
    waived: json.flag('waived'),
    reportType: json.str('report_type'),
    date: json.date(dateKey),
    notes: json.str('notes'),
    waiveReason: json.str('waive_reason'),
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

/// GET /staff-reports/dashboard — how you are doing this month against the
/// tenant's cadence, plus the team block reviewers get.
class StaffReportsDashboard {
  const StaffReportsDashboard({
    required this.thisMonth,
    required this.recentReviews,
    this.team,
  });

  /// Keyed daily | weekly | monthly.
  final Map<String, StaffReportCadence> thisMonth;
  final List<StaffReport> recentReviews;

  /// Present only for `staff_reports.review` / `staff_reports.view_all`.
  final StaffReportTeam? team;

  static const List<String> types = ['daily', 'weekly', 'monthly'];

  factory StaffReportsDashboard.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final month = data.object('this_month') ?? const <String, dynamic>{};
    final team = data.object('team');
    return StaffReportsDashboard(
      thisMonth: {
        for (final type in types)
          if (month[type] is Map)
            type: StaffReportCadence.fromJson(
              Map<String, dynamic>.from(month[type] as Map),
            ),
      },
      recentReviews: data.list('recent_reviews', StaffReport.fromJson),
      team: team == null ? null : StaffReportTeam.fromJson(team),
    );
  }
}

class StaffReportCadence {
  const StaffReportCadence({
    required this.submitted,
    required this.reviewed,
    required this.late,
    required this.target,
    required this.expected,
    required this.missing,
  });

  final int submitted;
  final int reviewed;
  final int late;

  /// How many this month asks for in total.
  final int target;

  /// How many are due by today.
  final int expected;
  final int missing;

  double get progress => target <= 0 ? 0 : (submitted / target).clamp(0.0, 1.0);

  factory StaffReportCadence.fromJson(Map<String, dynamic> json) =>
      StaffReportCadence(
        submitted: json.count('submitted'),
        reviewed: json.count('reviewed'),
        late: json.count('late'),
        target: json.count('target'),
        expected: json.count('expected'),
        missing: json.count('missing'),
      );
}

class StaffReportTeam {
  const StaffReportTeam({required this.pendingReview, required this.staff});

  final int pendingReview;
  final List<StaffReportTeamRow> staff;

  factory StaffReportTeam.fromJson(Map<String, dynamic> json) =>
      StaffReportTeam(
        pendingReview: json.count('pending_review'),
        staff: json.list('staff', StaffReportTeamRow.fromJson),
      );
}

class StaffReportTeamRow {
  const StaffReportTeamRow({
    required this.userId,
    required this.userName,
    required this.byType,
  });

  final String userId;
  final String userName;

  /// daily | weekly | monthly → that type's counts for this staff member.
  final Map<String, StaffReportCadence> byType;

  int get submitted => byType.values.fold(0, (sum, row) => sum + row.submitted);
  int get late => byType.values.fold(0, (sum, row) => sum + row.late);
  int get target => byType.values.fold(0, (sum, row) => sum + row.target);

  factory StaffReportTeamRow.fromJson(Map<String, dynamic> json) {
    final user = json.object('user');
    return StaffReportTeamRow(
      userId: user?.id() ?? '',
      userName: user?.strOr('name', '—') ?? '—',
      byType: {
        for (final type in StaffReportsDashboard.types)
          if (json[type] is Map)
            type: StaffReportCadence.fromJson(
              Map<String, dynamic>.from(json[type] as Map),
            ),
      },
    );
  }
}

/// GET /staff-reports/supervisors — the tenant's active staff, which is also
/// the list the web's target form picks an assignee from. Needs
/// `staff_reports.review`.
class StaffColleague {
  const StaffColleague({
    required this.id,
    required this.name,
    this.supervisorName,
  });

  final String id;
  final String name;
  final String? supervisorName;

  factory StaffColleague.fromJson(Map<String, dynamic> json) => StaffColleague(
    id: json.id(),
    name: json.strOr('name', '—'),
    supervisorName: json.object('supervisor')?.str('name'),
  );
}

/// `GET/PUT /staff-reports/settings` — the cadence and penalties every
/// employee is measured against. Needs `staff_reports.submit` (read) /
/// `staff_reports.review` (write).
class StaffReportSettings {
  const StaffReportSettings({
    required this.dailyTarget,
    required this.weeklyTarget,
    required this.monthlyTarget,
    required this.weeklyDeadlineDay,
    required this.monthlyDeadlineDay,
    required this.penaltiesEnabled,
    required this.workingDays,
    this.dailyDeadlineTime,
    this.weeklyDeadlineTime,
    this.monthlyDeadlineTime,
    this.penaltyMissingDaily,
    this.penaltyLate,
    this.penaltyMissingWeekly,
    this.penaltyMissingMonthly,
  });

  final int dailyTarget;
  final int weeklyTarget;
  final int monthlyTarget;
  final String? dailyDeadlineTime;
  final String? weeklyDeadlineTime;
  final String? monthlyDeadlineTime;

  /// ISO weekday, 1 = Monday.
  final int weeklyDeadlineDay;

  /// Day of month, 1-28.
  final int monthlyDeadlineDay;
  final bool penaltiesEnabled;
  final double? penaltyMissingDaily;
  final double? penaltyLate;
  final double? penaltyMissingWeekly;
  final double? penaltyMissingMonthly;

  /// ISO weekdays a report is expected on.
  final List<int> workingDays;

  factory StaffReportSettings.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final days = data['working_days'];
    return StaffReportSettings(
      dailyTarget: data.count('daily_target', fallback: 1),
      weeklyTarget: data.count('weekly_target', fallback: 1),
      monthlyTarget: data.count('monthly_target', fallback: 1),
      dailyDeadlineTime: data.str('daily_deadline_time'),
      weeklyDeadlineTime: data.str('weekly_deadline_time'),
      monthlyDeadlineTime: data.str('monthly_deadline_time'),
      weeklyDeadlineDay: data.count('weekly_deadline_day', fallback: 5),
      monthlyDeadlineDay: data.count('monthly_deadline_day', fallback: 28),
      penaltiesEnabled: data.flag('penalties_enabled'),
      penaltyMissingDaily: data['penalty_missing_daily'] == null
          ? null
          : data.money('penalty_missing_daily'),
      penaltyLate:
          data['penalty_late'] == null ? null : data.money('penalty_late'),
      penaltyMissingWeekly: data['penalty_missing_weekly'] == null
          ? null
          : data.money('penalty_missing_weekly'),
      penaltyMissingMonthly: data['penalty_missing_monthly'] == null
          ? null
          : data.money('penalty_missing_monthly'),
      workingDays:
          days is List ? days.map(readInt).toList() : const [1, 2, 3, 4, 5],
    );
  }
}

/// One row of `GET /staff-reports/holidays`.
class StaffReportHoliday {
  const StaffReportHoliday({required this.id, this.date, this.name});

  final String id;
  final DateTime? date;
  final String? name;

  factory StaffReportHoliday.fromJson(Map<String, dynamic> json) =>
      StaffReportHoliday(
        id: json.id(),
        date: json.date('date'),
        name: json.str('name'),
      );
}

/// One row of `GET /staff-reports/supervisors` — every active employee and
/// who reviews their reports/targets.
class SupervisorAssignment {
  const SupervisorAssignment({
    required this.id,
    required this.name,
    this.supervisorId,
    this.supervisorName,
  });

  final String id;
  final String name;
  final String? supervisorId;
  final String? supervisorName;

  factory SupervisorAssignment.fromJson(Map<String, dynamic> json) {
    final supervisor = json.object('supervisor');
    return SupervisorAssignment(
      id: json.id(),
      name: json.strOr('name', '—'),
      supervisorId: supervisor?.str('id'),
      supervisorName: supervisor?.str('name'),
    );
  }
}

// ---------------------------------------------------------------------------
// Staff reports — matrix report
// ---------------------------------------------------------------------------

/// `GET /staff-reports/report` — one employee's whole month across all three
/// cadences at once, for the printable matrix.
class StaffReportMatrix {
  const StaffReportMatrix({
    required this.monthLabel,
    required this.daily,
    required this.weekly,
    required this.totals,
    this.monthly,
  });

  final String monthLabel;
  final List<StaffReportMatrixDay> daily;
  final List<StaffReportMatrixWeek> weekly;
  final StaffReportMatrixMonth? monthly;
  final StaffReportMatrixTotals totals;

  factory StaffReportMatrix.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final monthly = data.object('monthly');
    return StaffReportMatrix(
      monthLabel: data.strOr('month_label', ''),
      daily: data.list('daily', StaffReportMatrixDay.fromJson),
      weekly: data.list('weekly', StaffReportMatrixWeek.fromJson),
      monthly:
          monthly == null ? null : StaffReportMatrixMonth.fromJson(monthly),
      totals: StaffReportMatrixTotals.fromJson(data.object('totals') ?? const {}),
    );
  }
}

class StaffReportMatrixDay {
  const StaffReportMatrixDay({
    required this.dateKey,
    required this.weekday,
    required this.status,
    required this.deduction,
    this.submittedAt,
  });

  final String dateKey;
  final String weekday;

  /// submitted | missing | not_due — the server's own word for the cell.
  final String status;
  final double deduction;
  final DateTime? submittedAt;

  factory StaffReportMatrixDay.fromJson(Map<String, dynamic> json) =>
      StaffReportMatrixDay(
        dateKey: json.strOr('date', ''),
        weekday: json.strOr('weekday', ''),
        status: json.strOr('status', 'pending'),
        deduction: json.money('deduction'),
        submittedAt: json.date('submitted_at'),
      );
}

class StaffReportMatrixWeek {
  const StaffReportMatrixWeek({
    required this.weekLabel,
    required this.status,
    required this.deduction,
    this.submittedAt,
  });

  final String weekLabel;
  final String status;
  final double deduction;
  final DateTime? submittedAt;

  factory StaffReportMatrixWeek.fromJson(Map<String, dynamic> json) =>
      StaffReportMatrixWeek(
        weekLabel: json.strOr('week_label', ''),
        status: json.strOr('status', 'pending'),
        deduction: json.money('deduction'),
        submittedAt: json.date('submitted_at'),
      );
}

class StaffReportMatrixMonth {
  const StaffReportMatrixMonth({
    required this.label,
    required this.status,
    required this.deduction,
    this.submittedAt,
  });

  final String label;
  final String status;
  final double deduction;
  final DateTime? submittedAt;

  factory StaffReportMatrixMonth.fromJson(Map<String, dynamic> json) =>
      StaffReportMatrixMonth(
        label: json.strOr('label', ''),
        status: json.strOr('status', 'pending'),
        deduction: json.money('deduction'),
        submittedAt: json.date('submitted_at'),
      );
}

class StaffReportMatrixTotals {
  const StaffReportMatrixTotals({
    required this.dailyWritten,
    required this.dailyExpected,
    required this.weeklyCovered,
    required this.weeklyExpected,
    required this.late,
    required this.deductionTotal,
  });

  final int dailyWritten;
  final int dailyExpected;
  final int weeklyCovered;
  final int weeklyExpected;
  final int late;
  final double deductionTotal;

  factory StaffReportMatrixTotals.fromJson(Map<String, dynamic> json) =>
      StaffReportMatrixTotals(
        dailyWritten: json.count('daily_written'),
        dailyExpected: json.count('daily_expected'),
        weeklyCovered: json.count('weekly_covered'),
        weeklyExpected: json.count('weekly_expected'),
        late: json.count('late'),
        deductionTotal: json.money('deduction_total'),
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
    this.userId,
    this.managerId,
    this.managerName,
    this.managerCommissionType = 'none',
    this.managerCommissionValue,
    this.managerCommissionEarned,
    this.groupCommissionType = 'none',
    this.groupCommissionValue,
    this.staffSalary,
    this.deductOnFailure = false,
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

  /// Who the target belongs to — needed when re-opening it in the edit form.
  final String? userId;

  /// The team lead who earns an override on this target, if any.
  final String? managerId;
  final String? managerName;

  /// none | fixed | percentage.
  final String managerCommissionType;
  final double? managerCommissionValue;

  /// What the manager actually earned — only settled once verified.
  final double? managerCommissionEarned;

  /// The all-goals-met bonus. none | fixed | percentage.
  final String groupCommissionType;
  final double? groupCommissionValue;

  /// The salary the percentage commissions and the failure deduction are
  /// computed from.
  final double? staffSalary;
  final bool deductOnFailure;

  bool get isVerified => status == 'verified';
  bool get isCancelled => status == 'cancelled';
  bool get awaitingSelfReport => status == 'active';
  bool get awaitingVerification => status == 'self_reported';

  /// The controller only lets an `active` target be edited, and refuses to
  /// delete a verified one.
  bool get isEditable => status == 'active';
  bool get isDeletable => status != 'verified';

  /// `verify` aborts on an already-verified target; anything else is fair
  /// game, though in practice a supervisor waits for the self-report.
  bool get isVerifiable => status != 'verified';

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
    userId: json.object('user')?.str('id'),
    managerId: json.object('manager')?.str('id'),
    managerName: json.object('manager')?.str('name'),
    managerCommissionType: json.strOr('manager_commission_type', 'none'),
    managerCommissionValue: json['manager_commission_value'] == null
        ? null
        : json.money('manager_commission_value'),
    managerCommissionEarned: json['manager_commission_earned'] == null
        ? null
        : json.money('manager_commission_earned'),
    groupCommissionType: json.strOr('group_commission_type', 'none'),
    groupCommissionValue: json['group_commission_value'] == null
        ? null
        : json.money('group_commission_value'),
    staffSalary: json['staff_salary'] == null
        ? null
        : json.money('staff_salary'),
    deductOnFailure: json.flag('deduct_on_failure'),
  );
}

/// One criterion as the create/edit form builds it, before the server gives it
/// an id. `commissionType` is none | fixed | percentage; a percentage is of the
/// target's `staff_salary`.
class TargetCriterionInput {
  const TargetCriterionInput({
    required this.type,
    required this.label,
    required this.goalValue,
    this.unit,
    this.commissionType = 'none',
    this.commissionValue,
  });

  /// customer_count | revenue | item_sales | custom.
  final String type;
  final String label;
  final double goalValue;
  final String? unit;
  final String commissionType;
  final double? commissionValue;

  Map<String, dynamic> toJson() => {
    'type': type,
    'label': label,
    'unit': ?unit,
    'goal_value': goalValue,
    'commission_type': commissionType,
    'commission_value': ?commissionValue,
  };

  /// Re-open an existing criterion in the edit form.
  factory TargetCriterionInput.from(TargetCriterion c) => TargetCriterionInput(
    type: c.type,
    label: c.label,
    goalValue: c.goalValue,
    unit: c.unit,
    commissionType: c.commissionType,
    commissionValue: c.commissionValue,
  );
}

/// GET /staff-targets/summary — verified commission per person, both the
/// targets they own and the ones they manage.
class TargetCommission {
  const TargetCommission({
    required this.userId,
    required this.userName,
    required this.grossCommission,
    required this.salaryDeductions,
    required this.totalCommission,
    required this.managerCommission,
    required this.targetsCount,
    required this.targets,
    required this.managedTargets,
  });

  final String userId;
  final String userName;
  final double grossCommission;
  final double salaryDeductions;

  /// Already includes [managerCommission] — the controller rolls it in.
  final double totalCommission;
  final double managerCommission;
  final int targetsCount;
  final List<TargetCommissionLine> targets;
  final List<TargetCommissionLine> managedTargets;

  factory TargetCommission.fromJson(Map<String, dynamic> json) {
    final user = json.object('user');
    return TargetCommission(
      userId: user?.id() ?? '',
      userName: user?.strOr('name', '—') ?? '—',
      grossCommission: json.money('gross_commission'),
      salaryDeductions: json.money('salary_deductions'),
      totalCommission: json.money('total_commission'),
      managerCommission: json.money('manager_commission'),
      targetsCount: json.count('targets_count'),
      targets: json.list('targets', TargetCommissionLine.fromJson),
      managedTargets: json.list(
        'managed_targets',
        TargetCommissionLine.fromJson,
      ),
    );
  }
}

class TargetCommissionLine {
  const TargetCommissionLine({
    required this.id,
    required this.title,
    required this.period,
    required this.commissionEarned,
    required this.salaryDeduction,
    this.staffName,
  });

  final String id;
  final String title;

  /// Server-composed, e.g. `01 Aug – 31 Aug 2026`.
  final String period;
  final double commissionEarned;
  final double salaryDeduction;

  /// Whose target it is — set on the managed-targets list only.
  final String? staffName;

  factory TargetCommissionLine.fromJson(Map<String, dynamic> json) =>
      TargetCommissionLine(
        id: json.id(),
        title: json.strOr('title', '—'),
        period: json.strOr('period', ''),
        commissionEarned: json.money('commission_earned'),
        salaryDeduction: json.money('salary_deduction'),
        staffName: json.object('staff')?.str('name'),
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
    this.commissionType = 'none',
    this.commissionValue,
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

  /// none | fixed | percentage — how this criterion pays when its goal is met.
  final String commissionType;
  final double? commissionValue;

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
        commissionType: json.strOr('commission_type', 'none'),
        commissionValue: json['commission_value'] == null
            ? null
            : json.money('commission_value'),
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
    this.clientId,
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
  final String? clientId;
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
      clientId: json.str('client_id'),
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
    required this.type,
    this.systemId,
    this.systemName,
    this.systemPropertyId,
    this.propertyName,
    this.bankAccountId,
    this.bankName,
    this.recordDate,
    this.notes,
    this.createdByName,
    this.receiptUrl,
  });

  final String id;
  final double amount;

  /// deposit | withdraw | charge. Required by the API on both create and
  /// update — see `StoreSystemRecordRequest::rules`.
  final String type;
  final String? systemId;
  final String? systemName;
  final String? systemPropertyId;
  final String? propertyName;
  final String? bankAccountId;
  final String? bankName;
  final DateTime? recordDate;
  final String? notes;
  final String? createdByName;

  /// Absolute URL to the receipt every record is required to carry.
  final String? receiptUrl;

  factory SystemRecord.fromJson(Map<String, dynamic> json) {
    final bank = json.object('bank_account');
    return SystemRecord(
      id: json.id(),
      amount: json.money('amount'),
      type: json.strOr('type', 'deposit'),
      systemId: json.str('system_id'),
      systemName: json.object('system')?.str('name'),
      systemPropertyId: json.str('system_property_id'),
      propertyName: json.object('system_property')?.str('name'),
      bankAccountId: json.str('bank_account_id'),
      bankName: bank == null
          ? null
          : [
              bank.str('bank_name'),
              bank.str('account_number'),
            ].whereType<String>().join(' · '),
      recordDate: json.date('record_date'),
      notes: json.str('notes'),
      createdByName: json.object('created_by')?.str('name'),
      receiptUrl: json.str('receipt_attachment_url'),
    );
  }
}

/// `type` values `StoreSystemRecordRequest` accepts, with the labels
/// `mobilling-ui/src/pages/SystemRecords.tsx` uses.
abstract final class SystemRecordTypes {
  static const values = <(String, String)>[
    ('deposit', 'Deposit'),
    ('withdraw', 'Withdraw'),
    ('charge', 'Charge'),
  ];

  static String label(String? value) =>
      values.firstWhere((v) => v.$1 == value, orElse: () => (value ?? '', value ?? '—')).$2;
}

/// A named row a system record points at — a system or a system property.
/// Both endpoints return the same three fields, so one model serves both.
class SystemOption {
  const SystemOption({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory SystemOption.fromJson(Map<String, dynamic> json) => SystemOption(
    id: json.id(),
    name: json.strOr('name', '—'),
    isActive: json.flag('is_active', fallback: true),
  );
}
