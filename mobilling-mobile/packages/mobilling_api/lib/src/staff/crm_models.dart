/// Models for the staff CRM / field-work endpoints: collection, follow-ups,
/// satisfaction calls, appointments, served customers and field marketing.
///
/// These controllers hand-build their responses inside `->map()` closures, so
/// the same logical field arrives as a float on one route and a `decimal:2`
/// string on another (`Followup::promise_amount` is cast, the collection
/// dashboard casts to `(float)`). Everything therefore goes through the
/// tolerant readers in `json.dart` rather than direct casts.
library;

import '../json.dart';
import '../paginated.dart';

// ─────────────────────────────────────────────────────────────
// Collection — CollectionController::dashboard
// ─────────────────────────────────────────────────────────────

/// One unpaid invoice on the collection worklist.
///
/// `daysOverdue` is present on the overdue list, `daysUntilDue` on the
/// upcoming list, neither on today's — the controller emits a different shape
/// per bucket.
class CollectionInvoice {
  const CollectionInvoice({
    required this.id,
    required this.documentNumber,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
    this.clientName,
    this.clientId,
    this.dueDate,
    this.daysOverdue,
    this.daysUntilDue,
  });

  final String id;
  final String documentNumber;
  final double total;
  final double paidAmount;
  final double balanceDue;
  final String status;
  final String? clientName;
  final String? clientId;
  final DateTime? dueDate;
  final int? daysOverdue;
  final int? daysUntilDue;

  factory CollectionInvoice.fromJson(Map<String, dynamic> json) =>
      CollectionInvoice(
        id: json.id(),
        documentNumber: json.strOr('document_number', '—'),
        total: json.money('total'),
        paidAmount: json.money('paid_amount'),
        balanceDue: json.money('balance_due'),
        status: json.strOr('status', 'sent'),
        clientName: json.str('client_name'),
        clientId: json.str('client_id'),
        dueDate: json.date('due_date'),
        daysOverdue: json['days_overdue'] == null
            ? null
            : json.count('days_overdue'),
        daysUntilDue: json['days_until_due'] == null
            ? null
            : json.count('days_until_due'),
      );
}

/// A payment taken today, as shown on the collection dashboard.
class CollectionPayment {
  const CollectionPayment({
    required this.id,
    required this.amount,
    this.paymentMethod,
    this.reference,
    this.documentNumber,
    this.clientName,
  });

  final String id;
  final double amount;
  final String? paymentMethod;
  final String? reference;
  final String? documentNumber;
  final String? clientName;

  factory CollectionPayment.fromJson(Map<String, dynamic> json) =>
      CollectionPayment(
        id: json.id(),
        amount: json.money('amount'),
        paymentMethod: json.str('payment_method'),
        reference: json.str('reference'),
        documentNumber: json.str('document_number'),
        clientName: json.str('client_name'),
      );
}

/// Headline figures for the month's collection effort.
class CollectionSummary {
  const CollectionSummary({
    required this.totalOutstanding,
    required this.totalInvoiced,
    required this.totalPartialPaid,
    required this.unpaidCount,
    required this.todayDue,
    required this.todayDuePaid,
    required this.todayCollected,
    required this.todayBalance,
    required this.overdueTotal,
    required this.overduePaid,
    required this.overdueBalance,
    required this.monthTarget,
    required this.monthCollected,
    required this.monthBalance,
  });

  final double totalOutstanding;
  final double totalInvoiced;
  final double totalPartialPaid;
  final int unpaidCount;
  final double todayDue;
  final double todayDuePaid;
  final double todayCollected;
  final double todayBalance;
  final double overdueTotal;
  final double overduePaid;
  final double overdueBalance;
  final double monthTarget;
  final double monthCollected;
  final double monthBalance;

  /// Share of the month's target already banked, clamped to 0..1 so a target
  /// of zero (nothing due) cannot produce a NaN progress bar.
  double get monthProgress =>
      monthTarget <= 0 ? 0 : (monthCollected / monthTarget).clamp(0, 1);

  factory CollectionSummary.fromJson(Map<String, dynamic> json) =>
      CollectionSummary(
        totalOutstanding: json.money('total_outstanding'),
        totalInvoiced: json.money('total_invoiced'),
        totalPartialPaid: json.money('total_partial_paid'),
        unpaidCount: json.count('unpaid_count'),
        todayDue: json.money('today_due'),
        todayDuePaid: json.money('today_due_paid'),
        todayCollected: json.money('today_collected'),
        todayBalance: json.money('today_balance'),
        overdueTotal: json.money('overdue_total'),
        overduePaid: json.money('overdue_paid'),
        overdueBalance: json.money('overdue_balance'),
        monthTarget: json.money('month_target'),
        monthCollected: json.money('month_collected'),
        monthBalance: json.money('month_balance'),
      );
}

/// Receivables split by how late they are.
class CollectionAging {
  const CollectionAging({
    required this.current,
    required this.days1To30,
    required this.days31To60,
    required this.days61To90,
    required this.over90,
  });

  final double current;
  final double days1To30;
  final double days31To60;
  final double days61To90;
  final double over90;

  /// Buckets in reading order, labelled for display.
  List<(String, double)> get buckets => [
    ('Not yet due', current),
    ('1–30 days', days1To30),
    ('31–60 days', days31To60),
    ('61–90 days', days61To90),
    ('90+ days', over90),
  ];

  factory CollectionAging.fromJson(Map<String, dynamic> json) =>
      CollectionAging(
        current: json.money('current'),
        days1To30: json.money('1_30'),
        days31To60: json.money('31_60'),
        days61To90: json.money('61_90'),
        over90: json.money('over_90'),
      );
}

/// One scheduled call in the month's call plan.
class CallPlanEntry {
  const CallPlanEntry({
    required this.date,
    required this.documentId,
    required this.documentNumber,
    required this.clientName,
    required this.balance,
    required this.type,
    required this.label,
    required this.hasFollowup,
    this.clientPhone,
    this.dueDate,
  });

  /// The `Y-m-d` key this entry was filed under in the calendar.
  final String date;
  final String documentId;
  final String documentNumber;
  final String clientName;
  final double balance;

  /// `reminder`, `due_date`, `overdue_urgent`, `overdue_followup`, `followup`.
  final String type;
  final String label;
  final bool hasFollowup;
  final String? clientPhone;
  final DateTime? dueDate;

  bool get isUrgent => type == 'overdue_urgent' || type == 'overdue_followup';

  factory CallPlanEntry.fromJson(String date, Map<String, dynamic> json) =>
      CallPlanEntry(
        date: date,
        documentId: json.id('document_id'),
        documentNumber: json.strOr('document_number', '—'),
        clientName: json.strOr('client_name', 'Unknown'),
        balance: json.money('balance'),
        type: json.strOr('type', 'followup'),
        label: json.strOr('label', 'Call'),
        hasFollowup: json.flag('has_followup'),
        clientPhone: json.str('client_phone'),
        dueDate: json.date('due_date'),
      );
}

/// Everything `GET /collection/dashboard` returns.
class CollectionDashboard {
  const CollectionDashboard({
    required this.summary,
    required this.aging,
    required this.todayDue,
    required this.todayPayments,
    required this.overdue,
    required this.upcoming,
    required this.callPlan,
    required this.phoneByDocument,
  });

  final CollectionSummary summary;
  final CollectionAging aging;
  final List<CollectionInvoice> todayDue;
  final List<CollectionPayment> todayPayments;
  final List<CollectionInvoice> overdue;
  final List<CollectionInvoice> upcoming;

  /// Calendar of scheduled calls, keyed by `Y-m-d` in ascending date order.
  final Map<String, List<CallPlanEntry>> callPlan;

  /// The invoice lists carry no phone number, but the call plan does. Joining
  /// them here is what makes one-tap calling possible from the worklist.
  final Map<String, String> phoneByDocument;

  /// Calls planned for [day] (`Y-m-d`).
  List<CallPlanEntry> callsOn(String day) => callPlan[day] ?? const [];

  factory CollectionDashboard.fromJson(Map<String, dynamic> json) {
    final plan = <String, List<CallPlanEntry>>{};
    final phones = <String, String>{};

    final rawPlan = json['call_plan'];
    if (rawPlan is Map) {
      // PHP's ksort already ordered the keys; an empty calendar arrives as `[]`
      // from json_encode, which is why this is guarded rather than cast.
      for (final key in rawPlan.keys) {
        final day = key.toString();
        final entries = rawPlan[key];
        if (entries is! List) continue;
        final parsed = entries
            .whereType<Map>()
            .map(
              (e) => CallPlanEntry.fromJson(day, Map<String, dynamic>.from(e)),
            )
            .toList();
        if (parsed.isEmpty) continue;
        plan[day] = parsed;
        for (final entry in parsed) {
          final phone = entry.clientPhone;
          if (phone != null) phones[entry.documentId] = phone;
        }
      }
    }

    return CollectionDashboard(
      summary: CollectionSummary.fromJson(
        json.object('summary') ?? const <String, dynamic>{},
      ),
      aging: CollectionAging.fromJson(
        json.object('aging') ?? const <String, dynamic>{},
      ),
      todayDue: json.list('today_due', CollectionInvoice.fromJson),
      todayPayments: json.list('today_payments', CollectionPayment.fromJson),
      overdue: json.list('overdue', CollectionInvoice.fromJson),
      upcoming: json.list('upcoming', CollectionInvoice.fromJson),
      callPlan: plan,
      phoneByDocument: phones,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Follow-ups — FollowupController
// ─────────────────────────────────────────────────────────────

/// A collection follow-up: one scheduled (or logged) call about one invoice.
class FollowupEntry {
  const FollowupEntry({
    required this.id,
    required this.status,
    required this.invoiceTotal,
    required this.invoiceBalance,
    this.documentId,
    this.documentNumber,
    this.clientId,
    this.clientName,
    this.clientPhone,
    this.assignedTo,
    this.userId,
    this.callDate,
    this.outcome,
    this.notes,
    this.promiseDate,
    this.promiseAmount,
    this.nextFollowup,
    this.callCount,
    this.createdAt,
  });

  final String id;

  /// `pending`, `open`, `fulfilled`, `broken`, `escalated`, `cancelled`.
  final String status;
  final double invoiceTotal;
  final double invoiceBalance;
  final String? documentId;
  final String? documentNumber;
  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final String? assignedTo;
  final String? userId;
  final DateTime? callDate;

  /// `promised`, `declined`, `no_answer`, `disputed`, `partial_payment`.
  final String? outcome;
  final String? notes;
  final DateTime? promiseDate;
  final double? promiseAmount;
  final DateTime? nextFollowup;

  /// Calls already logged against this invoice; the backend escalates at 3.
  final int? callCount;
  final DateTime? createdAt;

  /// A call has not been made yet, so "Log call" is the action.
  bool get isOpenWork => status == 'pending' || status == 'broken';

  factory FollowupEntry.fromJson(Map<String, dynamic> json) => FollowupEntry(
    id: json.id(),
    status: json.strOr('status', 'pending'),
    invoiceTotal: json.money('invoice_total'),
    invoiceBalance: json.money('invoice_balance'),
    documentId: json.str('document_id'),
    documentNumber: json.str('document_number'),
    clientId: json.str('client_id'),
    clientName: json.str('client_name'),
    clientPhone: json.str('client_phone'),
    assignedTo: json.str('assigned_to'),
    userId: json.str('user_id'),
    callDate: json.date('call_date'),
    outcome: json.str('outcome'),
    notes: json.str('notes'),
    promiseDate: json.date('promise_date'),
    promiseAmount: json['promise_amount'] == null
        ? null
        : json.money('promise_amount'),
    nextFollowup: json.date('next_followup'),
    callCount: json['call_count'] == null ? null : json.count('call_count'),
    createdAt: json.date('created_at'),
  );
}

/// Counts behind the follow-up dashboard.
class FollowupStats {
  const FollowupStats({
    required this.dueToday,
    required this.overdue,
    required this.totalActive,
  });

  final int dueToday;
  final int overdue;
  final int totalActive;

  factory FollowupStats.fromJson(Map<String, dynamic> json) => FollowupStats(
    dueToday: json.count('due_today'),
    overdue: json.count('overdue'),
    totalActive: json.count('total_active'),
  );
}

/// `GET /followups/dashboard` — today's calls plus the ones already missed.
class FollowupDashboard {
  const FollowupDashboard({
    required this.dueToday,
    required this.overdue,
    required this.stats,
  });

  final List<FollowupEntry> dueToday;
  final List<FollowupEntry> overdue;
  final FollowupStats stats;

  factory FollowupDashboard.fromJson(Map<String, dynamic> json) =>
      FollowupDashboard(
        dueToday: json.list('due_today', FollowupEntry.fromJson),
        overdue: json.list('overdue_followups', FollowupEntry.fromJson),
        stats: FollowupStats.fromJson(
          json.object('stats') ?? const <String, dynamic>{},
        ),
      );
}

/// What logging a call produced. The backend either auto-schedules the next
/// call or escalates the invoice at three calls, and says which in [message].
class FollowupCallResult {
  const FollowupCallResult({required this.message, required this.escalated});

  final String message;
  final bool escalated;

  factory FollowupCallResult.fromJson(Map<String, dynamic> json) =>
      FollowupCallResult(
        message: json.strOr('message', 'Call logged.'),
        escalated: json.flag('escalated'),
      );
}

/// The outcomes `POST /followups/{id}/log-call` accepts, in the order a caller
/// is most likely to need them.
abstract final class FollowupOutcomes {
  static const values = <(String, String)>[
    ('promised', 'Promised to pay'),
    ('partial_payment', 'Partial payment'),
    ('no_answer', 'No answer'),
    ('disputed', 'Disputed'),
    ('declined', 'Declined'),
  ];

  /// `promise_date` is required for a promise; an amount for either of these.
  static bool needsPromiseDate(String outcome) => outcome == 'promised';

  static bool needsAmount(String outcome) =>
      outcome == 'promised' || outcome == 'partial_payment';

  static String label(String? outcome) => values
      .firstWhere((e) => e.$1 == outcome, orElse: () => ('', outcome ?? '—'))
      .$2;
}

// ─────────────────────────────────────────────────────────────
// Satisfaction calls — SatisfactionCallController
// ─────────────────────────────────────────────────────────────

/// A monthly satisfaction call for one client.
class SatisfactionCall {
  const SatisfactionCall({
    required this.id,
    required this.status,
    this.clientId,
    this.clientName,
    this.clientPhone,
    this.userId,
    this.assignedTo,
    this.scheduledDate,
    this.calledAt,
    this.outcome,
    this.rating,
    this.feedback,
    this.internalNotes,
    this.monthKey,
    this.isFollowUp = false,
    this.appointmentRequested = false,
    this.appointmentDate,
    this.appointmentNotes,
    this.appointmentStatus,
    this.createdAt,
  });

  final String id;

  /// `scheduled`, `completed`, `missed`, `cancelled`.
  final String status;
  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final String? userId;
  final String? assignedTo;
  final DateTime? scheduledDate;
  final DateTime? calledAt;

  /// `satisfied`, `needs_improvement`, `complaint`, `suggestion`,
  /// `no_answer`, `unreachable`.
  final String? outcome;
  final int? rating;
  final String? feedback;
  final String? internalNotes;
  final String? monthKey;

  /// This call was auto-created because an earlier one went unanswered.
  final bool isFollowUp;
  final bool appointmentRequested;
  final DateTime? appointmentDate;
  final String? appointmentNotes;
  final String? appointmentStatus;
  final DateTime? createdAt;

  bool get isCompleted => status == 'completed';

  factory SatisfactionCall.fromJson(Map<String, dynamic> json) =>
      SatisfactionCall(
        id: json.id(),
        status: json.strOr('status', 'scheduled'),
        clientId: json.str('client_id'),
        clientName: json.str('client_name'),
        clientPhone: json.str('client_phone'),
        userId: json.str('user_id'),
        assignedTo: json.str('assigned_to'),
        scheduledDate: json.date('scheduled_date'),
        calledAt: json.date('called_at'),
        outcome: json.str('outcome'),
        rating: json['rating'] == null ? null : json.count('rating'),
        feedback: json.str('feedback'),
        internalNotes: json.str('internal_notes'),
        monthKey: json.str('month_key'),
        isFollowUp: json.flag('is_follow_up'),
        appointmentRequested: json.flag('appointment_requested'),
        appointmentDate: json.date('appointment_date'),
        appointmentNotes: json.str('appointment_notes'),
        appointmentStatus: json.str('appointment_status'),
        createdAt: json.date('created_at'),
      );
}

/// Tenant-wide satisfaction figures for the current month.
class SatisfactionStats {
  const SatisfactionStats({
    required this.dueToday,
    required this.overdue,
    required this.completedThisMonth,
    required this.totalThisMonth,
    this.avgRating,
  });

  final int dueToday;
  final int overdue;
  final int completedThisMonth;
  final int totalThisMonth;
  final double? avgRating;

  factory SatisfactionStats.fromJson(Map<String, dynamic> json) =>
      SatisfactionStats(
        dueToday: json.count('due_today'),
        overdue: json.count('overdue'),
        completedThisMonth: json.count('completed_this_month'),
        totalThisMonth: json.count('total_this_month'),
        avgRating: json['avg_rating'] == null ? null : json.money('avg_rating'),
      );
}

/// The signed-in caller's own numbers — the ones they are measured on.
class SatisfactionMyStats {
  const SatisfactionMyStats({
    required this.todayCompleted,
    required this.todayTotal,
    required this.monthCompleted,
    required this.monthTotal,
    required this.overdue,
    this.avgRating,
  });

  final int todayCompleted;
  final int todayTotal;
  final int monthCompleted;
  final int monthTotal;
  final int overdue;
  final double? avgRating;

  factory SatisfactionMyStats.fromJson(Map<String, dynamic> json) =>
      SatisfactionMyStats(
        todayCompleted: json.count('today_completed'),
        todayTotal: json.count('today_total'),
        monthCompleted: json.count('month_completed'),
        monthTotal: json.count('month_total'),
        overdue: json.count('overdue'),
        avgRating: json['avg_rating'] == null ? null : json.money('avg_rating'),
      );
}

/// `GET /satisfaction-calls/dashboard`.
class SatisfactionDashboard {
  const SatisfactionDashboard({
    required this.dueToday,
    required this.overdue,
    required this.stats,
    required this.myStats,
  });

  final List<SatisfactionCall> dueToday;
  final List<SatisfactionCall> overdue;
  final SatisfactionStats stats;
  final SatisfactionMyStats myStats;

  factory SatisfactionDashboard.fromJson(Map<String, dynamic> json) =>
      SatisfactionDashboard(
        dueToday: json.list('due_today', SatisfactionCall.fromJson),
        overdue: json.list('overdue', SatisfactionCall.fromJson),
        stats: SatisfactionStats.fromJson(
          json.object('stats') ?? const <String, dynamic>{},
        ),
        myStats: SatisfactionMyStats.fromJson(
          json.object('my_stats') ?? const <String, dynamic>{},
        ),
      );
}

/// Outcomes `POST /satisfaction-calls/{id}/log-call` accepts.
abstract final class SatisfactionOutcomes {
  static const values = <(String, String)>[
    ('satisfied', 'Satisfied'),
    ('needs_improvement', 'Needs improvement'),
    ('complaint', 'Complaint'),
    ('suggestion', 'Suggestion'),
    ('no_answer', 'No answer'),
    ('unreachable', 'Unreachable'),
  ];

  /// No-answer outcomes auto-spawn a follow-up server-side, and a rating from
  /// a call that never happened would be noise — so the form hides it.
  static bool reached(String outcome) =>
      outcome != 'no_answer' && outcome != 'unreachable';

  static String label(String? outcome) => values
      .firstWhere((e) => e.$1 == outcome, orElse: () => ('', outcome ?? '—'))
      .$2;
}

// ─────────────────────────────────────────────────────────────
// Appointments — SatisfactionCallController::appointments
// ─────────────────────────────────────────────────────────────

/// A physical visit a client asked for during a satisfaction call.
class Appointment {
  const Appointment({
    required this.id,
    this.clientId,
    this.clientName,
    this.clientPhone,
    this.clientAddress,
    this.assignedTo,
    this.userId,
    this.appointmentDate,
    this.appointmentNotes,
    this.appointmentStatus,
    this.outcome,
    this.rating,
    this.feedback,
    this.scheduledDate,
    this.calledAt,
  });

  final String id;
  final String? clientId;
  final String? clientName;
  final String? clientPhone;
  final String? clientAddress;
  final String? assignedTo;
  final String? userId;
  final DateTime? appointmentDate;
  final String? appointmentNotes;

  /// `pending`, `confirmed`, `completed`, `cancelled`.
  final String? appointmentStatus;
  final String? outcome;
  final int? rating;
  final String? feedback;
  final DateTime? scheduledDate;
  final DateTime? calledAt;

  bool get isOpen =>
      appointmentStatus == 'pending' || appointmentStatus == 'confirmed';

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
    id: json.id(),
    clientId: json.str('client_id'),
    clientName: json.str('client_name'),
    clientPhone: json.str('client_phone'),
    clientAddress: json.str('client_address'),
    assignedTo: json.str('assigned_to'),
    userId: json.str('user_id'),
    appointmentDate: json.date('appointment_date'),
    appointmentNotes: json.str('appointment_notes'),
    appointmentStatus: json.str('appointment_status'),
    outcome: json.str('outcome'),
    rating: json['rating'] == null ? null : json.count('rating'),
    feedback: json.str('feedback'),
    scheduledDate: json.date('scheduled_date'),
    calledAt: json.date('called_at'),
  );
}

/// Visit-schedule counters returned alongside the appointment page.
class AppointmentStats {
  const AppointmentStats({
    required this.today,
    required this.upcoming,
    required this.overdue,
    required this.pending,
    required this.confirmed,
    required this.completed,
  });

  final int today;
  final int upcoming;
  final int overdue;
  final int pending;
  final int confirmed;
  final int completed;

  factory AppointmentStats.fromJson(Map<String, dynamic> json) =>
      AppointmentStats(
        today: json.count('today'),
        upcoming: json.count('upcoming'),
        overdue: json.count('overdue'),
        pending: json.count('pending'),
        confirmed: json.count('confirmed'),
        completed: json.count('completed'),
      );
}

/// One page of appointments plus the schedule-wide counters.
///
/// This endpoint hand-rolls its envelope — page metadata sits under `meta`,
/// not at the top level — so [Paginated.fromJson] would read it as a single
/// complete page. It is rebuilt here instead.
class AppointmentPage {
  const AppointmentPage({required this.page, required this.stats});

  final Paginated<Appointment> page;
  final AppointmentStats stats;

  factory AppointmentPage.fromJson(Map<String, dynamic> json) {
    final meta = json.object('meta') ?? const <String, dynamic>{};
    final items = json.list('data', Appointment.fromJson);
    final current = meta.count('current_page', fallback: 1);

    return AppointmentPage(
      page: Paginated(
        items: items,
        currentPage: current,
        lastPage: meta.count('last_page', fallback: current),
        total: meta.count('total', fallback: items.length),
      ),
      stats: AppointmentStats.fromJson(
        json.object('stats') ?? const <String, dynamic>{},
      ),
    );
  }
}

/// Statuses `PATCH /satisfaction-calls/{id}/appointment` accepts.
abstract final class AppointmentStatuses {
  static const values = <(String, String)>[
    ('pending', 'Pending'),
    ('confirmed', 'Confirmed'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];
}

// ─────────────────────────────────────────────────────────────
// Served customers — ServedCustomersController
// ─────────────────────────────────────────────────────────────

/// A service a walk-in customer can be served with.
class ServedService {
  const ServedService({
    required this.id,
    required this.name,
    required this.isActive,
    this.description,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final bool isActive;
  final String? description;
  final int sortOrder;

  factory ServedService.fromJson(Map<String, dynamic> json) => ServedService(
    id: json.id(),
    name: json.strOr('name', '—'),
    // The pivot rows on a customer only carry id + name; treat those as
    // active so a served customer's chips never render as disabled.
    isActive: json['is_active'] == null ? true : json.flag('is_active'),
    description: json.str('description'),
    sortOrder: json.count('sort_order'),
  );
}

/// Feedback captured on a call-back to a served customer.
class ServedFeedback {
  const ServedFeedback({
    required this.id,
    this.calledAt,
    this.rating,
    this.outcome,
    this.feedback,
    this.challenges,
    this.internalNotes,
    this.createdByName,
  });

  final String id;
  final DateTime? calledAt;
  final int? rating;

  /// `satisfied`, `neutral`, `dissatisfied`.
  final String? outcome;
  final String? feedback;
  final String? challenges;
  final String? internalNotes;
  final String? createdByName;

  factory ServedFeedback.fromJson(Map<String, dynamic> json) => ServedFeedback(
    id: json.id(),
    calledAt: json.date('called_at'),
    rating: json['rating'] == null ? null : json.count('rating'),
    outcome: json.str('outcome'),
    feedback: json.str('feedback'),
    challenges: json.str('challenges'),
    internalNotes: json.str('internal_notes'),
    createdByName: json.object('created_by')?.str('name'),
  );
}

/// A customer served at the counter, with any follow-up feedback.
class ServedCustomer {
  const ServedCustomer({
    required this.id,
    required this.name,
    required this.services,
    required this.feedbacks,
    this.phone,
    this.servedDate,
    this.notes,
    this.createdAt,
    this.createdByName,
  });

  final String id;
  final String name;
  final List<ServedService> services;
  final List<ServedFeedback> feedbacks;
  final String? phone;
  final DateTime? servedDate;
  final String? notes;
  final DateTime? createdAt;
  final String? createdByName;

  bool get hasFeedback => feedbacks.isNotEmpty;

  factory ServedCustomer.fromJson(Map<String, dynamic> json) => ServedCustomer(
    id: json.id(),
    name: json.strOr('name', '—'),
    services: json.list('services', ServedService.fromJson),
    feedbacks: json.list('feedbacks', ServedFeedback.fromJson),
    phone: json.str('phone'),
    servedDate: json.date('served_date'),
    notes: json.str('notes'),
    createdAt: json.date('created_at'),
    createdByName: json.object('created_by')?.str('name'),
  );
}

/// The daily counter target for the served-customers desk.
class ServedTarget {
  const ServedTarget({
    required this.id,
    required this.newCustomersTarget,
    required this.calledCustomersTarget,
    required this.activeDays,
    this.effectiveFrom,
  });

  final String id;
  final int newCustomersTarget;
  final int calledCustomersTarget;

  /// ISO weekdays (1 = Monday) the target applies to.
  final List<int> activeDays;
  final DateTime? effectiveFrom;

  factory ServedTarget.fromJson(Map<String, dynamic> json) {
    final days = json['active_days'];
    return ServedTarget(
      id: json.id(),
      newCustomersTarget: json.count('new_customers_target'),
      calledCustomersTarget: json.count('called_customers_target'),
      activeDays: days is List
          ? days.map((d) => readInt(d)).where((d) => d > 0).toList()
          : const [],
      effectiveFrom: json.date('effective_from'),
    );
  }
}

/// One day in the weekly served-customers summary.
class ServedDay {
  const ServedDay({
    required this.date,
    required this.dayName,
    required this.isActive,
    required this.newCustomers,
    required this.callsMade,
  });

  final String date;
  final String dayName;
  final bool isActive;
  final int newCustomers;
  final int callsMade;

  factory ServedDay.fromJson(Map<String, dynamic> json) => ServedDay(
    date: json.strOr('date', ''),
    dayName: json.strOr('day_name', ''),
    isActive: json.flag('is_active', fallback: true),
    newCustomers: json.count('new_customers'),
    callsMade: json.count('calls_made'),
  );
}

/// `GET /served/weekly-summary` — progress against the weekly target.
class ServedWeeklySummary {
  const ServedWeeklySummary({
    required this.newCustomersAchieved,
    required this.callsAchieved,
    required this.daily,
    this.weekStart,
    this.weekEnd,
    this.target,
    this.newCustomersTarget,
    this.callsTarget,
  });

  final int newCustomersAchieved;
  final int callsAchieved;
  final List<ServedDay> daily;
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final ServedTarget? target;

  /// Null when no target has been configured for the tenant.
  final int? newCustomersTarget;
  final int? callsTarget;

  factory ServedWeeklySummary.fromJson(Map<String, dynamic> json) =>
      ServedWeeklySummary(
        newCustomersAchieved: json.count('new_customers_achieved'),
        callsAchieved: json.count('calls_achieved'),
        daily: json.list('daily', ServedDay.fromJson),
        weekStart: json.date('week_start'),
        weekEnd: json.date('week_end'),
        target: json.object('target') == null
            ? null
            : ServedTarget.fromJson(json.object('target')!),
        newCustomersTarget: json['new_customers_target'] == null
            ? null
            : json.count('new_customers_target'),
        callsTarget: json['calls_target'] == null
            ? null
            : json.count('calls_target'),
      );
}

/// One day of `GET /served/report` — richer than [ServedDay] (which backs
/// the weekly summary): each day also carries its own target and percent
/// achieved, and which ISO week it falls in, for a month-spanning table.
class ServedReportDay {
  const ServedReportDay({
    required this.date,
    required this.dayName,
    required this.week,
    required this.isActive,
    required this.newCustomers,
    required this.newTarget,
    required this.newPct,
    required this.callsMade,
    required this.callsTarget,
    required this.callsPct,
  });

  final String date;
  final String dayName;
  final int week;
  final bool isActive;
  final int newCustomers;
  final int newTarget;
  final double newPct;
  final int callsMade;
  final int callsTarget;
  final double callsPct;

  factory ServedReportDay.fromJson(Map<String, dynamic> json) =>
      ServedReportDay(
        date: json.strOr('date', ''),
        dayName: json.strOr('day_name', ''),
        week: json.count('week'),
        isActive: json.flag('is_active', fallback: true),
        newCustomers: json.count('new_customers'),
        newTarget: json.count('new_target'),
        newPct: readDouble(json['new_pct']),
        callsMade: json.count('calls_made'),
        callsTarget: json.count('calls_target'),
        callsPct: readDouble(json['calls_pct']),
      );
}

/// `GET /served/report` — a date range's daily breakdown against target,
/// defaulting server-side to the current month.
class ServedReport {
  const ServedReport({
    required this.startDate,
    required this.endDate,
    required this.newCustomersAchieved,
    required this.newCustomersTarget,
    required this.callsAchieved,
    required this.callsTarget,
    required this.daily,
    this.target,
  });

  final String startDate;
  final String endDate;
  final int newCustomersAchieved;
  final int newCustomersTarget;
  final int callsAchieved;
  final int callsTarget;
  final List<ServedReportDay> daily;

  /// Null when the tenant has never set a target.
  final ServedTarget? target;

  factory ServedReport.fromJson(Map<String, dynamic> json) => ServedReport(
    startDate: json.strOr('start_date', ''),
    endDate: json.strOr('end_date', ''),
    newCustomersAchieved: json.count('new_customers_achieved'),
    newCustomersTarget: json.count('new_customers_target'),
    callsAchieved: json.count('calls_achieved'),
    callsTarget: json.count('calls_target'),
    daily: json.list('daily', ServedReportDay.fromJson),
    target: json.object('target') == null
        ? null
        : ServedTarget.fromJson(json.object('target')!),
  );
}

/// Outcomes `POST /served/customers/{id}/feedback` accepts.
abstract final class ServedFeedbackOutcomes {
  static const values = <(String, String)>[
    ('satisfied', 'Satisfied'),
    ('neutral', 'Neutral'),
    ('dissatisfied', 'Dissatisfied'),
  ];
}

// ─────────────────────────────────────────────────────────────
// Field marketing — FieldMarketingController
// ─────────────────────────────────────────────────────────────

/// A day out in the field by one officer, in one area.
class FieldSession {
  const FieldSession({
    required this.id,
    required this.area,
    required this.visitsCount,
    required this.interestedCount,
    required this.convertedCount,
    this.officerId,
    this.officerName,
    this.visitDate,
    this.summary,
    this.challenges,
    this.recommendations,
  });

  final String id;
  final String area;
  final int visitsCount;
  final int interestedCount;
  final int convertedCount;
  final String? officerId;
  final String? officerName;
  final DateTime? visitDate;
  final String? summary;
  final String? challenges;
  final String? recommendations;

  factory FieldSession.fromJson(Map<String, dynamic> json) {
    final officer = json.object('officer');
    return FieldSession(
      id: json.id(),
      area: json.strOr('area', '—'),
      // Absent on the create/update responses, which return the raw model.
      visitsCount: json.count('visits_count'),
      interestedCount: json.count('interested_count'),
      convertedCount: json.count('converted_count'),
      officerId: json.str('officer_id') ?? officer?.str('id'),
      officerName: officer?.str('name'),
      visitDate: json.date('visit_date'),
      summary: json.str('summary'),
      challenges: json.str('challenges'),
      recommendations: json.str('recommendations'),
    );
  }
}

/// One business visited during a field session.
class FieldVisit {
  const FieldVisit({
    required this.id,
    required this.businessName,
    required this.status,
    required this.services,
    this.sessionId,
    this.officerName,
    this.location,
    this.phone,
    this.feedback,
    this.nextFollowupDate,
    this.clientId,
    this.clientName,
    this.visitDate,
    this.area,
  });

  final String id;
  final String businessName;

  /// `interested`, `not_interested`, `follow_up`, `converted`.
  final String status;
  final List<String> services;
  final String? sessionId;
  final String? officerName;
  final String? location;
  final String? phone;
  final String? feedback;
  final DateTime? nextFollowupDate;
  final String? clientId;
  final String? clientName;

  /// Present on the visits report, which joins the parent session.
  final DateTime? visitDate;
  final String? area;

  bool get isConverted => status == 'converted';

  factory FieldVisit.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final officer = json.object('officer');
    return FieldVisit(
      id: json.id(),
      businessName: json.strOr('business_name', '—'),
      status: json.strOr('status', 'interested'),
      services: json.strings('services'),
      sessionId: json.str('session_id'),
      officerName: officer?.str('name'),
      location: json.str('location'),
      phone: json.str('phone'),
      feedback: json.str('feedback'),
      nextFollowupDate: json.date('next_followup_date'),
      clientId: json.str('client_id') ?? client?.str('id'),
      clientName: client?.str('name'),
      visitDate: json.date('visit_date'),
      area: json.str('area'),
    );
  }
}

/// A field session with its visits — `GET /field-sessions/{id}`.
class FieldSessionDetail {
  const FieldSessionDetail({required this.session, required this.visits});

  final FieldSession session;
  final List<FieldVisit> visits;

  /// The detail endpoint returns the raw session model without the
  /// `*_count` aggregates the list carries, so derive them from the visits.
  factory FieldSessionDetail.fromJson(Map<String, dynamic> json) {
    final visits = json.list('visits', FieldVisit.fromJson);
    final session = Map<String, dynamic>.from(
      json.object('session') ?? const <String, dynamic>{},
    );
    session['visits_count'] ??= visits.length;
    session['interested_count'] ??= visits
        .where((v) => v.status == 'interested')
        .length;
    session['converted_count'] ??= visits
        .where((v) => v.status == 'converted')
        .length;
    return FieldSessionDetail(
      session: FieldSession.fromJson(session),
      visits: visits,
    );
  }
}

/// An officer's monthly new-client target and progress against it.
class FieldTarget {
  const FieldTarget({
    required this.id,
    required this.month,
    required this.year,
    required this.targetClients,
    required this.wonClients,
    required this.totalVisits,
    required this.progress,
    this.officerName,
    this.officerId,
  });

  final String id;
  final int month;
  final int year;
  final int targetClients;
  final int wonClients;
  final int totalVisits;

  /// Percent complete, as computed server-side.
  final int progress;
  final String? officerName;
  final String? officerId;

  factory FieldTarget.fromJson(Map<String, dynamic> json) {
    final officer = json.object('officer');
    return FieldTarget(
      id: json.id(),
      month: json.count('month'),
      year: json.count('year'),
      targetClients: json.count('target_clients'),
      wonClients: json.count('won_clients'),
      totalVisits: json.count('total_visits'),
      progress: json.count('progress'),
      officerName: officer?.str('name'),
      officerId: json.str('officer_id') ?? officer?.str('id'),
    );
  }
}

/// Statuses `POST /field-sessions/{id}/visits` accepts.
abstract final class FieldVisitStatuses {
  static const values = <(String, String)>[
    ('interested', 'Interested'),
    ('follow_up', 'Follow up'),
    ('converted', 'Converted'),
    ('not_interested', 'Not interested'),
  ];
}

/// One logged call against a field visit — `FieldFollowupController`.
///
/// The store route does more than record a call: a `next_followup_date` is
/// copied onto the visit, and an `interested` / `not_interested` / `converted`
/// outcome rewrites the visit's status. Callers should therefore refresh the
/// visit after logging one.
class FieldFollowup {
  const FieldFollowup({
    required this.id,
    required this.outcome,
    this.visitId,
    this.callDate,
    this.notes,
    this.nextFollowupDate,
    this.userName,
  });

  final String id;

  /// `answered`, `no_answer`, `callback`, `interested`, `not_interested`,
  /// `converted`.
  final String outcome;
  final String? visitId;
  final DateTime? callDate;
  final String? notes;
  final DateTime? nextFollowupDate;
  final String? userName;

  factory FieldFollowup.fromJson(Map<String, dynamic> json) => FieldFollowup(
    id: json.id(),
    outcome: json.strOr('outcome', 'answered'),
    visitId: json.str('visit_id'),
    callDate: json.date('call_date'),
    notes: json.str('notes'),
    nextFollowupDate: json.date('next_followup_date'),
    userName: json.object('user')?.str('name'),
  );
}

/// Outcomes `POST /field-visits/{visit}/followups` accepts.
abstract final class FieldFollowupOutcomes {
  static const values = <(String, String)>[
    ('answered', 'Answered'),
    ('no_answer', 'No answer'),
    ('callback', 'Call back'),
    ('interested', 'Interested'),
    ('not_interested', 'Not interested'),
    ('converted', 'Converted'),
  ];
}

/// One officer's row in `GET /field-stats`.
class FieldOfficerStat {
  const FieldOfficerStat({
    required this.visits,
    required this.won,
    this.officerId,
    this.officerName,
  });

  final int visits;
  final int won;
  final String? officerId;
  final String? officerName;

  factory FieldOfficerStat.fromJson(Map<String, dynamic> json) =>
      FieldOfficerStat(
        visits: json.count('visits'),
        won: json.count('won'),
        officerId: json.str('officer_id'),
        officerName: json.object('officer')?.str('name'),
      );
}

/// `GET /field-stats` — a month's canvassing at a glance.
class FieldStats {
  const FieldStats({
    required this.totalVisits,
    required this.totalConverted,
    required this.byStatus,
    required this.byOfficer,
  });

  final int totalVisits;
  final int totalConverted;

  /// Visit counts keyed by visit status; `pluck` gives an object, and a month
  /// with no visits of a status simply omits the key.
  final Map<String, int> byStatus;
  final List<FieldOfficerStat> byOfficer;

  factory FieldStats.fromJson(Map<String, dynamic> json) {
    final statuses = json['by_status'];
    return FieldStats(
      totalVisits: json.count('total_visits'),
      totalConverted: json.count('total_converted'),
      byStatus: statuses is Map
          ? {
              for (final entry in statuses.entries)
                entry.key.toString(): readInt(entry.value),
            }
          : const <String, int>{},
      byOfficer: json.list('by_officer', FieldOfficerStat.fromJson),
    );
  }
}

/// One row of `GET /marketing-services` — the tenant-editable reference list
/// a field visit or WhatsApp contact tags itself with. `MarketingServiceController`
/// answers bare (no `data` envelope): an array from `index`, a single object
/// from `store`/`update`.
class MarketingServiceItem {
  const MarketingServiceItem({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;

  factory MarketingServiceItem.fromJson(Map<String, dynamic> json) =>
      MarketingServiceItem(
        id: json.id(),
        name: json.strOr('name', '—'),
        sortOrder: json.count('sort_order'),
      );
}

/// Emergency fallback only, used when `GET /marketing-services` has never
/// once succeeded (first launch offline, or the endpoint erroring) — see
/// `_VisitFormSheetState` in `field_marketing_screen.dart`.
///
/// This used to be the *only* source for the "services discussed" picker,
/// hardcoded and silently drifting from whatever a tenant had actually
/// customised or reordered via the web's Field Marketing > Services tab.
/// Every real load now comes from [MarketingServiceItem] instead.
abstract final class FieldServices {
  static const values = <String>[
    'MoBilling',
    'Bulk SMS',
    'Hosting',
    'Web Design',
    'CCTV',
    'POS System',
    'E-File System',
    'IT Support',
    'Online Marketing',
    'Other',
  ];
}
