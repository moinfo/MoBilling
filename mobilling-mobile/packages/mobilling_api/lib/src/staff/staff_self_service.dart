import '../api_client.dart';
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
  }) =>
      _api.post<dynamic>('/staff-reports', body: {
        'report_type': reportType,
        'period_date': _ymd(periodDate),
        'achievements': achievements,
        'challenges': ?challenges,
        'plans': ?plans,
        'notes': ?notes,
      });

  /// POST /staff-reports/{id}/reply — the conversation thread on a report.
  Future<void> replyToStaffReport(String id, String message) =>
      _api.post<dynamic>('/staff-reports/$id/reply',
          body: {'message': message});

  /// POST /staff-reports/{id}/review — supervisor sign-off with a rating.
  Future<void> reviewStaffReport(
    String id, {
    int? rating,
    String? reviewNotes,
  }) =>
      _api.post<dynamic>('/staff-reports/$id/review', body: {
        'rating': ?rating,
        'review_notes': ?reviewNotes,
      });

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
  }) =>
      _api.post<dynamic>('/staff-targets/$targetId/self-report', body: {
        'criteria': [
          for (final entry in values.entries)
            {'id': entry.key, 'achieved_value': entry.value},
        ],
        'notes': ?notes,
      });

  // ---------------------------------------------------------------------
  // System verifications & records
  // ---------------------------------------------------------------------

  /// GET /system-verifications — systems to check, with today's report
  /// attached when already submitted.
  Future<List<SystemVerification>> systemVerifications() async {
    final body =
        await _api.get<dynamic>('/system-verifications');
    return Paginated.fromJson(body, SystemVerification.fromJson).items;
  }

  /// POST /system-verifications/{id}/reports — submit today's check.
  /// Needs `system_verification_reports.submit`.
  Future<void> submitVerification(
    String verificationId, {
    required String status, // ok | issue
    String? notes,
  }) =>
      _api.post<dynamic>('/system-verifications/$verificationId/reports',
          body: {'status': status, 'notes': ?notes});

  /// GET /system-verifications/{id}/reports — the check history.
  Future<List<SystemVerificationReport>> verificationReports(
      String verificationId) async {
    final body = await _api.get<dynamic>(
        '/system-verifications/$verificationId/reports');
    return Paginated.fromJson(body, SystemVerificationReport.fromJson).items;
  }

  /// GET /system-records — paginated.
  Future<Paginated<SystemRecord>> systemRecords({
    String? systemId,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/system-records',
      query: {'system_id': systemId, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, SystemRecord.fromJson);
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class StaffSelfPermissions {
  static const attendanceManage = 'attendance.manage';
  static const staffReportsReview = 'staff_reports.review';
  static const systemRecordsRead = 'system_records.read';
  static const systemVerificationsRead = 'system_verifications.read';
  static const verificationSubmit = 'system_verification_reports.submit';
}
