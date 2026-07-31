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
    this.totalClients,
    this.totalDocuments,
    this.totalExpenses,
    this.smsBalance,
    required this.recentInvoices,
    required this.monthlyRevenue,
    required this.invoiceStatusBreakdown,
  });

  final double? totalReceivable;
  final double? totalReceived;
  final double? outstanding;
  final int? overdueInvoices;
  final int? totalClients;
  final int? totalDocuments;
  final double? totalExpenses;
  final int? smsBalance;
  final List<StaffInvoiceRow> recentInvoices;
  final List<MonthlyRevenuePoint> monthlyRevenue;
  final List<StatusCount> invoiceStatusBreakdown;

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
        invoiceStatusBreakdown:
            json.list('invoice_status_breakdown', StatusCount.fromJson),
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
