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
    final body = await _api.get<Map<String, dynamic>>('/collection/dashboard');
    return CollectionDashboard.fromJson(_unwrap(body));
  }

  // ---------------------------------------------------------------------
  // Follow-ups
  // ---------------------------------------------------------------------

  /// GET /followups/dashboard — due today + overdue + counters.
  Future<FollowupDashboard> followupDashboard() async {
    final body = await _api.get<dynamic>('/followups/dashboard');
    return FollowupDashboard.fromJson(_unwrap(body));
  }

  /// GET /followups — optionally narrowed by status. Paginated server-side
  /// (default 20); the screen shows one generous page.
  Future<List<FollowupEntry>> followups({
    String? status,
    int perPage = 100,
  }) async {
    final body = await _api.get<dynamic>(
      '/followups',
      query: {'status': status, 'per_page': perPage},
    );
    return Paginated.fromJson(body, FollowupEntry.fromJson).items;
  }

  /// POST /followups — schedule a follow-up against an unpaid invoice.
  Future<void> createFollowup({
    required String documentId,
    required DateTime callDate,
    String? notes,
  }) => _api.post<dynamic>(
    '/followups',
    body: {
      'document_id': documentId,
      'call_date': _ymd(callDate),
      'notes': ?notes,
    },
  );

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
        // Required server-side — send an empty string rather than omit so
        // the validator's message is about content, not absence.
        'notes': notes ?? '',
        'promise_date': promiseDate == null ? null : _ymd(promiseDate),
        'promise_amount': ?promiseAmount,
        // `FollowupController::logCall` reads `next_followup_override`.
        'next_followup_override': nextFollowup == null
            ? null
            : _ymd(nextFollowup),
      },
    );
    return FollowupCallResult.fromJson(body);
  }

  /// PATCH /followups/{id}/cancel.
  Future<void> cancelFollowup(String followupId, {String? reason}) =>
      _api.patch<dynamic>(
        '/followups/$followupId/cancel',
        body: {'reason': ?reason},
      );

  /// GET /followups/client/{clientId} — every follow-up for one client.
  Future<List<FollowupEntry>> clientFollowupHistory(String clientId) async {
    final body = await _api.get<dynamic>('/followups/client/$clientId');
    return Paginated.fromJson(body, FollowupEntry.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Satisfaction calls
  // ---------------------------------------------------------------------

  /// GET /satisfaction-calls/dashboard — queue + team and personal stats.
  Future<SatisfactionDashboard> satisfactionDashboard() async {
    final body = await _api.get<dynamic>('/satisfaction-calls/dashboard');
    return SatisfactionDashboard.fromJson(_unwrap(body));
  }

  /// GET /satisfaction-calls — the call queue. Statuses are
  /// `scheduled | completed | missed | cancelled`. Paginated server-side;
  /// the screen shows one generous page.
  Future<List<SatisfactionCall>> satisfactionCalls({
    String? status,
    int perPage = 100,
  }) async {
    final body = await _api.get<dynamic>(
      '/satisfaction-calls',
      query: {'status': status, 'per_page': perPage},
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
  }) => _api.post<dynamic>(
    '/satisfaction-calls/$callId/log-call',
    body: {
      'outcome': outcome,
      'rating': ?rating,
      'feedback': ?feedback,
      'internal_notes': ?internalNotes,
      'appointment_requested': ?appointmentRequested,
      'appointment_date': appointmentDate == null
          ? null
          : _ymd(appointmentDate),
      'appointment_notes': ?appointmentNotes,
    },
  );

  /// PATCH /satisfaction-calls/{id}/reschedule.
  Future<void> rescheduleSatisfactionCall(
    String callId, {
    required DateTime scheduledDate,
    String? reason,
  }) => _api.patch<dynamic>(
    '/satisfaction-calls/$callId/reschedule',
    body: {'scheduled_date': _ymd(scheduledDate), 'reason': ?reason},
  );

  /// PATCH /satisfaction-calls/{id}/cancel.
  Future<void> cancelSatisfactionCall(String callId, {String? reason}) =>
      _api.patch<dynamic>(
        '/satisfaction-calls/$callId/cancel',
        body: {'reason': ?reason},
      );

  /// PATCH /satisfaction-calls/{id}/assign — hand the call to a colleague.
  /// The user must be active and in the same tenant. Returns the server's
  /// confirmation ("Call assigned to …").
  Future<String> assignSatisfactionCall(
    String callId, {
    required String userId,
  }) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/satisfaction-calls/$callId/assign',
      body: {'user_id': userId},
    );
    return body['message']?.toString() ?? 'Call assigned.';
  }

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
  }) => _api.patch<dynamic>(
    '/satisfaction-calls/$callId/appointment',
    body: {
      'appointment_status': ?appointmentStatus,
      'appointment_date': appointmentDate == null
          ? null
          : _ymd(appointmentDate),
      'appointment_notes': ?appointmentNotes,
    },
  );

  // ---------------------------------------------------------------------
  // Served customers (walk-ins)
  // ---------------------------------------------------------------------

  /// GET /served/services — the service types a walk-in can be recorded under.
  Future<List<ServedService>> servedServices() async {
    final body = await _api.get<dynamic>('/served/services');
    return Paginated.fromJson(body, ServedService.fromJson).items;
  }

  /// GET /served/customers — paginated walk-in log.
  Future<Paginated<ServedCustomer>> servedCustomers({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
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
  }) => _api.post<dynamic>(
    '/served/customers',
    body: {
      'name': name,
      // `ServedCustomersController::storeCustomer` validates `service_ids`
      // and requires `served_date` — default to today for a walk-in.
      if (serviceIds.isNotEmpty) 'service_ids': serviceIds,
      'phone': ?phone,
      'served_date': _ymd(servedDate ?? DateTime.now()),
      'notes': ?notes,
    },
  );

  /// POST /served/customers/{id}/feedback — the satisfaction call-back on a
  /// walk-in.
  Future<void> recordServedFeedback(
    String customerId, {
    required String outcome,
    int? rating,
    String? feedback,
    String? challenges,
    String? internalNotes,
  }) => _api.post<dynamic>(
    '/served/customers/$customerId/feedback',
    body: {
      'outcome': outcome,
      'rating': ?rating,
      'feedback': ?feedback,
      'challenges': ?challenges,
      'internal_notes': ?internalNotes,
    },
  );

  /// PUT /served/customers/{id} — correct a logged walk-in. Every field is
  /// `sometimes`; passing [serviceIds] re-syncs the whole pivot, so send the
  /// complete list rather than the additions.
  Future<ServedCustomer> updateServedCustomer(
    String customerId, {
    String? name,
    String? phone,
    DateTime? servedDate,
    String? notes,
    List<String>? serviceIds,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/served/customers/$customerId',
      body: {
        'name': ?name,
        'phone': ?phone,
        'served_date': servedDate == null ? null : _ymd(servedDate),
        'notes': ?notes,
        'service_ids': ?serviceIds,
      },
    );
    return ServedCustomer.fromJson(_unwrap(body));
  }

  /// DELETE /served/customers/{id} — removes the entry and its feedback.
  Future<void> deleteServedCustomer(String customerId) =>
      _api.delete<dynamic>('/served/customers/$customerId');

  /// DELETE /served/customers/{id}/feedback/{feedback} — drop one call-back.
  Future<void> deleteServedFeedback(String customerId, String feedbackId) =>
      _api.delete<dynamic>(
        '/served/customers/$customerId/feedback/$feedbackId',
      );

  /// GET /served/target — the counter's daily target, or null when the tenant
  /// has never set one.
  Future<ServedTarget?> servedTarget() async {
    final body = await _api.get<Map<String, dynamic>>('/served/target');
    final data = body['data'];
    if (data is! Map || data.isEmpty) return null;
    return ServedTarget.fromJson(Map<String, dynamic>.from(data));
  }

  /// POST /served/target — set or replace the daily target. Tenant-wide, not
  /// per officer: the controller upserts the single [ServedTarget] row.
  ///
  /// [activeDays] are ISO weekdays (1 = Monday) and at least one is required.
  Future<ServedTarget> setServedTarget({
    required int newCustomersTarget,
    required int calledCustomersTarget,
    required List<int> activeDays,
    required DateTime effectiveFrom,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/served/target',
      body: {
        'new_customers_target': newCustomersTarget,
        'called_customers_target': calledCustomersTarget,
        'active_days': activeDays,
        'effective_from': _ymd(effectiveFrom),
      },
    );
    return ServedTarget.fromJson(_unwrap(body));
  }

  /// GET /served/weekly-summary — this week's achievement against target.
  Future<ServedWeeklySummary> servedWeeklySummary() async {
    final body = await _api.get<Map<String, dynamic>>('/served/weekly-summary');
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
    final body = await _api.get<dynamic>(
      '/field-sessions',
      query: {'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, FieldSession.fromJson);
  }

  /// GET /field-sessions/{id} — the session plus its visits.
  Future<FieldSessionDetail> fieldSession(String sessionId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/field-sessions/$sessionId',
    );
    return FieldSessionDetail.fromJson(body);
  }

  /// POST /field-sessions — start a session for an area and date.
  /// [officerId] is required by the controller; the app passes the
  /// signed-in user.
  Future<FieldSession> createFieldSession({
    required String officerId,
    required String area,
    required DateTime visitDate,
    String? summary,
    String? challenges,
    String? recommendations,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/field-sessions',
      body: {
        'officer_id': officerId,
        'area': area,
        'visit_date': _ymd(visitDate),
        'summary': ?summary,
        'challenges': ?challenges,
        'recommendations': ?recommendations,
      },
    );
    final data = body['data'];
    return FieldSession.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// POST /field-sessions/{id}/visits — log a business visited. `location`
  /// and at least one service are required by the controller.
  Future<void> logFieldVisit(
    String sessionId, {
    required String businessName,
    required String status,
    required String location,
    required List<String> services,
    String? phone,
    String? feedback,
    DateTime? nextFollowupDate,
  }) => _api.post<dynamic>(
    '/field-sessions/$sessionId/visits',
    body: {
      'business_name': businessName,
      'status': status,
      'services': services,
      'location': location,
      'phone': ?phone,
      'feedback': ?feedback,
      'next_followup_date': nextFollowupDate == null
          ? null
          : _ymd(nextFollowupDate),
    },
  );

  /// GET /field-visits-report — every visit across sessions, for follow-up.
  Future<Paginated<FieldVisit>> allFieldVisits({
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/field-visits-report',
      query: {'status': status, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, FieldVisit.fromJson);
  }

  /// PUT /field-sessions/{id} — correct a session, or close it off by writing
  /// the summary, challenges and recommendations. Every field is `sometimes`,
  /// so pass only what changed.
  Future<FieldSession> updateFieldSession(
    String sessionId, {
    String? area,
    DateTime? visitDate,
    String? officerId,
    String? summary,
    String? challenges,
    String? recommendations,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/field-sessions/$sessionId',
      body: {
        'area': ?area,
        'visit_date': visitDate == null ? null : _ymd(visitDate),
        'officer_id': ?officerId,
        'summary': ?summary,
        'challenges': ?challenges,
        'recommendations': ?recommendations,
      },
    );
    return FieldSession.fromJson(_unwrap(body));
  }

  /// DELETE /field-sessions/{id} — takes the session's visits with it.
  Future<void> deleteFieldSession(String sessionId) =>
      _api.delete<dynamic>('/field-sessions/$sessionId');

  /// PUT /field-sessions/{s}/visits/{v} — correct a logged visit.
  ///
  /// `services` is validated `sometimes|array|min:1`, so an empty list would be
  /// rejected; pass null to leave it alone.
  Future<FieldVisit> updateFieldVisit(
    String sessionId,
    String visitId, {
    String? businessName,
    String? location,
    String? phone,
    List<String>? services,
    String? feedback,
    String? status,
    String? clientId,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/field-sessions/$sessionId/visits/$visitId',
      body: {
        'business_name': ?businessName,
        'location': ?location,
        'phone': ?phone,
        if (services != null && services.isNotEmpty) 'services': services,
        'feedback': ?feedback,
        'status': ?status,
        'client_id': ?clientId,
      },
    );
    return FieldVisit.fromJson(_unwrap(body));
  }

  /// DELETE /field-sessions/{s}/visits/{v}.
  Future<void> deleteFieldVisit(String sessionId, String visitId) =>
      _api.delete<dynamic>('/field-sessions/$sessionId/visits/$visitId');

  /// POST /field-sessions/{s}/visits/{v}/convert — turn a prospect into a
  /// billing client. This is the point of the whole module.
  ///
  /// Either link an existing client with [clientId], or create one — in which
  /// case [clientName] is required and the visit's own phone is used when
  /// [clientPhone] is omitted. Either way the visit comes back `converted`
  /// with the client attached.
  Future<FieldVisit> convertFieldVisit(
    String sessionId,
    String visitId, {
    String? clientId,
    String? clientName,
    String? clientEmail,
    String? clientPhone,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/field-sessions/$sessionId/visits/$visitId/convert',
      body: {
        'client_id': ?clientId,
        'client_name': ?clientName,
        'client_email': ?clientEmail,
        'client_phone': ?clientPhone,
      },
    );
    return FieldVisit.fromJson(_unwrap(body));
  }

  /// GET /field-visits/{visit}/followups — newest call first.
  Future<List<FieldFollowup>> fieldVisitFollowups(String visitId) async {
    final body = await _api.get<dynamic>('/field-visits/$visitId/followups');
    return Paginated.fromJson(body, FieldFollowup.fromJson).items;
  }

  /// POST /field-visits/{visit}/followups — record a call on a prospect.
  ///
  /// The controller also writes [nextFollowupDate] onto the visit and maps an
  /// `interested` / `not_interested` / `converted` outcome onto the visit's
  /// status, so the visit is stale after this returns.
  Future<FieldFollowup> logFieldVisitFollowup(
    String visitId, {
    required DateTime callDate,
    required String outcome,
    String? notes,
    DateTime? nextFollowupDate,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/field-visits/$visitId/followups',
      body: {
        'call_date': _ymd(callDate),
        'outcome': outcome,
        'notes': ?notes,
        'next_followup_date': nextFollowupDate == null
            ? null
            : _ymd(nextFollowupDate),
      },
    );
    return FieldFollowup.fromJson(_unwrap(body));
  }

  /// DELETE /field-visits/{visit}/followups/{followup}.
  Future<void> deleteFieldVisitFollowup(String visitId, String followupId) =>
      _api.delete<dynamic>('/field-visits/$visitId/followups/$followupId');

  /// GET /field-targets — monthly conversion targets per officer.
  Future<List<FieldTarget>> fieldTargets({int? month, int? year}) async {
    final body = await _api.get<dynamic>(
      '/field-targets',
      query: {'month': month, 'year': year},
    );
    return Paginated.fromJson(body, FieldTarget.fromJson).items;
  }

  /// POST /field-targets — set one officer's target for a month. Upserts on
  /// (officer, month, year), so this is also how a target is corrected.
  Future<FieldTarget> setFieldTarget({
    required String officerId,
    required int month,
    required int year,
    required int targetClients,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/field-targets',
      body: {
        'officer_id': officerId,
        'month': month,
        'year': year,
        'target_clients': targetClients,
      },
    );
    return FieldTarget.fromJson(_unwrap(body));
  }

  /// GET /field-stats — a month's visits by status and by officer.
  Future<FieldStats> fieldStats({int? month, int? year}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/field-stats',
      query: {'month': month, 'year': year},
    );
    return FieldStats.fromJson(_unwrap(body));
  }

  // ---------------------------------------------------------------------
  // Marketing services — MarketingServiceController
  //
  // The tenant-customisable reference list field visits and WhatsApp
  // contacts tag themselves with. Live data, not the hardcoded
  // `FieldServices.values` the "services discussed" picker used to fall
  // back to unconditionally.
  // ---------------------------------------------------------------------

  /// GET /marketing-services. Needs `marketing_services.read`.
  Future<List<MarketingServiceItem>> marketingServices() async {
    final body = await _api.get<dynamic>('/marketing-services');
    return Paginated.fromJson(body, MarketingServiceItem.fromJson).items;
  }

  /// POST /marketing-services. Needs `marketing_services.create`. 422s with
  /// a "Service already exists." message on a duplicate name.
  Future<MarketingServiceItem> createMarketingService(String name) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/marketing-services',
      body: {'name': name},
    );
    return MarketingServiceItem.fromJson(body);
  }

  /// PUT /marketing-services/{id}. Needs `marketing_services.update`.
  Future<MarketingServiceItem> updateMarketingService(
    String id,
    String name,
  ) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/marketing-services/$id',
      body: {'name': name},
    );
    return MarketingServiceItem.fromJson(body);
  }

  /// DELETE /marketing-services/{id}. Needs `marketing_services.delete`.
  Future<void> deleteMarketingService(String id) =>
      _api.delete<dynamic>('/marketing-services/$id');

  /// POST /marketing-services/reorder — [ids] in the new display order.
  /// Needs `marketing_services.update` server-side, same as the PUT.
  Future<void> reorderMarketingServices(List<String> ids) =>
      _api.post<dynamic>('/marketing-services/reorder', body: {'ids': ids});

  /// The three CRM dashboards wrap their payload in `{data: {...}}`; the
  /// list endpoints in this service do not. Parsing the outer map produced
  /// an all-zero screen with no error.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
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
  static const satisfactionAssign = 'satisfaction_calls.assign';
  static const servedRead = 'served.read';
  static const servedCreate = 'served.create';
  static const servedUpdate = 'served.update';
  static const servedDelete = 'served.delete';
  static const servedSettings = 'served.settings';

  /// Only managers may back-date a walk-in; the web form falls back to a
  /// read-only date without it.
  static const servedChangeDate = 'served.change_date';
  static const fieldSessionsRead = 'field_sessions.read';
  static const fieldSessionsCreate = 'field_sessions.create';
  static const fieldSessionsUpdate = 'field_sessions.update';
  static const fieldSessionsDelete = 'field_sessions.delete';
  static const fieldVisitsCreate = 'field_visits.create';
  static const fieldVisitsUpdate = 'field_visits.update';
  static const fieldVisitsDelete = 'field_visits.delete';
  static const fieldVisitsConvert = 'field_visits.convert';
  static const fieldTargetsRead = 'field_targets.read';
  static const fieldTargetsUpdate = 'field_targets.update';

  /// Choosing a colleague means listing `/users`, which is gated separately
  /// from the action itself — assign and set-target need both.
  static const settingsUsers = 'settings.users';

  // ── Marketing services (the "services discussed" reference list) ──────
  static const marketingServicesRead = 'marketing_services.read';
  static const marketingServicesCreate = 'marketing_services.create';
  static const marketingServicesUpdate = 'marketing_services.update';
  static const marketingServicesDelete = 'marketing_services.delete';
}
