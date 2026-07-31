import '../api_client.dart';
import '../paginated.dart';
import 'crm_models.dart';

/// Field-work tooling: debt collection, follow-up calls, satisfaction calls,
/// appointments, walk-in customers served, and field-marketing visits.
///
/// Shape notes worth knowing before changing anything here:
///   * **Collection is dashboard-only.** `CollectionController` exposes exactly
///     one route; there is no list or log-outcome endpoint. Acting on a
///     collection row means creating a *follow-up*, which is why
///     [createFollowup] takes a document id.
///   * **Appointments are satisfaction calls.** They live on
///     `SatisfactionCallController` — an appointment is a satisfaction call
///     whose `appointment_requested` is true. There is no appointments table.
///   * Follow-up and satisfaction "log call" are the write actions that matter
///     on a phone; both are separately permissioned from reading.
class CrmService {
  const CrmService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Collection
  // ---------------------------------------------------------------------

  /// GET /collection/dashboard — outstanding money, ageing buckets, today's
  /// dues and payments, plus a date-keyed call plan.
  Future<CollectionDashboard> collectionDashboard() async {
    final body =
        await _api.get<Map<String, dynamic>>('/collection/dashboard');
    return CollectionDashboard.fromJson(body);
  }

  // ---------------------------------------------------------------------
  // Follow-ups
  // ---------------------------------------------------------------------

  /// GET /followups/dashboard — due today + overdue + counters.
  Future<FollowupDashboard> followupDashboard() async {
    final body = await _api.get<Map<String, dynamic>>('/followups/dashboard');
    return FollowupDashboard.fromJson(body);
  }

  /// GET /followups — the full list, optionally narrowed by status.
  Future<List<FollowupEntry>> followups({String? status}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/followups',
      query: {'status': status},
    );
    return Paginated.fromJson(body, FollowupEntry.fromJson).items;
  }

  /// POST /followups — schedule a follow-up against an unpaid invoice.
  Future<void> createFollowup({
    required String documentId,
    required DateTime callDate,
    String? notes,
  }) =>
      _api.post<dynamic>('/followups', body: {
        'document_id': documentId,
        'call_date': _ymd(callDate),
        'notes': ?notes,
      });

  /// POST /followups/{id}/log-call — record the outcome of a call.
  ///
  /// A promise-to-pay ([promiseDate] + [promiseAmount]) is what turns a
  /// follow-up into a tracked commitment; the server may escalate on repeated
  /// broken promises, which is reported back via
  /// [FollowupCallResult.escalated].
  Future<FollowupCallResult> logFollowupCall(
    String followupId, {
    required String outcome,
    String? notes,
    DateTime? promiseDate,
    double? promiseAmount,
    DateTime? nextFollowup,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/followups/$followupId/log-call',
      body: {
        'outcome': outcome,
        'notes': ?notes,
        'promise_date': promiseDate == null ? null : _ymd(promiseDate),
        'promise_amount': ?promiseAmount,
        'next_followup': nextFollowup == null ? null : _ymd(nextFollowup),
      },
    );
    return FollowupCallResult.fromJson(body);
  }

  /// PATCH /followups/{id}/cancel.
  Future<void> cancelFollowup(String followupId, {String? reason}) =>
      _api.patch<dynamic>('/followups/$followupId/cancel',
          body: {'reason': ?reason});

  /// GET /followups/client/{clientId} — every follow-up for one client.
  Future<List<FollowupEntry>> clientFollowupHistory(String clientId) async {
    final body =
        await _api.get<Map<String, dynamic>>('/followups/client/$clientId');
    return Paginated.fromJson(body, FollowupEntry.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Satisfaction calls
  // ---------------------------------------------------------------------

  /// GET /satisfaction-calls/dashboard — queue + team and personal stats.
  Future<SatisfactionDashboard> satisfactionDashboard() async {
    final body =
        await _api.get<Map<String, dynamic>>('/satisfaction-calls/dashboard');
    return SatisfactionDashboard.fromJson(body);
  }

  /// GET /satisfaction-calls — the call queue.
  Future<List<SatisfactionCall>> satisfactionCalls({String? status}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/satisfaction-calls',
      query: {'status': status},
    );
    return Paginated.fromJson(body, SatisfactionCall.fromJson).items;
  }

  /// POST /satisfaction-calls/{id}/log-call — record rating and feedback.
  ///
  /// [appointmentRequested] with [appointmentDate] is how a call turns into an
  /// appointment; there is no separate appointment-create endpoint.
  Future<void> logSatisfactionCall(
    String callId, {
    required String outcome,
    int? rating,
    String? feedback,
    String? internalNotes,
    bool? appointmentRequested,
    DateTime? appointmentDate,
    String? appointmentNotes,
  }) =>
      _api.post<dynamic>('/satisfaction-calls/$callId/log-call', body: {
        'outcome': outcome,
        'rating': ?rating,
        'feedback': ?feedback,
        'internal_notes': ?internalNotes,
        'appointment_requested': ?appointmentRequested,
        'appointment_date':
            appointmentDate == null ? null : _ymd(appointmentDate),
        'appointment_notes': ?appointmentNotes,
      });

  /// PATCH /satisfaction-calls/{id}/reschedule.
  Future<void> rescheduleSatisfactionCall(
    String callId, {
    required DateTime scheduledDate,
    String? reason,
  }) =>
      _api.patch<dynamic>('/satisfaction-calls/$callId/reschedule', body: {
        'scheduled_date': _ymd(scheduledDate),
        'reason': ?reason,
      });

  /// PATCH /satisfaction-calls/{id}/cancel.
  Future<void> cancelSatisfactionCall(String callId, {String? reason}) =>
      _api.patch<dynamic>('/satisfaction-calls/$callId/cancel',
          body: {'reason': ?reason});

  // ---------------------------------------------------------------------
  // Appointments (satisfaction calls with an appointment attached)
  // ---------------------------------------------------------------------

  /// GET /satisfaction-calls/appointments — paginated, with status counters.
  Future<AppointmentPage> appointments({
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/satisfaction-calls/appointments',
      query: {'status': status, 'page': page, 'per_page': perPage},
    );
    return AppointmentPage.fromJson(body);
  }

  /// PATCH /satisfaction-calls/{id}/appointment — confirm, complete, cancel or
  /// move an appointment.
  Future<void> updateAppointment(
    String callId, {
    String? appointmentStatus,
    DateTime? appointmentDate,
    String? appointmentNotes,
  }) =>
      _api.patch<dynamic>('/satisfaction-calls/$callId/appointment', body: {
        'appointment_status': ?appointmentStatus,
        'appointment_date':
            appointmentDate == null ? null : _ymd(appointmentDate),
        'appointment_notes': ?appointmentNotes,
      });

  // ---------------------------------------------------------------------
  // Served customers (walk-ins)
  // ---------------------------------------------------------------------

  /// GET /served/services — the service types a walk-in can be recorded under.
  Future<List<ServedService>> servedServices() async {
    final body = await _api.get<Map<String, dynamic>>('/served/services');
    return Paginated.fromJson(body, ServedService.fromJson).items;
  }

  /// GET /served/customers — paginated walk-in log.
  Future<Paginated<ServedCustomer>> servedCustomers({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/served/customers',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, ServedCustomer.fromJson);
  }

  /// POST /served/customers — log someone served at the counter.
  Future<void> recordServedCustomer({
    required String name,
    required List<String> serviceIds,
    String? phone,
    DateTime? servedDate,
    String? notes,
  }) =>
      _api.post<dynamic>('/served/customers', body: {
        'name': name,
        'served_service_ids': serviceIds,
        'phone': ?phone,
        'served_date': servedDate == null ? null : _ymd(servedDate),
        'notes': ?notes,
      });

  /// POST /served/customers/{id}/feedback — the satisfaction call-back on a
  /// walk-in.
  Future<void> recordServedFeedback(
    String customerId, {
    required String outcome,
    int? rating,
    String? feedback,
    String? challenges,
    String? internalNotes,
  }) =>
      _api.post<dynamic>('/served/customers/$customerId/feedback', body: {
        'outcome': outcome,
        'rating': ?rating,
        'feedback': ?feedback,
        'challenges': ?challenges,
        'internal_notes': ?internalNotes,
      });

  /// GET /served/weekly-summary — this week's achievement against target.
  Future<ServedWeeklySummary> servedWeeklySummary() async {
    final body =
        await _api.get<Map<String, dynamic>>('/served/weekly-summary');
    return ServedWeeklySummary.fromJson(body);
  }

  // ---------------------------------------------------------------------
  // Field marketing
  // ---------------------------------------------------------------------

  /// GET /field-sessions — a day's canvassing in an area.
  Future<Paginated<FieldSession>> fieldSessions({
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/field-sessions',
      query: {'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, FieldSession.fromJson);
  }

  /// GET /field-sessions/{id} — the session plus its visits.
  Future<FieldSessionDetail> fieldSession(String sessionId) async {
    final body =
        await _api.get<Map<String, dynamic>>('/field-sessions/$sessionId');
    return FieldSessionDetail.fromJson(body);
  }

  /// POST /field-sessions — start a session for an area and date.
  Future<FieldSession> createFieldSession({
    required String area,
    required DateTime visitDate,
    String? summary,
    String? challenges,
    String? recommendations,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/field-sessions',
      body: {
        'area': area,
        'visit_date': _ymd(visitDate),
        'summary': ?summary,
        'challenges': ?challenges,
        'recommendations': ?recommendations,
      },
    );
    final data = body['data'];
    return FieldSession.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : body);
  }

  /// POST /field-sessions/{id}/visits — log a business visited.
  Future<void> logFieldVisit(
    String sessionId, {
    required String businessName,
    required String status,
    List<String> services = const [],
    String? location,
    String? phone,
    String? feedback,
    DateTime? nextFollowupDate,
  }) =>
      _api.post<dynamic>('/field-sessions/$sessionId/visits', body: {
        'business_name': businessName,
        'status': status,
        if (services.isNotEmpty) 'services': services,
        'location': ?location,
        'phone': ?phone,
        'feedback': ?feedback,
        'next_followup_date':
            nextFollowupDate == null ? null : _ymd(nextFollowupDate),
      });

  /// GET /field-visits-report — every visit across sessions, for follow-up.
  Future<Paginated<FieldVisit>> allFieldVisits({
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/field-visits-report',
      query: {'status': status, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, FieldVisit.fromJson);
  }

  /// GET /field-targets — monthly conversion targets per officer.
  Future<List<FieldTarget>> fieldTargets({int? month, int? year}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/field-targets',
      query: {'month': month, 'year': year},
    );
    return Paginated.fromJson(body, FieldTarget.fromJson).items;
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class CrmPermissions {
  static const collection = 'menu.collection';
  static const followups = 'menu.followups';
  static const followupLog = 'field_visits.log';
  static const satisfactionCalls = 'menu.satisfaction_calls';
  static const satisfactionLog = 'satisfaction_calls.log';
  static const satisfactionReschedule = 'satisfaction_calls.reschedule';
  static const satisfactionCancel = 'satisfaction_calls.cancel';
  static const servedRead = 'served.read';
  static const servedCreate = 'served.create';
  static const fieldSessionsRead = 'field_sessions.read';
  static const fieldSessionsCreate = 'field_sessions.create';
  static const fieldVisitsCreate = 'field_visits.create';
  static const fieldTargetsRead = 'field_targets.read';
}
