import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../json.dart';
import '../paginated.dart';
import 'staff_self_models.dart';

/// The signed-in staff member's own working life: attendance, reports,
/// targets, and the systems they verify.
///
/// Scope is decided server-side, not by parameters here — `/staff-reports`
/// returns only your own reports unless you hold `staff_reports.review`
/// (adds your subordinates) or the manage permission (the whole tenant).
class StaffSelfService {
  const StaffSelfService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Attendance
  // ---------------------------------------------------------------------

  /// GET /attendance/mine — this month's record, today's state, and any
  /// penalties accrued.
  Future<MyAttendance> myAttendance() async {
    final body = await _api.get<dynamic>('/attendance/mine');
    return MyAttendance.fromJson(body);
  }

  /// POST /attendance/record — write one person's check-in / check-out for one
  /// day, or mark the day excused.
  ///
  /// **Needs `attendance.manage`.** There is no self-service check-in route:
  /// ordinary staff are marked by the fingerprint device (the
  /// `/attendance/device/{token}` webhook), by an iVMS sheet import, or by
  /// whoever holds this permission — which is why the app only offers the
  /// clock to that person, exactly as the web's Record tab does.
  ///
  /// [checkIn] and [checkOut] are `HH:mm`; sending null for either **clears**
  /// it, which is how a mistaken mark is undone. Passing a [status]
  /// (leave | sick | field) excuses the whole day and wipes both times.
  /// Charges the edit contradicts are dropped immediately by the controller.
  ///
  /// Returns the day as the server now sees it, so the caller can show the
  /// recorded time without a refetch.
  Future<AttendanceDay> recordAttendance({
    required String userId,
    required DateTime date,
    String? status,
    String? statusNote,
    String? checkIn,
    String? checkOut,
  }) async {
    final body = await _api.post<dynamic>(
      '/attendance/record',
      body: {
        'user_id': userId,
        'date': _ymd(date),
        // Sent even when null: null is the instruction to clear.
        'status': status,
        'status_note': statusNote,
        'check_in': checkIn,
        'check_out': checkOut,
      },
    );
    return AttendanceDay.fromJson(_data(body));
  }

  /// GET /attendance/my-report — the signed-in user's own month, day by day.
  /// Open to everyone; [month] is 1-12.
  Future<AttendanceReport> myAttendanceReport({int? month, int? year}) async {
    final body = await _api.get<dynamic>(
      '/attendance/my-report',
      query: {'month': month, 'year': year},
    );
    return AttendanceReport.fromJson(_map(body));
  }

  /// GET /attendance/day — every active staff member's marks for one date.
  /// Needs `attendance.manage`.
  Future<AttendanceBoard> attendanceBoard({DateTime? date}) async {
    final body = await _api.get<dynamic>(
      '/attendance/day',
      query: {'date': date == null ? null : _ymd(date)},
    );
    return AttendanceBoard.fromJson(_map(body));
  }

  /// GET /attendance/dashboard — today's snapshot and the month's deductions.
  /// Needs `attendance.manage`.
  Future<AttendanceOverview> attendanceOverview() async {
    final body = await _api.get<dynamic>('/attendance/dashboard');
    return AttendanceOverview.fromJson(_map(body));
  }

  /// GET /attendance/penalties — every staff member's attendance charges for
  /// a month, waived ones included. Needs `attendance.manage`.
  Future<PenaltyLedger> attendancePenalties({int? month, int? year}) async {
    final body = await _api.get<dynamic>(
      '/attendance/penalties',
      query: {'month': month, 'year': year},
    );
    return PenaltyLedger.fromJson(_map(body), dateKey: 'date');
  }

  /// POST /attendance/penalties/{id}/waive — forgive one charge, optionally
  /// on the record. Needs `attendance.manage`. Returns the API's message.
  Future<String> waiveAttendancePenalty(String id, {String? reason}) async {
    final body = await _api.post<dynamic>(
      '/attendance/penalties/$id/waive',
      body: {'reason': ?reason},
    );
    return _message(body, 'Deduction waived.');
  }

  /// POST /attendance/penalties/{id}/unwaive — put the charge back.
  Future<String> unwaiveAttendancePenalty(String id) async {
    final body = await _api.post<dynamic>('/attendance/penalties/$id/unwaive');
    return _message(body, 'Deduction reinstated.');
  }

  // ---------------------------------------------------------------------
  // Staff reports
  // ---------------------------------------------------------------------

  /// GET /staff-reports — unpaginated.
  Future<List<StaffReport>> staffReports({
    String? reportType,
    String? status,
  }) async {
    final body = await _api.get<dynamic>(
      '/staff-reports',
      query: {'report_type': reportType, 'status': status},
    );
    return Paginated.fromJson(body, StaffReport.fromJson).items;
  }

  /// POST /staff-reports — submit a daily/weekly/monthly report.
  ///
  /// [periodDate] identifies which period this covers; the server derives the
  /// label and decides whether it counts as late.
  Future<void> submitStaffReport({
    required String reportType,
    required DateTime periodDate,
    required String achievements,
    String? challenges,
    String? plans,
    String? notes,
  }) => _api.post<dynamic>(
    '/staff-reports',
    body: {
      'report_type': reportType,
      'period_date': _ymd(periodDate),
      'achievements': achievements,
      'challenges': ?challenges,
      'plans': ?plans,
      'notes': ?notes,
    },
  );

  /// PUT /staff-reports/{id} — correct your own report.
  ///
  /// The controller refuses once the report has been reviewed, and once its
  /// period has ended: a daily report is editable only on the day it covers.
  /// Every field is replaced, so send the ones you are keeping too.
  Future<void> updateStaffReport(
    String id, {
    String? achievements,
    String? challenges,
    String? plans,
    String? notes,
  }) => _api.put<dynamic>(
    '/staff-reports/$id',
    body: {
      'achievements': achievements,
      'challenges': challenges,
      'plans': plans,
      'notes': notes,
    },
  );

  /// DELETE /staff-reports/{id} — withdraw your own report. Same two locks as
  /// [updateStaffReport]: not once reviewed, not once the period has ended.
  Future<void> deleteStaffReport(String id) =>
      _api.delete<dynamic>('/staff-reports/$id');

  /// GET /staff-reports/dashboard — your cadence for the month, plus the team
  /// block when you hold `staff_reports.review`.
  Future<StaffReportsDashboard> staffReportsDashboard() async {
    final body = await _api.get<dynamic>('/staff-reports/dashboard');
    return StaffReportsDashboard.fromJson(_map(body));
  }

  /// GET /staff-reports/penalties — late-report charges for a month, scoped
  /// server-side to your subordinates (or everyone with `view_all`).
  /// Needs `staff_reports.review`.
  Future<PenaltyLedger> staffReportPenalties({int? month, int? year}) async {
    final body = await _api.get<dynamic>(
      '/staff-reports/penalties',
      query: {'month': month, 'year': year},
    );
    return PenaltyLedger.fromJson(_map(body), dateKey: 'period_date');
  }

  /// POST /staff-reports/penalties/{id}/waive — needs `staff_reports.review`,
  /// and the charge must be one you supervise.
  Future<String> waiveStaffReportPenalty(String id, {String? reason}) async {
    final body = await _api.post<dynamic>(
      '/staff-reports/penalties/$id/waive',
      body: {'reason': ?reason},
    );
    return _message(body, 'Deduction waived.');
  }

  /// POST /staff-reports/penalties/{id}/unwaive.
  Future<String> unwaiveStaffReportPenalty(String id) async {
    final body = await _api.post<dynamic>(
      '/staff-reports/penalties/$id/unwaive',
    );
    return _message(body, 'Deduction reinstated.');
  }

  /// GET /staff-reports/supervisors — the tenant's active staff. Needs
  /// `staff_reports.review`; it is also where the web's target form gets its
  /// assignee list from.
  Future<List<StaffColleague>> colleagues() async {
    final body = await _api.get<dynamic>('/staff-reports/supervisors');
    return Paginated.fromJson(body, StaffColleague.fromJson).items;
  }

  /// POST /staff-reports/{id}/reply — the conversation thread on a report.
  Future<void> replyToStaffReport(String id, String message) => _api
      .post<dynamic>('/staff-reports/$id/reply', body: {'message': message});

  /// POST /staff-reports/{id}/review — supervisor sign-off with a rating.
  Future<void> reviewStaffReport(
    String id, {
    int? rating,
    String? reviewNotes,
  }) => _api.post<dynamic>(
    '/staff-reports/$id/review',
    body: {'rating': ?rating, 'review_notes': ?reviewNotes},
  );

  // ---------------------------------------------------------------------
  // Staff targets
  // ---------------------------------------------------------------------

  /// GET /staff-targets — unpaginated.
  Future<List<StaffTarget>> staffTargets({String? status}) async {
    final body = await _api.get<dynamic>(
      '/staff-targets',
      query: {'status': status},
    );
    return Paginated.fromJson(body, StaffTarget.fromJson).items;
  }

  /// POST /staff-targets/{id}/self-report — enter what you achieved.
  ///
  /// [values] maps criterion id to achieved value. A supervisor then verifies,
  /// and only the verified numbers pay commission.
  Future<void> selfReportTarget(
    String targetId, {
    required Map<String, double> values,
    String? notes,
  }) => _api.post<dynamic>(
    '/staff-targets/$targetId/self-report',
    body: {
      'criteria': [
        for (final entry in values.entries)
          {'id': entry.key, 'achieved_value': entry.value},
      ],
      'notes': ?notes,
    },
  );

  /// POST /staff-targets/{id}/verify — the other half of the loop: a
  /// supervisor confirms the numbers, and only these pay.
  ///
  /// Needs `staff_targets.verify`. [values] maps criterion id to the confirmed
  /// value; the server decides goal-met, per-criterion commission, the
  /// all-goals-met group bonus and any salary deduction from them, then
  /// notifies the staff member and the target's manager. A target can only be
  /// verified once.
  Future<void> verifyTarget(
    String targetId, {
    required Map<String, double> values,
    String? supervisorNotes,
  }) => _api.post<dynamic>(
    '/staff-targets/$targetId/verify',
    body: {
      'criteria': [
        for (final entry in values.entries)
          {'id': entry.key, 'verified_value': entry.value},
      ],
      'supervisor_notes': ?supervisorNotes,
    },
  );

  /// POST /staff-targets — assign a target. Needs `staff_targets.manage`.
  ///
  /// A percentage commission is of [staffSalary], so the two travel together.
  /// [managerId] gives a team lead an override on the same target and must
  /// differ from [userId].
  Future<void> createStaffTarget({
    required String userId,
    required String title,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<TargetCriterionInput> criteria,
    String? description,
    String groupCommissionType = 'none',
    double? groupCommissionValue,
    double? staffSalary,
    bool deductOnFailure = false,
    String? managerId,
    String managerCommissionType = 'none',
    double? managerCommissionValue,
  }) => _api.post<dynamic>(
    '/staff-targets',
    body: {
      'user_id': userId,
      'title': title,
      'description': ?description,
      'period_start': _ymd(periodStart),
      'period_end': _ymd(periodEnd),
      'group_commission_type': groupCommissionType,
      'group_commission_value': ?groupCommissionValue,
      'staff_salary': ?staffSalary,
      'deduct_on_failure': deductOnFailure,
      'manager_id': ?managerId,
      'manager_commission_type': managerCommissionType,
      'manager_commission_value': ?managerCommissionValue,
      'criteria': [for (final c in criteria) c.toJson()],
    },
  );

  /// PUT /staff-targets/{id} — only an `active` target can be edited, and
  /// sending [criteria] replaces the whole set (the server deletes and
  /// recreates them, dropping any values already reported against them).
  Future<void> updateStaffTarget(
    String id, {
    String? title,
    String? description,
    DateTime? periodStart,
    DateTime? periodEnd,
    List<TargetCriterionInput>? criteria,
    String? groupCommissionType,
    double? groupCommissionValue,
    double? staffSalary,
    bool? deductOnFailure,
    String? managerId,
    String? managerCommissionType,
    double? managerCommissionValue,
  }) => _api.put<dynamic>(
    '/staff-targets/$id',
    body: {
      'title': ?title,
      'description': ?description,
      // Omitted rather than sent null: the dates are `sometimes|date`, and a
      // present-but-null value would fail the date rule.
      if (periodStart != null) 'period_start': _ymd(periodStart),
      if (periodEnd != null) 'period_end': _ymd(periodEnd),
      'group_commission_type': ?groupCommissionType,
      'group_commission_value': ?groupCommissionValue,
      'staff_salary': ?staffSalary,
      'deduct_on_failure': ?deductOnFailure,
      // Always sent, null included: the controller reads `manager_id`'s
      // *presence* as "the manager is being set", and a null clears it along
      // with the override commission.
      'manager_id': managerId,
      'manager_commission_type': ?managerCommissionType,
      'manager_commission_value': ?managerCommissionValue,
      if (criteria != null) 'criteria': [for (final c in criteria) c.toJson()],
    },
  );

  /// DELETE /staff-targets/{id} — needs `staff_targets.manage`; a verified
  /// target cannot be deleted.
  Future<void> deleteStaffTarget(String id) =>
      _api.delete<dynamic>('/staff-targets/$id');

  /// GET /staff-targets/summary — commission actually earned, per person,
  /// across verified targets only. Same scoping as the index.
  Future<List<TargetCommission>> targetCommissions({String? userId}) async {
    final body = await _api.get<dynamic>(
      '/staff-targets/summary',
      query: {'user_id': userId},
    );
    return Paginated.fromJson(body, TargetCommission.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // System verifications & records
  // ---------------------------------------------------------------------

  /// GET /my-verifications — the systems assigned to the signed-in user,
  /// with today's report attached when already submitted. Gated on
  /// `menu.my_verifications` (the drawer's permission); `/system-verifications`
  /// is the admin CRUD index, which 403s for ordinary staff and lists other
  /// people's systems for admins.
  Future<List<SystemVerification>> systemVerifications() async {
    final body = await _api.get<dynamic>('/my-verifications');
    return Paginated.fromJson(body, SystemVerification.fromJson).items;
  }

  /// POST /system-verifications/{id}/reports — submit today's check.
  /// Needs `system_verification_reports.submit`.
  Future<void> submitVerification(
    String verificationId, {
    required String status, // ok | issue
    String? notes,
  }) => _api.post<dynamic>(
    '/system-verifications/$verificationId/reports',
    body: {'status': status, 'notes': ?notes},
  );

  /// GET /system-verifications/{id}/reports — the check history.
  Future<List<SystemVerificationReport>> verificationReports(
    String verificationId,
  ) async {
    final body = await _api.get<dynamic>(
      '/system-verifications/$verificationId/reports',
    );
    return Paginated.fromJson(body, SystemVerificationReport.fromJson).items;
  }

  /// GET /system-records — paginated.
  Future<Paginated<SystemRecord>> systemRecords({
    String? systemId,
    String? systemPropertyId,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/system-records',
      query: {
        'system_id': systemId,
        'system_property_id': systemPropertyId,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, SystemRecord.fromJson);
  }

  /// GET /systems — needs `systems.read`. Feeds the record form's picker.
  Future<List<SystemOption>> systems() async {
    final body = await _api.get<dynamic>('/systems', query: {'per_page': 200});
    return Paginated.fromJson(body, SystemOption.fromJson).items;
  }

  /// GET /system-properties — needs `system_properties.read`.
  Future<List<SystemOption>> systemProperties() async {
    final body = await _api.get<dynamic>(
      '/system-properties',
      query: {'per_page': 200},
    );
    return Paginated.fromJson(body, SystemOption.fromJson).items;
  }

  /// POST /system-records — log a figure against a system property. Needs
  /// `system_records.create`.
  ///
  /// Multipart, and the receipt is **required** on create: the validator's
  /// rule is `required|file|max:10240|mimes:pdf,jpg,jpeg,png`. The record date
  /// cannot be in the future.
  Future<void> createSystemRecord({
    required String systemId,
    required String systemPropertyId,
    required DateTime recordDate,
    required double amount,
    required String receiptPath,
    String? bankAccountId,
    String? notes,
  }) => _sendSystemRecord(
    '/system-records',
    systemId: systemId,
    systemPropertyId: systemPropertyId,
    recordDate: recordDate,
    amount: amount,
    bankAccountId: bankAccountId,
    notes: notes,
    receiptPath: receiptPath,
  );

  /// PUT /system-records/{id} — needs `system_records.update`.
  ///
  /// Sent as POST with `_method=PUT`, exactly as the web does: PHP does not
  /// parse a multipart body on a real PUT, so the file would arrive empty.
  /// A null [receiptPath] keeps the receipt already on file.
  Future<void> updateSystemRecord(
    String id, {
    required String systemId,
    required String systemPropertyId,
    required DateTime recordDate,
    required double amount,
    String? bankAccountId,
    String? notes,
    String? receiptPath,
  }) => _sendSystemRecord(
    '/system-records/$id',
    systemId: systemId,
    systemPropertyId: systemPropertyId,
    recordDate: recordDate,
    amount: amount,
    bankAccountId: bankAccountId,
    notes: notes,
    receiptPath: receiptPath,
    methodOverride: 'PUT',
  );

  /// DELETE /system-records/{id} — needs `system_records.delete`. Soft delete,
  /// so the receipt file stays on disk.
  Future<void> deleteSystemRecord(String id) =>
      _api.delete<dynamic>('/system-records/$id');

  Future<void> _sendSystemRecord(
    String path, {
    required String systemId,
    required String systemPropertyId,
    required DateTime recordDate,
    required double amount,
    String? bankAccountId,
    String? notes,
    String? receiptPath,
    String? methodOverride,
  }) async {
    // Every value goes up as a string: multipart has no other type, and
    // routing the amount through `toString()` ourselves avoids Dio's
    // scientific notation on large values.
    final form = FormData.fromMap({
      '_method': ?methodOverride,
      'system_id': systemId,
      'system_property_id': systemPropertyId,
      'bank_account_id': ?bankAccountId,
      'record_date': _ymd(recordDate),
      'amount': amount.toString(),
      'notes': ?notes,
    });
    if (receiptPath != null && receiptPath.isNotEmpty) {
      form.files.add(
        MapEntry('receipt', await MultipartFile.fromFile(receiptPath)),
      );
    }

    try {
      await _api.raw.post<dynamic>(path, data: form);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// The `{data: ...}` wrapper these hand-built controllers use.
  static Map<String, dynamic> _map(dynamic body) =>
      body is Map ? Map<String, dynamic>.from(body) : const <String, dynamic>{};

  static Map<String, dynamic> _data(dynamic body) {
    final json = _map(body);
    return json.object('data') ?? json;
  }

  /// The `message` a waive/unwaive returns, for the snackbar.
  static String _message(dynamic body, String fallback) =>
      _map(body).str('message') ?? fallback;
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class StaffSelfPermissions {
  /// Guards the whole clerk half of attendance — the day board, the
  /// dashboard, the deductions ledger, and `POST /attendance/record`, which
  /// is the only route that writes a check-in or check-out.
  static const attendanceManage = 'attendance.manage';
  static const staffReportsSubmit = 'staff_reports.submit';
  static const staffReportsReview = 'staff_reports.review';
  static const staffTargetsSubmit = 'staff_targets.submit';
  static const staffTargetsManage = 'staff_targets.manage';
  static const staffTargetsVerify = 'staff_targets.verify';
  static const systemRecordsRead = 'system_records.read';
  static const systemRecordsCreate = 'system_records.create';
  static const systemRecordsUpdate = 'system_records.update';
  static const systemRecordsDelete = 'system_records.delete';
  static const systemVerificationsRead = 'system_verifications.read';
  static const verificationSubmit = 'system_verification_reports.submit';
}
