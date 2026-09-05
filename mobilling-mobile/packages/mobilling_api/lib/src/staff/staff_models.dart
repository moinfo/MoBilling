/// Staff-app models, matching the tenant-side controllers.
///
/// The staff dashboard (`DashboardController::summary`) is permission-gated
/// per field: metrics the user may not see arrive as NULL (withheld
/// server-side, not merely hidden). Nullable fields here therefore mean
/// "not allowed", and the UI hides those cards entirely.
library;

import '../json.dart';
import '../portal/support_models.dart' show TicketReply;

class StaffDashboard {
  const StaffDashboard({
    this.totalReceivable,
    this.totalReceived,
    this.outstanding,
    this.overdueInvoices,
    this.overdueBills,
    this.totalClients,
    this.totalDocuments,
    this.totalExpenses,
    this.smsBalance,
    this.whatsappContacts,
    this.fieldVisits,
    this.hosting,
    this.statutory,
    this.subscriptions,
    this.penalties,
    this.systemRecords,
    required this.recentInvoices,
    required this.monthlyRevenue,
    required this.invoiceStatusBreakdown,
    required this.paymentMethodBreakdown,
    required this.topClients,
    required this.upcomingBills,
    required this.upcomingRenewals,
    required this.urgentObligations,
    required this.calendar,
  });

  final double? totalReceivable;
  final double? totalReceived;
  final double? outstanding;
  final int? overdueInvoices;
  final int? totalClients;
  final int? totalDocuments;
  final double? totalExpenses;
  final int? smsBalance;
  final int? overdueBills;
  final int? whatsappContacts;
  final int? fieldVisits;

  /// Grouped blocks. Null means the role cannot see that whole section.
  final HostingDomainsStats? hosting;
  final StatutoryStats? statutory;
  final SubscriptionStats? subscriptions;
  final StaffPenalties? penalties;
  final SystemRecordsStats? systemRecords;

  final List<StaffInvoiceRow> recentInvoices;
  final List<MonthlyRevenuePoint> monthlyRevenue;
  final List<StatusCount> invoiceStatusBreakdown;
  final List<MethodTotal> paymentMethodBreakdown;
  final List<TopClient> topClients;
  final List<UpcomingBill> upcomingBills;
  final List<UpcomingRenewal> upcomingRenewals;
  final List<UrgentObligation> urgentObligations;

  /// One entry per date that has at least one activity, current month ± 1
  /// (`dashboard.activity_calendar`) — empty, not null, when withheld.
  final List<CalendarDay> calendar;

  factory StaffDashboard.fromJson(Map<String, dynamic> json) => StaffDashboard(
    totalReceivable: json['total_receivable'] == null
        ? null
        : json.money('total_receivable'),
    totalReceived: json['total_received'] == null
        ? null
        : json.money('total_received'),
    outstanding: json['outstanding'] == null ? null : json.money('outstanding'),
    overdueInvoices: json['overdue_invoices'] == null
        ? null
        : json.count('overdue_invoices'),
    totalClients: json['total_clients'] == null
        ? null
        : json.count('total_clients'),
    totalDocuments: json['total_documents'] == null
        ? null
        : json.count('total_documents'),
    totalExpenses: json['total_expenses'] == null
        ? null
        : json.money('total_expenses'),
    smsBalance: json['sms_balance'] == null ? null : json.count('sms_balance'),
    recentInvoices: json.list('recent_invoices', StaffInvoiceRow.fromJson),
    monthlyRevenue: json.list('monthly_revenue', MonthlyRevenuePoint.fromJson),
    overdueBills: json['overdue_bills'] == null
        ? null
        : json.count('overdue_bills'),
    whatsappContacts: json['total_whatsapp_contacts'] == null
        ? null
        : json.count('total_whatsapp_contacts'),
    fieldVisits: json['total_field_visits'] == null
        ? null
        : json.count('total_field_visits'),
    hosting: switch (json.object('hosting_domains')) {
      final o? => HostingDomainsStats.fromJson(o),
      _ => null,
    },
    statutory: switch (json.object('statutory_stats')) {
      final o? => StatutoryStats.fromJson(o),
      _ => null,
    },
    subscriptions: switch (json.object('subscription_stats')) {
      final o? => SubscriptionStats.fromJson(o),
      _ => null,
    },
    penalties: switch (json.object('staff_penalties')) {
      final o? => StaffPenalties.fromJson(o),
      _ => null,
    },
    systemRecords: switch (json.object('system_records')) {
      final o? => SystemRecordsStats.fromJson(o),
      _ => null,
    },
    invoiceStatusBreakdown: json.list(
      'invoice_status_breakdown',
      StatusCount.fromJson,
    ),
    paymentMethodBreakdown: json.list(
      'payment_method_breakdown',
      MethodTotal.fromJson,
    ),
    topClients: json.list('top_clients', TopClient.fromJson),
    upcomingBills: json.list('upcoming_bills', UpcomingBill.fromJson),
    upcomingRenewals: json.list('upcoming_renewals', UpcomingRenewal.fromJson),
    urgentObligations: json.list(
      'urgent_obligations',
      UrgentObligation.fromJson,
    ),
    calendar: json.list('calendar', CalendarDay.fromJson),
  );
}

/// One calendar day carrying at least one activity — followups, satisfaction
/// calls, client visits, invoice/bill/statutory due dates, WhatsApp and field
/// follow-ups all land here, current month ± 1.
class CalendarDay {
  const CalendarDay({required this.dateKey, required this.items});

  /// `Y-m-d`, as the API sends it — used as the lookup key, not parsed to a
  /// [DateTime] here since the grid builds its own dates and only needs to
  /// match this string back.
  final String dateKey;
  final List<CalendarItem> items;

  factory CalendarDay.fromJson(Map<String, dynamic> json) => CalendarDay(
    dateKey: json.strOr('date', ''),
    items: json.list('items', CalendarItem.fromJson),
  );
}

/// One activity on a [CalendarDay].
class CalendarItem {
  const CalendarItem({required this.type, required this.label, this.detail});

  /// followup | satisfaction | appointment | invoice | bill | statutory |
  /// whatsapp | field_followup.
  final String type;
  final String label;
  final String? detail;

  factory CalendarItem.fromJson(Map<String, dynamic> json) => CalendarItem(
    type: json.strOr('type', 'followup'),
    label: json.strOr('label', '—'),
    detail: json.str('detail'),
  );
}

/// Display metadata for [CalendarItem.type], mirroring the web dashboard's
/// `typeConfig` map so both clients group and label activities alike.
abstract final class CalendarItemTypes {
  static const order = [
    'followup',
    'satisfaction',
    'appointment',
    'invoice',
    'bill',
    'statutory',
    'whatsapp',
    'field_followup',
  ];

  static const labels = <String, String>{
    'followup': 'Follow-up',
    'satisfaction': 'Satisfaction call',
    'appointment': 'Client visit',
    'invoice': 'Invoice due',
    'bill': 'Bill due',
    'statutory': 'Statutory',
    'whatsapp': 'WhatsApp follow-up',
    'field_followup': 'Field follow-up',
  };

  static String label(String type) => labels[type] ?? type;
}

/// Hosting accounts and domains, with the counts the web dashboard shows.
///
/// The endpoint sends its own `can` map here rather than simply omitting the
/// block, so a role with hosting but not domains still gets the hosting half.
class HostingDomainsStats {
  const HostingDomainsStats({
    required this.canHosting,
    required this.canDomains,
    required this.canTickets,
    required this.hostingTotal,
    required this.hostingActive,
    required this.hostingSuspended,
    required this.domainsTotal,
    required this.domainsActive,
    required this.domainsExpiringSoon,
    required this.openTickets,
    required this.registrarCredit,
    required this.expiringDomains,
  });

  final bool canHosting;
  final bool canDomains;
  final bool canTickets;
  final int hostingTotal;
  final int hostingActive;
  final int hostingSuspended;
  final int domainsTotal;
  final int domainsActive;
  final int domainsExpiringSoon;
  final int openTickets;

  /// Null when the registrar balance has not been synced — must render as
  /// "not synced", never as zero credit.
  final double? registrarCredit;

  final List<ExpiringDomain> expiringDomains;

  factory HostingDomainsStats.fromJson(Map<String, dynamic> json) {
    final can = json.object('can');
    final hosting = json.object('hosting');
    final domains = json.object('domains');
    return HostingDomainsStats(
      canHosting: can?.flag('hosting') ?? false,
      canDomains: can?.flag('domains') ?? false,
      canTickets: can?.flag('tickets') ?? false,
      hostingTotal: hosting?.count('total') ?? 0,
      hostingActive: hosting?.count('active') ?? 0,
      hostingSuspended: hosting?.count('suspended') ?? 0,
      domainsTotal: domains?.count('total') ?? 0,
      domainsActive: domains?.count('active') ?? 0,
      domainsExpiringSoon: domains?.count('expiring_soon') ?? 0,
      openTickets: json.count('open_tickets'),
      registrarCredit: json['registrar_credit_total'] == null
          ? null
          : json.money('registrar_credit_total'),
      expiringDomains: json.list('expiring_domains', ExpiringDomain.fromJson),
    );
  }
}

class ExpiringDomain {
  const ExpiringDomain({
    required this.id,
    required this.name,
    this.clientName,
    this.expiresAt,
    this.daysLeft,
    required this.autoRenew,
  });

  final String id;
  final String name;
  final String? clientName;
  final DateTime? expiresAt;

  /// Negative once expired.
  final int? daysLeft;
  final bool autoRenew;

  factory ExpiringDomain.fromJson(Map<String, dynamic> json) => ExpiringDomain(
    id: json.id(),
    name: json.strOr('name', '—'),
    clientName: json.str('client_name'),
    expiresAt: json.date('expires_at'),
    daysLeft: json['days_left'] == null ? null : json.count('days_left'),
    autoRenew: json.flag('auto_renew'),
  );
}

class StatutoryStats {
  const StatutoryStats({
    required this.totalActive,
    required this.overdue,
    required this.dueSoon,
  });

  final int totalActive;
  final int overdue;
  final int dueSoon;

  factory StatutoryStats.fromJson(Map<String, dynamic> json) => StatutoryStats(
    totalActive: json.count('total_active'),
    overdue: json.count('overdue'),
    dueSoon: json.count('due_soon'),
  );
}

class SubscriptionStats {
  const SubscriptionStats({
    required this.active,
    required this.pending,
    required this.cancelled,
  });

  final int active;
  final int pending;
  final int cancelled;

  int get total => active + pending + cancelled;

  factory SubscriptionStats.fromJson(Map<String, dynamic> json) =>
      SubscriptionStats(
        active: json.count('active'),
        pending: json.count('pending'),
        cancelled: json.count('cancelled'),
      );
}

/// What this month's missed reports have cost the signed-in user.
///
/// Personal, not company-wide — it is the one block on the dashboard about
/// the reader rather than the business.
class StaffPenalties {
  const StaffPenalties({
    required this.monthLabel,
    required this.monthTotal,
    required this.countThisMonth,
    required this.byType,
  });

  final String monthLabel;
  final double monthTotal;
  final int countThisMonth;
  final List<PenaltyByType> byType;

  factory StaffPenalties.fromJson(Map<String, dynamic> json) => StaffPenalties(
    monthLabel: json.strOr('month_label', ''),
    monthTotal: json.money('month_total'),
    countThisMonth: json.count('count_this_month'),
    byType: json.list('by_type', PenaltyByType.fromJson),
  );
}

class PenaltyByType {
  const PenaltyByType({
    required this.reportType,
    required this.count,
    required this.total,
  });

  /// daily | weekly | monthly.
  final String reportType;
  final int count;
  final double total;

  factory PenaltyByType.fromJson(Map<String, dynamic> json) => PenaltyByType(
    reportType: json.strOr('report_type', ''),
    count: json.count('count'),
    total: json.money('total'),
  );
}

class SystemRecordsStats {
  const SystemRecordsStats({
    required this.total,
    required this.systems,
    required this.byBank,
  });

  final double total;
  final List<NamedTotal> systems;
  final List<NamedTotal> byBank;

  factory SystemRecordsStats.fromJson(Map<String, dynamic> json) =>
      SystemRecordsStats(
        total: json.money('total'),
        systems: json.list('systems', NamedTotal.fromSystem),
        byBank: json.list('by_bank', NamedTotal.fromBank),
      );
}

/// A label and an amount — the shape both system-record breakdowns share.
class NamedTotal {
  const NamedTotal({required this.name, required this.total, this.detail});

  final String name;
  final double total;
  final String? detail;

  factory NamedTotal.fromSystem(Map<String, dynamic> json) => NamedTotal(
    name: json.strOr('name', '—'),
    total: json.money('total'),
    detail: json.str('detail'),
  );

  factory NamedTotal.fromBank(Map<String, dynamic> json) => NamedTotal(
    name: json.strOr('bank_name', '—'),
    total: json.money('total'),
    detail: json.str('account_number'),
  );
}

class MethodTotal {
  const MethodTotal({required this.method, required this.amount});

  final String method;
  final double amount;

  factory MethodTotal.fromJson(Map<String, dynamic> json) => MethodTotal(
    method: json.strOr('method', json.strOr('payment_method', '—')),
    amount: json.money('amount'),
  );
}

class TopClient {
  const TopClient({
    required this.name,
    required this.total,
    required this.paid,
  });

  final String name;
  final double total;
  final double paid;

  factory TopClient.fromJson(Map<String, dynamic> json) => TopClient(
    name: json.strOr('name', 'Unknown'),
    total: json.money('total'),
    paid: json.money('paid'),
  );
}

class UpcomingBill {
  const UpcomingBill({
    required this.id,
    required this.name,
    required this.amount,
    this.dueDate,
    this.category,
  });

  final String id;
  final String name;
  final double amount;
  final DateTime? dueDate;
  final String? category;

  factory UpcomingBill.fromJson(Map<String, dynamic> json) => UpcomingBill(
    id: json.id(),
    name: json.strOr('name', '—'),
    amount: json.money('amount'),
    dueDate: json.date('due_date'),
    category: json.str('category'),
  );
}

class UpcomingRenewal {
  const UpcomingRenewal({
    this.clientName,
    this.productName,
    this.label,
    this.nextBillDate,
    required this.price,
  });

  final String? clientName;
  final String? productName;

  /// The domain or service instance the subscription is for.
  final String? label;
  final DateTime? nextBillDate;
  final double price;

  factory UpcomingRenewal.fromJson(Map<String, dynamic> json) =>
      UpcomingRenewal(
        clientName: json.str('client_name'),
        productName: json.str('product_name'),
        label: json.str('label'),
        nextBillDate: json.date('next_bill_date'),
        price: json.money('price'),
      );
}

class UrgentObligation {
  const UrgentObligation({
    required this.id,
    required this.name,
    required this.amount,
    this.nextDueDate,
    this.daysRemaining,
    this.cycle,
  });

  final String id;
  final String name;
  final double amount;
  final DateTime? nextDueDate;

  /// Negative once past due.
  final int? daysRemaining;
  final String? cycle;

  factory UrgentObligation.fromJson(Map<String, dynamic> json) =>
      UrgentObligation(
        id: json.id(),
        name: json.strOr('name', '—'),
        amount: json.money('amount'),
        nextDueDate: json.date('next_due_date'),
        daysRemaining: json['days_remaining'] == null
            ? null
            : json.count('days_remaining'),
        cycle: json.str('cycle'),
      );
}

class MonthlyRevenuePoint {
  const MonthlyRevenuePoint({
    required this.month,
    required this.invoiced,
    required this.collected,
  });

  final String month;
  final double invoiced;
  final double collected;

  factory MonthlyRevenuePoint.fromJson(Map<String, dynamic> json) =>
      MonthlyRevenuePoint(
        month: json.strOr('month', ''),
        invoiced: json.money('invoiced'),
        collected: json.money('collected'),
      );
}

class StatusCount {
  const StatusCount({required this.status, required this.count});

  final String status;
  final int count;

  factory StatusCount.fromJson(Map<String, dynamic> json) => StatusCount(
    status: json.strOr('status', 'unknown'),
    count: json.count('count'),
  );
}

/// A document row in staff lists — the raw Eloquent model with client
/// relation, so money fields are decimal STRINGS.
class StaffInvoiceRow {
  const StaffInvoiceRow({
    required this.id,
    required this.documentNumber,
    required this.status,
    required this.total,
    this.clientName,
    this.clientId,
    this.description,
    this.type,
    this.date,
    this.dueDate,
    this.reminderCount = 0,
  });

  final String id;
  final String documentNumber;
  final String status;
  final double total;
  final String? clientName;
  final String? clientId;
  final String? description;
  final String? type;
  final DateTime? date;
  final DateTime? dueDate;

  /// How many payment reminders have gone out for this document — same
  /// field the detail screen already reads, just missing from the list row.
  final int reminderCount;

  factory StaffInvoiceRow.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    return StaffInvoiceRow(
      id: json.id(),
      documentNumber: json.strOr('document_number', '—'),
      status: json.strOr('status', 'draft'),
      total: json.money('total'),
      clientName: json.str('client_name') ?? client?.str('name'),
      clientId: json.str('client_id') ?? client?.str('id'),
      description: json.str('description') ?? _firstItem(json),
      type: json.str('type'),
      date: json.date('date'),
      dueDate: json.date('due_date'),
      reminderCount: json.count('reminder_count'),
    );
  }

  static String? _firstItem(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is List && items.isNotEmpty && items.first is Map) {
      return Map<String, dynamic>.from(items.first as Map).str('description');
    }
    return null;
  }
}

/// A client row (`ClientController::index`): raw model plus the two computed
/// columns the list view needs.
///
/// `ClientResource` also carries the WHMCS-style structured name and address
/// columns, which the edit form needs to round-trip — a form seeded without
/// them would blank `city`/`country` on the first save, because
/// `StoreClientRequest` validates every one of them as `nullable` and
/// `Client::update()` writes whatever `validated()` contains.
class StaffClient {
  const StaffClient({
    required this.id,
    required this.name,
    required this.activeSubscriptionsCount,
    required this.subscriptionTotal,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.creditBalance,
    this.firstName,
    this.lastName,
    this.companyName,
    this.address1,
    this.address2,
    this.city,
    this.state,
    this.postcode,
    this.country,
    this.createdAt,
  });

  final String id;
  final String name;
  final int activeSubscriptionsCount;

  /// Sum of active subscription value (qty × price).
  final double subscriptionTotal;
  final String? email;
  final String? phone;
  final String? address;
  final String? taxId;
  final double? creditBalance;

  /// WHMCS-style structured fields — all optional, all additive alongside the
  /// flat [name] / [address] above.
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? address1;
  final String? address2;
  final String? city;
  final String? state;
  final String? postcode;

  /// ISO 3166-1 alpha-2. The API validates `size:2`.
  final String? country;

  final DateTime? createdAt;

  factory StaffClient.fromJson(Map<String, dynamic> json) => StaffClient(
    id: json.id(),
    name: json.strOr('name', '—'),
    activeSubscriptionsCount: json.count('active_subscriptions_count'),
    subscriptionTotal: json.money('subscription_total'),
    email: json.str('email'),
    phone: json.str('phone'),
    address: json.str('address'),
    taxId: json.str('tax_id'),
    creditBalance: json['credit_balance'] == null
        ? null
        : json.money('credit_balance'),
    firstName: json.str('first_name'),
    lastName: json.str('last_name'),
    companyName: json.str('company_name'),
    address1: json.str('address_1'),
    address2: json.str('address_2'),
    city: json.str('city'),
    state: json.str('state'),
    postcode: json.str('postcode'),
    country: json.str('country'),
    createdAt: json.date('created_at'),
  );
}

/// What `POST /clients` and `PUT /clients/{client}` accept — the whole of
/// `StoreClientRequest`.
///
/// Every field but [name] goes out even when blank, as an explicit null:
/// `update()` writes `validated()` wholesale, so omitting a key that the form
/// cleared would silently keep the old value. [toJson] therefore maps empty
/// strings to null rather than dropping them.
class ClientInput {
  const ClientInput({
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.firstName,
    this.lastName,
    this.companyName,
    this.address1,
    this.address2,
    this.city,
    this.state,
    this.postcode,
    this.country,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? taxId;
  final String? firstName;
  final String? lastName;
  final String? companyName;
  final String? address1;
  final String? address2;
  final String? city;
  final String? state;
  final String? postcode;

  /// Two letters or nothing — the API rejects anything else with a 422.
  final String? country;

  /// Seeds an edit form from a loaded record.
  factory ClientInput.from(StaffClient client) => ClientInput(
    name: client.name,
    email: client.email,
    phone: client.phone,
    address: client.address,
    taxId: client.taxId,
    firstName: client.firstName,
    lastName: client.lastName,
    companyName: client.companyName,
    address1: client.address1,
    address2: client.address2,
    city: client.city,
    state: client.state,
    postcode: client.postcode,
    country: client.country,
  );

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'email': _blankToNull(email),
    'phone': _blankToNull(phone),
    'address': _blankToNull(address),
    'tax_id': _blankToNull(taxId),
    'first_name': _blankToNull(firstName),
    'last_name': _blankToNull(lastName),
    'company_name': _blankToNull(companyName),
    'address_1': _blankToNull(address1),
    'address_2': _blankToNull(address2),
    'city': _blankToNull(city),
    'state': _blankToNull(state),
    'postcode': _blankToNull(postcode),
    'country': _blankToNull(country)?.toUpperCase(),
  };
}

/// `GET /clients/stats` — the counters above the client list.
///
/// [subscriptionValue] and [creditBalanceTotal] are withheld server-side
/// unless the user holds `client_profile.subscription_value`, so null here
/// means "not allowed to see" and the tile is dropped rather than zeroed.
class ClientCounters {
  const ClientCounters({
    required this.totalClients,
    required this.withSubscriptions,
    required this.withoutSubscriptions,
    required this.activeSubscriptions,
    required this.newThisMonth,
    this.subscriptionValue,
    this.creditBalanceTotal,
  });

  final int totalClients;
  final int withSubscriptions;
  final int withoutSubscriptions;
  final int activeSubscriptions;
  final int newThisMonth;
  final double? subscriptionValue;
  final double? creditBalanceTotal;

  factory ClientCounters.fromJson(Map<String, dynamic> json) => ClientCounters(
    totalClients: json.count('total_clients'),
    withSubscriptions: json.count('with_subscriptions'),
    withoutSubscriptions: json.count('without_subscriptions'),
    activeSubscriptions: json.count('active_subscriptions'),
    newThisMonth: json.count('new_this_month'),
    subscriptionValue: json['subscription_value'] == null
        ? null
        : json.money('subscription_value'),
    creditBalanceTotal: json['credit_balance_total'] == null
        ? null
        : json.money('credit_balance_total'),
  );
}

// ---------------------------------------------------------------------------
// Client 360 profile — GET /clients/{client}/profile
// ---------------------------------------------------------------------------

/// Everything `ClientController::profile` returns in one payload.
///
/// The endpoint is hand-built rather than resource-driven, so amounts arrive
/// as a mix of JSON numbers and decimal strings; every field here goes
/// through the tolerant readers in `json.dart`.
class ClientProfile {
  const ClientProfile({
    required this.client,
    required this.summary,
    required this.creditBalance,
    required this.isReseller,
    required this.clientStatus,
    required this.billingBreakdown,
    required this.contacts,
    required this.domains,
    required this.tickets,
    required this.hostingAccounts,
    required this.subscriptions,
    required this.addons,
    required this.invoices,
    required this.quotations,
    required this.payments,
    required this.communicationLogs,
    this.resellerExpiresAt,
    this.clientSince,
    this.adminNotes,
  });

  final StaffClient client;
  final ClientSummary summary;
  final double creditBalance;

  /// Derived live from an active Reseller Membership subscription, never a
  /// stored flag — non-payment revokes it on its own.
  final bool isReseller;
  final DateTime? resellerExpiresAt;

  final String clientStatus;
  final DateTime? clientSince;

  /// Staff-only notes, never shown to the client.
  final String? adminNotes;

  final List<ClientBillingBucket> billingBreakdown;
  final List<ClientContact> contacts;
  final List<ClientDomainRow> domains;
  final List<ClientTicketRow> tickets;
  final List<ClientHostingRow> hostingAccounts;
  final List<ClientSubscriptionRow> subscriptions;
  final List<ClientAddonRow> addons;
  final List<ClientInvoiceRow> invoices;
  final List<ClientQuotationRow> quotations;
  final List<ClientPaymentRow> payments;
  final List<ClientCommunication> communicationLogs;

  /// The invoices this client still owes something on — what an "apply
  /// credit" picker offers.
  List<ClientInvoiceRow> get unpaidInvoices =>
      invoices.where((i) => i.balanceDue > 0.005 && !i.isVoid).toList();

  factory ClientProfile.fromJson(Map<String, dynamic> json) {
    final breakdown = json.object('billing_breakdown') ?? const {};
    return ClientProfile(
      client: StaffClient.fromJson(json.object('client') ?? const {}),
      summary: ClientSummary.fromJson(json.object('summary') ?? const {}),
      creditBalance: json.money('credit_balance'),
      isReseller: json.flag('is_reseller'),
      resellerExpiresAt: json
          .object('reseller_membership')
          ?.date('expire_date'),
      clientStatus: json.strOr('client_status', 'active'),
      clientSince: json.date('client_since'),
      adminNotes: json.str('admin_notes'),
      billingBreakdown: [
        for (final entry in breakdown.entries)
          if (entry.value is Map)
            ClientBillingBucket.fromJson(
              entry.key,
              Map<String, dynamic>.from(entry.value as Map),
            ),
      ],
      contacts: json.list('contacts', ClientContact.fromJson),
      domains: json.list('domains', ClientDomainRow.fromJson),
      tickets: json.list('tickets', ClientTicketRow.fromJson),
      hostingAccounts: json.list('hosting_accounts', ClientHostingRow.fromJson),
      subscriptions: json.list('subscriptions', ClientSubscriptionRow.fromJson),
      addons: json.list('addons', ClientAddonRow.fromJson),
      invoices: json.list('invoices', ClientInvoiceRow.fromJson),
      quotations: json.list('quotations', ClientQuotationRow.fromJson),
      payments: json.list('payments', ClientPaymentRow.fromJson),
      communicationLogs: json.list(
        'communication_logs',
        ClientCommunication.fromJson,
      ),
    );
  }
}

/// The four figures the profile header is about. Invoiced and paid describe
/// the same set of documents (live invoices only), so [balance] is their
/// difference and means something.
class ClientSummary {
  const ClientSummary({
    required this.totalInvoiced,
    required this.totalPaid,
    required this.balance,
    required this.activeSubscriptions,
    required this.totalSubscriptionValue,
  });

  final double totalInvoiced;
  final double totalPaid;

  /// Outstanding: invoiced minus paid. Negative means overpaid.
  final double balance;
  final int activeSubscriptions;
  final double totalSubscriptionValue;

  factory ClientSummary.fromJson(Map<String, dynamic> json) => ClientSummary(
    totalInvoiced: json.money('total_invoiced'),
    totalPaid: json.money('total_paid'),
    balance: json.money('balance'),
    activeSubscriptions: json.count('active_subscriptions'),
    totalSubscriptionValue: json.money('total_subscription_value'),
  );
}

/// One row of the WHMCS-style billing breakdown: how many invoices sit at a
/// status and what they add up to.
class ClientBillingBucket {
  const ClientBillingBucket({
    required this.status,
    required this.count,
    required this.total,
  });

  /// paid | sent | partial | overdue | draft | cancelled | refunded.
  final String status;
  final int count;
  final double total;

  factory ClientBillingBucket.fromJson(
    String status,
    Map<String, dynamic> json,
  ) => ClientBillingBucket(
    status: status,
    count: json.count('count'),
    total: json.money('total'),
  );
}

/// A secondary person at the client's company (`ClientContact`). Distinct
/// from a portal login, which is a credential.
class ClientContact {
  const ClientContact({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.role,
    this.notes,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;
  final String? notes;

  factory ClientContact.fromJson(Map<String, dynamic> json) => ClientContact(
    id: json.id(),
    name: json.strOr('name', '—'),
    email: json.str('email'),
    phone: json.str('phone'),
    role: json.str('role'),
    notes: json.str('notes'),
  );
}

class ClientDomainRow {
  const ClientDomainRow({
    required this.id,
    required this.name,
    required this.autoRenew,
    this.registrar,
    this.registeredAt,
    this.expiresAt,
    this.status,
  });

  final String id;
  final String name;
  final bool autoRenew;
  final String? registrar;
  final DateTime? registeredAt;
  final DateTime? expiresAt;
  final String? status;

  factory ClientDomainRow.fromJson(Map<String, dynamic> json) =>
      ClientDomainRow(
        id: json.id(),
        name: json.strOr('name', '—'),
        autoRenew: json.flag('auto_renew'),
        registrar: json.str('registrar'),
        registeredAt: json.date('registered_at'),
        expiresAt: json.date('expires_at'),
        status: json.str('status'),
      );
}

class ClientTicketRow {
  const ClientTicketRow({
    required this.id,
    required this.subject,
    this.ticketNumber,
    this.status,
    this.lastReplyAt,
  });

  final String id;
  final String subject;
  final String? ticketNumber;
  final String? status;
  final DateTime? lastReplyAt;

  factory ClientTicketRow.fromJson(Map<String, dynamic> json) =>
      ClientTicketRow(
        id: json.id(),
        subject: json.strOr('subject', '—'),
        ticketNumber: json.str('ticket_number'),
        status: json.str('status'),
        lastReplyAt: json.date('last_reply_at'),
      );
}

class ClientHostingRow {
  const ClientHostingRow({
    required this.id,
    this.domain,
    this.cpanelUsername,
    this.status,
  });

  final String id;
  final String? domain;
  final String? cpanelUsername;
  final String? status;

  factory ClientHostingRow.fromJson(Map<String, dynamic> json) =>
      ClientHostingRow(
        id: json.id(),
        domain: json.str('domain'),
        cpanelUsername: json.str('cpanel_username'),
        status: json.str('status'),
      );
}

/// One of the client's subscriptions, with the next bill date the profile
/// endpoint computes by walking the billing cycle forward.
class ClientSubscriptionRow {
  const ClientSubscriptionRow({
    required this.id,
    required this.productServiceName,
    required this.quantity,
    required this.price,
    required this.status,
    this.label,
    this.billingCycle,
    this.startDate,
    this.nextBill,
  });

  final String id;
  final String productServiceName;

  /// The domain or instance this subscription is for.
  final String? label;
  final String? billingCycle;
  final int quantity;
  final double price;
  final String status;
  final DateTime? startDate;

  /// Only computed for active subscriptions on a known cycle.
  final DateTime? nextBill;

  double get value => price * quantity;

  factory ClientSubscriptionRow.fromJson(Map<String, dynamic> json) =>
      ClientSubscriptionRow(
        id: json.id(),
        productServiceName: json.strOr('product_service_name', '—'),
        label: json.str('label'),
        billingCycle: json.str('billing_cycle'),
        quantity: json.count('quantity', fallback: 1),
        price: json.money('price'),
        status: json.strOr('status', 'pending'),
        startDate: json.date('start_date'),
        nextBill: json.date('next_bill'),
      );
}

class ClientAddonRow {
  const ClientAddonRow({
    required this.id,
    required this.name,
    required this.price,
    this.billingCycle,
    this.startDate,
    this.status,
  });

  final String id;
  final String name;
  final double price;
  final String? billingCycle;
  final DateTime? startDate;
  final String? status;

  factory ClientAddonRow.fromJson(Map<String, dynamic> json) => ClientAddonRow(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    billingCycle: json.str('billing_cycle'),
    startDate: json.date('start_date'),
    status: json.str('status'),
  );
}

/// An invoice as the profile endpoint shapes it — late fees split out of the
/// total, and the paid/outstanding split already computed.
class ClientInvoiceRow {
  const ClientInvoiceRow({
    required this.id,
    required this.documentNumber,
    required this.subtotal,
    required this.lateFee,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    required this.status,
    this.description,
    this.date,
    this.dueDate,
  });

  final String id;
  final String documentNumber;
  final String? description;
  final DateTime? date;
  final DateTime? dueDate;

  /// [total] less [lateFee].
  final double subtotal;
  final double lateFee;
  final double total;
  final double paidAmount;
  final double balanceDue;
  final String status;

  /// Nothing can be collected against these, so they stay out of an
  /// apply-credit picker.
  bool get isVoid => status == 'cancelled' || status == 'draft';

  factory ClientInvoiceRow.fromJson(Map<String, dynamic> json) =>
      ClientInvoiceRow(
        id: json.id(),
        documentNumber: json.strOr('document_number', '—'),
        description: json.str('description'),
        date: json.date('date'),
        dueDate: json.date('due_date'),
        subtotal: json.money('subtotal'),
        lateFee: json.money('late_fee'),
        total: json.money('total'),
        paidAmount: json.money('paid_amount'),
        balanceDue: json.money('balance_due'),
        status: json.strOr('status', 'draft'),
      );
}

class ClientQuotationRow {
  const ClientQuotationRow({
    required this.id,
    required this.documentNumber,
    required this.total,
    required this.status,
    this.subject,
    this.date,
    this.validUntil,
  });

  final String id;
  final String documentNumber;
  final String? subject;
  final DateTime? date;
  final DateTime? validUntil;
  final double total;
  final String status;

  factory ClientQuotationRow.fromJson(Map<String, dynamic> json) =>
      ClientQuotationRow(
        id: json.id(),
        documentNumber: json.strOr('document_number', '—'),
        subject: json.str('subject'),
        date: json.date('date'),
        validUntil: json.date('valid_until'),
        total: json.money('total'),
        status: json.strOr('status', 'draft'),
      );
}

class ClientPaymentRow {
  const ClientPaymentRow({
    required this.id,
    required this.amount,
    this.paymentDate,
    this.paymentMethod,
    this.reference,
    this.documentNumber,
  });

  final String id;
  final double amount;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? reference;
  final String? documentNumber;

  factory ClientPaymentRow.fromJson(Map<String, dynamic> json) =>
      ClientPaymentRow(
        id: json.id(),
        amount: json.money('amount'),
        paymentDate: json.date('payment_date'),
        paymentMethod: json.str('payment_method'),
        reference: json.str('reference'),
        documentNumber: json.str('document_number'),
      );
}

/// One entry in the communication log — an email, SMS or WhatsApp the system
/// sent this client, with whether it actually went out.
class ClientCommunication {
  const ClientCommunication({
    required this.id,
    required this.channel,
    this.type,
    this.recipient,
    this.subject,
    this.message,
    this.status,
    this.error,
    this.sentAt,
  });

  final String id;

  /// email | sms | whatsapp.
  final String channel;

  /// What it was about — `invoice_sent`, `welcome`, and so on.
  final String? type;
  final String? recipient;
  final String? subject;
  final String? message;

  /// sent | failed | pending.
  final String? status;
  final String? error;
  final DateTime? sentAt;

  bool get failed => status == 'failed';

  factory ClientCommunication.fromJson(Map<String, dynamic> json) =>
      ClientCommunication(
        id: json.id(),
        channel: json.strOr('channel', 'email'),
        type: json.str('type'),
        recipient: json.str('recipient'),
        subject: json.str('subject'),
        message: json.str('message'),
        status: json.str('status'),
        error: json.str('error'),
        sentAt: json.date('created_at'),
      );
}

// ---------------------------------------------------------------------------
// Wallet — GET /clients/{client}/credit
// ---------------------------------------------------------------------------

/// A client's credit balance with the last 50 ledger movements.
class ClientCreditLedger {
  const ClientCreditLedger({required this.balance, required this.entries});

  final double balance;
  final List<ClientCreditEntry> entries;

  factory ClientCreditLedger.fromJson(Map<String, dynamic> json) =>
      ClientCreditLedger(
        balance: json.money('balance'),
        entries: json.list('ledger', ClientCreditEntry.fromJson),
      );
}

class ClientCreditEntry {
  const ClientCreditEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.notes,
    this.createdAt,
  });

  final String id;

  /// `topup`, `adjustment`, `applied`, `refund` — pending top-ups are
  /// filtered out server-side.
  final String type;

  /// Signed: negative when credit left the wallet.
  final double amount;
  final double balanceAfter;
  final String? notes;
  final DateTime? createdAt;

  factory ClientCreditEntry.fromJson(Map<String, dynamic> json) =>
      ClientCreditEntry(
        id: json.id(),
        type: json.strOr('type', 'adjustment'),
        amount: json.money('amount'),
        balanceAfter: json.money('balance_after'),
        notes: json.str('notes'),
        createdAt: json.date('created_at'),
      );
}

/// What `POST /clients/{client}/merge` answers with — [movedCounts] is a
/// table-name → row-count map of everything reassigned to [survivorId],
/// meant to be shown as a confirmation summary before the merge runs, not
/// just a report of what already happened.
class ClientMergeResult {
  const ClientMergeResult({
    required this.survivorId,
    required this.movedCounts,
    this.message,
  });

  final String survivorId;
  final Map<String, int> movedCounts;
  final String? message;

  int get totalMoved => movedCounts.values.fold(0, (a, b) => a + b);

  factory ClientMergeResult.fromJson(Map<String, dynamic> json) {
    final moved = json.object('moved') ?? const {};
    return ClientMergeResult(
      survivorId: json.str('survivor_id') ?? '',
      movedCounts: {
        for (final entry in moved.entries) entry.key: readInt(entry.value),
      },
      message: json.str('message'),
    );
  }
}

/// A payment row (`PaymentInController::index`): raw model with relations.
class StaffPayment {
  const StaffPayment({
    required this.id,
    required this.amount,
    this.paymentDate,
    this.paymentMethod,
    this.reference,
    this.clientName,
    this.documentNumber,
    this.documentId,
  });

  final String id;
  final double amount;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? reference;
  final String? clientName;
  final String? documentNumber;
  final String? documentId;

  factory StaffPayment.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final document = json.object('document');
    return StaffPayment(
      id: json.id(),
      amount: json.money('amount'),
      paymentDate: json.date('payment_date'),
      paymentMethod: json.str('payment_method'),
      reference: json.str('reference'),
      clientName:
          client?.str('name') ?? document?.object('client')?.str('name'),
      documentNumber: document?.str('document_number'),
      documentId: json.str('document_id'),
    );
  }
}

/// A staff-side ticket (`TicketController::format`) — same thread shape as
/// the portal but with the client and assignee attached.
class StaffTicket {
  const StaffTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.priority,
    required this.replies,
    this.ticketNumber,
    this.clientName,
    this.clientId,
    this.assigneeName,
    this.repliesCount,
    this.lastReplyAt,
    this.createdAt,
  });

  final String id;
  final String subject;
  final String status;
  final String priority;
  final List<TicketReply> replies;
  final String? ticketNumber;
  final String? clientName;
  final String? clientId;
  final String? assigneeName;
  final int? repliesCount;
  final DateTime? lastReplyAt;
  final DateTime? createdAt;

  bool get isClosed => status == 'closed';

  factory StaffTicket.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final assignee = json.object('assignee');
    return StaffTicket(
      id: json.id(),
      subject: json.strOr('subject', '—'),
      status: json.strOr('status', 'open'),
      priority: json.strOr('priority', 'medium'),
      replies: json.list('replies', TicketReply.fromJson),
      ticketNumber: json.str('ticket_number'),
      clientName: client?.str('name'),
      clientId: client?.str('id'),
      assigneeName: assignee?.str('name'),
      repliesCount: json['replies_count'] == null
          ? null
          : json.count('replies_count'),
      lastReplyAt: json.date('last_reply_at'),
      createdAt: json.date('created_at'),
    );
  }
}
