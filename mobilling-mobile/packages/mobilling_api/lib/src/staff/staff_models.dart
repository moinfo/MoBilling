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

  factory StaffDashboard.fromJson(Map<String, dynamic> json) => StaffDashboard(
        totalReceivable: json['total_receivable'] == null
            ? null
            : json.money('total_receivable'),
        totalReceived:
            json['total_received'] == null ? null : json.money('total_received'),
        outstanding:
            json['outstanding'] == null ? null : json.money('outstanding'),
        overdueInvoices: json['overdue_invoices'] == null
            ? null
            : json.count('overdue_invoices'),
        totalClients:
            json['total_clients'] == null ? null : json.count('total_clients'),
        totalDocuments: json['total_documents'] == null
            ? null
            : json.count('total_documents'),
        totalExpenses:
            json['total_expenses'] == null ? null : json.money('total_expenses'),
        smsBalance:
            json['sms_balance'] == null ? null : json.count('sms_balance'),
        recentInvoices: json.list('recent_invoices', StaffInvoiceRow.fromJson),
        monthlyRevenue:
            json.list('monthly_revenue', MonthlyRevenuePoint.fromJson),
        overdueBills:
            json['overdue_bills'] == null ? null : json.count('overdue_bills'),
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
        invoiceStatusBreakdown:
            json.list('invoice_status_breakdown', StatusCount.fromJson),
        paymentMethodBreakdown:
            json.list('payment_method_breakdown', MethodTotal.fromJson),
        topClients: json.list('top_clients', TopClient.fromJson),
        upcomingBills: json.list('upcoming_bills', UpcomingBill.fromJson),
        upcomingRenewals:
            json.list('upcoming_renewals', UpcomingRenewal.fromJson),
        urgentObligations:
            json.list('urgent_obligations', UrgentObligation.fromJson),
      );
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
      expiringDomains:
          json.list('expiring_domains', ExpiringDomain.fromJson),
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
        daysLeft:
            json['days_left'] == null ? null : json.count('days_left'),
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
      );
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
      clientName: client?.str('name') ?? document?.object('client')?.str('name'),
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
      repliesCount:
          json['replies_count'] == null ? null : json.count('replies_count'),
      lastReplyAt: json.date('last_reply_at'),
      createdAt: json.date('created_at'),
    );
  }
}
