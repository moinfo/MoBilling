/// Models for the client-portal endpoints, hand-written against the actual
/// controller output (no API Resources exist to generate from — the portal
/// controllers build arrays inline, so codegen has nothing to read).
///
/// Field-type notes worth keeping in mind throughout:
///   * `decimal:2` model casts (total, amount, subtotal…) serialise as
///     STRINGS: `"1500.00"`.
///   * Hand-cast fields (`(float) $doc->total`) serialise as numbers.
///   * Uncast `->sum()` results (dashboard `total_invoiced`, `total_paid`)
///     are strings; `total_balance` — PHP arithmetic on them — is a number.
/// All parsing goes through the tolerant readers in `json.dart` for this
/// reason. See `PortalDashboardController` / `PortalDocumentController`.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Dashboard — GET /portal/dashboard  (PortalDashboardController::summary)
// ---------------------------------------------------------------------------

class PortalDashboard {
  const PortalDashboard({
    required this.creditBalance,
    required this.servicesCount,
    required this.domainsCount,
    required this.ticketsCount,
    required this.unpaidInvoicesCount,
    required this.expiringDomainsCount,
    required this.overdueCount,
    required this.totalInvoiced,
    required this.totalPaid,
    required this.totalBalance,
    required this.clientInfo,
    required this.recentServices,
    required this.contacts,
    required this.recentTickets,
    required this.announcements,
    required this.recentInvoices,
    required this.recentPayments,
    required this.upcomingSubscriptions,
  });

  final double creditBalance;
  final int servicesCount;
  final int domainsCount;
  final int ticketsCount;
  final int unpaidInvoicesCount;
  final int expiringDomainsCount;
  final int overdueCount;
  final double totalInvoiced;
  final double totalPaid;
  final double totalBalance;
  final ClientInfo? clientInfo;
  final List<RecentService> recentServices;
  final List<PortalContact> contacts;
  final List<RecentTicket> recentTickets;
  final List<AnnouncementSummary> announcements;
  final List<InvoiceSummary> recentInvoices;
  final List<PaymentSummary> recentPayments;
  final List<UpcomingSubscription> upcomingSubscriptions;

  factory PortalDashboard.fromJson(Map<String, dynamic> json) {
    final client = json.object('client_info');
    return PortalDashboard(
      creditBalance: json.money('credit_balance'),
      servicesCount: json.count('services_count'),
      domainsCount: json.count('domains_count'),
      ticketsCount: json.count('tickets_count'),
      unpaidInvoicesCount: json.count('unpaid_invoices_count'),
      expiringDomainsCount: json.count('expiring_domains_count'),
      overdueCount: json.count('overdue_count'),
      totalInvoiced: json.money('total_invoiced'),
      totalPaid: json.money('total_paid'),
      totalBalance: json.money('total_balance'),
      clientInfo: client == null ? null : ClientInfo.fromJson(client),
      recentServices: json.list('recent_services', RecentService.fromJson),
      contacts: json.list('contacts', PortalContact.fromJson),
      recentTickets: json.list('recent_tickets', RecentTicket.fromJson),
      announcements: json.list('announcements', AnnouncementSummary.fromJson),
      recentInvoices: json.list('recent_invoices', InvoiceSummary.fromJson),
      recentPayments: json.list('recent_payments', PaymentSummary.fromJson),
      upcomingSubscriptions: json.list(
        'upcoming_subscriptions',
        UpcomingSubscription.fromJson,
      ),
    );
  }
}

class ClientInfo {
  const ClientInfo({
    this.company,
    this.contact,
    this.address,
    this.email,
    this.phone,
  });

  final String? company;
  final String? contact;
  final String? address;
  final String? email;
  final String? phone;

  factory ClientInfo.fromJson(Map<String, dynamic> json) => ClientInfo(
    company: json.str('company'),
    contact: json.str('contact'),
    address: json.str('address'),
    email: json.str('email'),
    phone: json.str('phone'),
  );
}

class RecentService {
  const RecentService({
    required this.id,
    required this.status,
    this.product,
    this.label,
    this.hostingAccountId,
  });

  final String id;
  final String status;
  final String? product;
  final String? label;
  final String? hostingAccountId;

  factory RecentService.fromJson(Map<String, dynamic> json) => RecentService(
    id: json.id(),
    status: json.strOr('status', 'unknown'),
    product: json.str('product'),
    label: json.str('label'),
    hostingAccountId: json.str('hosting_account_id'),
  );
}

class PortalContact {
  const PortalContact({
    required this.id,
    required this.name,
    this.email,
    this.role,
  });

  final String id;
  final String name;
  final String? email;
  final String? role;

  factory PortalContact.fromJson(Map<String, dynamic> json) => PortalContact(
    id: json.id(),
    name: json.strOr('name', '—'),
    email: json.str('email'),
    role: json.str('role'),
  );
}

class RecentTicket {
  const RecentTicket({
    required this.id,
    required this.subject,
    required this.status,
    this.ticketNumber,
    this.lastReplyAt,
  });

  final String id;
  final String subject;
  final String status;
  final String? ticketNumber;
  final DateTime? lastReplyAt;

  factory RecentTicket.fromJson(Map<String, dynamic> json) => RecentTicket(
    id: json.id(),
    subject: json.strOr('subject', '—'),
    status: json.strOr('status', 'open'),
    ticketNumber: json.str('ticket_number'),
    lastReplyAt: json.date('last_reply_at'),
  );
}

class AnnouncementSummary {
  const AnnouncementSummary({
    required this.id,
    required this.title,
    this.excerpt,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String? excerpt;
  final DateTime? publishedAt;

  factory AnnouncementSummary.fromJson(Map<String, dynamic> json) =>
      AnnouncementSummary(
        id: json.id(),
        title: json.strOr('title', '—'),
        excerpt: json.str('excerpt'),
        publishedAt: json.date('published_at'),
      );
}

class UpcomingSubscription {
  const UpcomingSubscription({
    required this.id,
    required this.price,
    required this.quantity,
    this.service,
    this.label,
    this.schedule,
    this.nextInvoiceDate,
  });

  final String id;
  final double price;
  final int quantity;
  final String? service;
  final String? label;
  final String? schedule;
  final DateTime? nextInvoiceDate;

  factory UpcomingSubscription.fromJson(Map<String, dynamic> json) =>
      UpcomingSubscription(
        id: json.id(),
        price: json.money('price'),
        quantity: json.count('quantity', fallback: 1),
        service: json.str('service'),
        label: json.str('label'),
        schedule: json.str('schedule'),
        nextInvoiceDate: json.date('next_invoice_date'),
      );
}

// ---------------------------------------------------------------------------
// Invoices — GET /portal/documents  (PortalDocumentController)
// ---------------------------------------------------------------------------

/// A list-row invoice, as returned by both the dashboard's `recent_invoices`
/// (hand-built, already floats) and the paginated index (raw model with
/// appended computed fields).
class InvoiceSummary {
  const InvoiceSummary({
    required this.id,
    required this.documentNumber,
    required this.status,
    required this.total,
    required this.paid,
    required this.balance,
    this.cancellationRequested = false,
    this.description,
    this.date,
    this.dueDate,
  });

  final String id;
  final String documentNumber;
  final String status;
  final double total;
  final double paid;
  final double balance;

  /// An open billing ticket asks staff to cancel this invoice. Payment is on
  /// hold until they answer, so the row hides its pay action.
  final bool cancellationRequested;

  final String? description;
  final DateTime? date;
  final DateTime? dueDate;

  factory InvoiceSummary.fromJson(Map<String, dynamic> json) => InvoiceSummary(
    id: json.id(),
    documentNumber: json.strOr('document_number', '—'),
    status: json.strOr('status', 'sent'),
    cancellationRequested: json.flag('cancellation_requested'),
    total: json.money('total'),
    // Dashboard rows call these paid/balance; the index appends
    // paid_amount/balance_due to the raw model. Accept either spelling.
    paid: json.containsKey('paid')
        ? json.money('paid')
        : json.money('paid_amount'),
    balance: json.containsKey('balance')
        ? json.money('balance')
        : json.money('balance_due'),
    description:
        json.str('description') ??
        _firstItemDescription(json) ??
        json.str('notes'),
    date: json.date('date'),
    dueDate: json.date('due_date'),
  );

  static String? _firstItemDescription(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is List && items.isNotEmpty && items.first is Map) {
      return Map<String, dynamic>.from(items.first as Map).str('description');
    }
    return null;
  }
}

/// Full invoice detail — GET /portal/documents/{id} (`show`), which merges the
/// raw model with WHMCS-style panels (invoiced_to / pay_to) and the tenant's
/// offline payment instructions.
class PortalDocument {
  const PortalDocument({
    required this.id,
    required this.documentNumber,
    required this.type,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    required this.lateFee,
    required this.items,
    required this.payments,
    required this.paymentMethods,
    this.cancellationRequested = false,
    this.date,
    this.dueDate,
    this.notes,
    this.invoicedTo,
    this.payTo,
  });

  final String id;
  final String documentNumber;
  final String type;
  final String status;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final double balanceDue;
  final double lateFee;
  final List<DocumentItem> items;
  final List<PaymentSummary> payments;

  /// The tenant's offline payment instructions (bank / mobile money), shown on
  /// the invoice so a client can pay outside Pesapal.
  final List<OfflinePaymentMethod> paymentMethods;

  /// True while an open billing ticket asks staff to cancel this invoice.
  /// The backend refuses a second request, and the web portal puts payment on
  /// hold until the ticket is resolved — mirror both.
  final bool cancellationRequested;

  final DateTime? date;
  final DateTime? dueDate;
  final String? notes;
  final PartyPanel? invoicedTo;
  final PartyPanel? payTo;

  bool get isPayable =>
      balanceDue > 0 &&
      status != 'paid' &&
      status != 'cancelled' &&
      !cancellationRequested;

  /// Statuses `PortalDocumentController::requestCancellation` accepts. Anything
  /// else is already paid, cancelled, or still a draft.
  static const cancellableStatuses = {
    'sent',
    'overdue',
    'partial',
    'pending_approval',
  };

  /// Whether a cancellation request would be accepted — the caller must also
  /// be a portal admin, which only the session knows.
  bool get isCancellable =>
      type == 'invoice' &&
      !cancellationRequested &&
      cancellableStatuses.contains(status);

  factory PortalDocument.fromJson(Map<String, dynamic> json) {
    final invoicedTo = json.object('invoiced_to');
    final payTo = json.object('pay_to');
    return PortalDocument(
      id: json.id(),
      documentNumber: json.strOr('document_number', '—'),
      type: json.strOr('type', 'invoice'),
      status: json.strOr('status', 'sent'),
      subtotal: json.money('subtotal'),
      discountAmount: json.money('discount_amount'),
      taxAmount: json.money('tax_amount'),
      total: json.money('total'),
      paidAmount: json.money('paid_amount'),
      balanceDue: json.money('balance_due'),
      lateFee: json.money('late_fee'),
      items: json.list('items', DocumentItem.fromJson),
      payments: json.list('payments', PaymentSummary.fromJson),
      paymentMethods: json.list(
        'payment_methods',
        OfflinePaymentMethod.fromJson,
      ),
      cancellationRequested: json.flag('cancellation_requested'),
      date: json.date('date'),
      dueDate: json.date('due_date'),
      notes: json.str('notes'),
      invoicedTo: invoicedTo == null ? null : PartyPanel.fromJson(invoicedTo),
      payTo: payTo == null ? null : PartyPanel.fromJson(payTo),
    );
  }
}

class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.price,
    required this.total,
    this.serviceFrom,
    this.serviceTo,
  });

  final String id;
  final String description;
  final double quantity;
  final double price;
  final double total;
  final DateTime? serviceFrom;
  final DateTime? serviceTo;

  factory DocumentItem.fromJson(Map<String, dynamic> json) => DocumentItem(
    id: json.id(),
    description: json.strOr('description', '—'),
    quantity: json.money('quantity', fallback: 1),
    price: json.money('price'),
    total: json.money('total'),
    serviceFrom: json.date('service_from'),
    serviceTo: json.date('service_to'),
  );
}

/// The invoiced_to / pay_to blocks on the invoice view.
class PartyPanel {
  const PartyPanel({
    this.name,
    this.address,
    this.email,
    this.phone,
    this.taxId,
  });

  final String? name;
  final String? address;
  final String? email;
  final String? phone;
  final String? taxId;

  factory PartyPanel.fromJson(Map<String, dynamic> json) => PartyPanel(
    name: json.str('name'),
    address: json.str('address'),
    email: json.str('email'),
    phone: json.str('phone'),
    taxId: json.str('tax_id'),
  );
}

/// One entry of `tenants.payment_methods` — free-form label + instructions.
class OfflinePaymentMethod {
  const OfflinePaymentMethod({this.name, this.details});

  final String? name;
  final String? details;

  factory OfflinePaymentMethod.fromJson(Map<String, dynamic> json) =>
      OfflinePaymentMethod(
        name: json.str('name') ?? json.str('label') ?? json.str('method'),
        details: json.str('details'),
      );
}

// ---------------------------------------------------------------------------
// Payments — GET /portal/payments  (PortalPaymentController::index)
// ---------------------------------------------------------------------------

/// A payment row. Serves both the paginated index (raw PaymentIn model, amount
/// as a decimal string, nested document) and the dashboard's hand-built rows
/// (flat document_number, amount as a number).
class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.amount,
    this.paymentDate,
    this.paymentMethod,
    this.reference,
    this.documentNumber,
    this.documentId,
  });

  final String id;
  final double amount;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? reference;
  final String? documentNumber;
  final String? documentId;

  factory PaymentSummary.fromJson(Map<String, dynamic> json) {
    final document = json.object('document');
    return PaymentSummary(
      id: json.id(),
      amount: json.money('amount'),
      paymentDate: json.date('payment_date'),
      paymentMethod: json.str('payment_method'),
      reference: json.str('reference'),
      documentNumber:
          json.str('document_number') ?? document?.str('document_number'),
      documentId: json.str('document_id') ?? document?.str('id'),
    );
  }
}

// ---------------------------------------------------------------------------
// Online payment — POST /portal/documents/{id}/pay
// (InvoicePaymentController::checkout / ::status, shared with the public
//  pay-by-link page; the portal variant just adds auth.)
// ---------------------------------------------------------------------------

/// A freshly initiated Pesapal checkout.
///
/// The actual card/M-Pesa entry happens on Pesapal's hosted page at
/// [redirectUrl]; the app's job is to open it and then watch
/// [InvoicePaymentStatus] until the IPN webhook settles the payment
/// server-side. [redirectUrl] can be null if Pesapal declined the order.
class CheckoutSession {
  const CheckoutSession({
    required this.paymentId,
    this.redirectUrl,
    this.orderTrackingId,
  });

  final String paymentId;
  final String? redirectUrl;
  final String? orderTrackingId;

  factory CheckoutSession.fromJson(Map<String, dynamic> json) =>
      CheckoutSession(
        paymentId: json.id('payment_id'),
        redirectUrl: json.str('redirect_url'),
        orderTrackingId: json.str('order_tracking_id'),
      );
}

/// Poll result for a Pesapal payment. The webhook writes exactly three
/// states: 'pending' → 'completed' | 'failed'.
class InvoicePaymentStatus {
  const InvoicePaymentStatus({
    required this.status,
    required this.amount,
    this.confirmationCode,
    this.paymentMethod,
    this.completedAt,
  });

  final String status;
  final double amount;
  final String? confirmationCode;
  final String? paymentMethod;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isSettled => isCompleted || isFailed;

  factory InvoicePaymentStatus.fromJson(Map<String, dynamic> json) =>
      InvoicePaymentStatus(
        status: json.strOr('status', 'pending'),
        amount: json.money('amount'),
        confirmationCode: json.str('confirmation_code'),
        paymentMethod: json.str('payment_method'),
        completedAt: json.date('completed_at'),
      );
}

// ---------------------------------------------------------------------------
// Statement — GET /portal/statement  (PortalStatementController::index)
// ---------------------------------------------------------------------------

class Statement {
  const Statement({
    required this.entries,
    required this.totalDebits,
    required this.totalCredits,
    required this.closingBalance,
  });

  final List<StatementEntry> entries;
  final double totalDebits;
  final double totalCredits;
  final double closingBalance;

  factory Statement.fromJson(Map<String, dynamic> json) => Statement(
    entries: json.list('entries', StatementEntry.fromJson),
    totalDebits: json.money('total_debits'),
    totalCredits: json.money('total_credits'),
    closingBalance: json.money('closing_balance'),
  );
}

class StatementEntry {
  const StatementEntry({
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.date,
    this.reference,
  });

  /// 'invoice' or 'payment'.
  final String type;
  final String description;
  final double debit;
  final double credit;

  /// Running balance, computed server-side in date order.
  final double balance;
  final DateTime? date;
  final String? reference;

  bool get isPayment => type == 'payment';

  factory StatementEntry.fromJson(Map<String, dynamic> json) => StatementEntry(
    type: json.strOr('type', 'invoice'),
    description: json.strOr('description', '—'),
    debit: json.money('debit'),
    credit: json.money('credit'),
    balance: json.money('balance'),
    date: json.date('date'),
    reference: json.str('reference'),
  );
}
