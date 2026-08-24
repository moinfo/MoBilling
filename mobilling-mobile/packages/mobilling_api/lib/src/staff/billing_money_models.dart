/// Models for the staff app's money-movement screens: recording payments in,
/// paying bills out, and the upcoming recurring-billing schedule.
///
/// Three separate serialisation styles meet here, so the tolerant readers in
/// `json.dart` are doing real work:
///
///   * `DocumentResource` / `BillResource` / `PaymentOutResource` are API
///     Resources over `decimal:2` casts — every money field is a STRING
///     (`"1500.00"`), including the computed `balance_due`.
///   * `NextBillController::index` hand-builds its rows inside a `->map()`, so
///     `price` comes straight off the model (string) while `is_overdue` is a
///     real bool and `quantity` an int.
///   * `SettingsController::getPaymentMethods` returns a bare tenant JSON
///     column, whose shape is only guaranteed by the update validator.
library;

import '../json.dart';

/// One entry from the tenant's configured payment methods
/// (`GET /settings/payment-methods`).
///
/// The `value` is what `StorePaymentInRequest`/`StorePaymentOutRequest` accept
/// via `Rule::in(...)` — sending a label instead of a value is a 422, so the
/// dropdown must post [value] and only display [label].
class TenantPaymentMethod {
  const TenantPaymentMethod({
    required this.value,
    required this.label,
    this.details = const [],
  });

  final String value;
  final String label;

  /// Free-form key/value pairs the tenant shows on invoices (bank name, paybill
  /// number...). Blank values are dropped, matching the web's `usePaymentMethods`.
  final List<PaymentMethodDetail> details;

  factory TenantPaymentMethod.fromJson(Map<String, dynamic> json) {
    final value = json.strOr('value', '');
    return TenantPaymentMethod(
      value: value,
      label: json.str('label') ?? _titleCase(value),
      details: json
          .list('details', PaymentMethodDetail.fromJson)
          .where((d) => d.value.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Mirrors `SettingsController::DEFAULT_PAYMENT_METHODS`, used when the tenant
  /// has never saved the setting or when the request 403s — the create forms
  /// must stay usable either way, and these are the values the backend's own
  /// fallback `Rule::in` accepts.
  static const List<TenantPaymentMethod> defaults = [
    TenantPaymentMethod(value: 'bank', label: 'Bank Transfer'),
    TenantPaymentMethod(value: 'mpesa', label: 'M-Pesa'),
    TenantPaymentMethod(value: 'cash', label: 'Cash'),
    TenantPaymentMethod(value: 'card', label: 'Card'),
    TenantPaymentMethod(value: 'other', label: 'Other'),
  ];

  static String _titleCase(String value) {
    if (value.isEmpty) return 'Unknown';
    final words = value.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }
}

class PaymentMethodDetail {
  const PaymentMethodDetail({required this.key, required this.value});

  final String key;
  final String value;

  factory PaymentMethodDetail.fromJson(Map<String, dynamic> json) =>
      PaymentMethodDetail(
        key: json.strOr('key', ''),
        value: json.strOr('value', '').trim(),
      );
}

/// An invoice a payment can be recorded against (`DocumentController::index`
/// with `status=sent`, which expands server-side to sent + overdue + partial).
///
/// [balanceDue] is the `balance_due` accessor (`total - paid_amount`, itself net
/// of refunds), so it is the correct prefill for the amount field.
class UnpaidInvoice {
  const UnpaidInvoice({
    required this.id,
    required this.documentNumber,
    required this.status,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    this.clientId,
    this.clientName,
    this.date,
    this.dueDate,
  });

  final String id;
  final String documentNumber;
  final String status;
  final double total;
  final double paidAmount;
  final double balanceDue;

  /// `PaymentIn` requires a `client_id`, and the invoice is where the staff app
  /// gets it — hence carrying it on the row rather than re-fetching the client.
  final String? clientId;
  final String? clientName;
  final DateTime? date;
  final DateTime? dueDate;

  bool get isPartlyPaid => paidAmount > 0;

  factory UnpaidInvoice.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final total = json.money('total');
    final paid = json.money('paid_amount');
    return UnpaidInvoice(
      id: json.id(),
      documentNumber: json.strOr('document_number', '—'),
      status: json.strOr('status', 'sent'),
      total: total,
      paidAmount: paid,
      // Prefer the server's accessor; fall back to the arithmetic for the few
      // endpoints that omit it.
      balanceDue: json['balance_due'] == null
          ? total - paid
          : json.money('balance_due'),
      clientId: json.str('client_id') ?? client?.str('id'),
      clientName: client?.str('name') ?? json.str('client_name'),
      date: json.date('date'),
      dueDate: json.date('due_date'),
    );
  }
}

/// A payment received (`PaymentInResource`).
///
/// Carries [clientId] deliberately: `PUT /payments-in/{id}` re-validates with
/// `StorePaymentInRequest`, which requires `client_id` — so an edit cannot be
/// built from a row that only knows the client's *name*. The index resource
/// includes it, which is why the staff payment list reads through this model
/// rather than the leaner dashboard one.
class StaffPaymentIn {
  const StaffPaymentIn({
    required this.id,
    required this.amount,
    this.clientId,
    this.documentId,
    this.paymentDate,
    this.paymentMethod,
    this.reference,
    this.notes,
    this.attachmentUrl,
    this.clientName,
    this.documentNumber,
    this.documentTotal,
    this.receivedByName,
  });

  final String id;
  final double amount;
  final String? clientId;
  final String? documentId;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? reference;
  final String? notes;

  /// The proof-of-payment file attached when the payment was recorded on the
  /// web (`attachment_path`); the app has no upload for it yet.
  final String? attachmentUrl;
  final String? clientName;
  final String? documentNumber;
  final double? documentTotal;

  /// Who logged it — `received_by`, present when the index eager-loads it.
  final String? receivedByName;

  /// Only a payment against an invoice has a receipt to email: `resendReceipt`
  /// 422s on a standalone payment because it reads the client off the document.
  bool get hasInvoice => documentId != null && documentId!.isNotEmpty;

  /// The name `PaymentInController::downloadReceipt` gives the PDF, rebuilt
  /// here so the shared file carries the receipt number staff will quote.
  String get receiptFileName {
    final date = paymentDate;
    final stamp = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}'
              '${date.month.toString().padLeft(2, '0')}'
              '${date.day.toString().padLeft(2, '0')}';
    final suffix = (id.length >= 6 ? id.substring(0, 6) : id).toUpperCase();
    return 'RCT-$stamp-$suffix.pdf';
  }

  factory StaffPaymentIn.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final document = json.object('document');
    final receiver = json.object('received_by');
    return StaffPaymentIn(
      id: json.id(),
      amount: json.money('amount'),
      clientId: json.str('client_id'),
      documentId: json.str('document_id'),
      paymentDate: json.date('payment_date'),
      paymentMethod: json.str('payment_method'),
      reference: json.str('reference'),
      notes: json.str('notes'),
      attachmentUrl: json.str('attachment_url'),
      clientName:
          client?.str('name') ?? document?.object('client')?.str('name'),
      documentNumber: document?.str('document_number'),
      documentTotal: document == null || document['total'] == null
          ? null
          : document.money('total'),
      receivedByName: receiver?.str('name'),
    );
  }
}

/// A statutory/operating bill (`BillController::index` → `BillResource`).
///
/// The index eager-loads `payments`, so [paidTotal] and [remaining] are exact
/// without a second request — and they matter, because
/// `StorePaymentOutRequest::withValidator` rejects any amount above the
/// remaining balance and any bill that is already settled.
class StaffBill {
  const StaffBill({
    required this.id,
    required this.name,
    required this.amount,
    required this.paidTotal,
    required this.isOverdue,
    required this.isActive,
    this.category,
    this.categoryName,
    this.cycle,
    this.issueDate,
    this.dueDate,
    this.paidAt,
    this.notes,
  });

  final String id;
  final String name;
  final double amount;

  /// Sum of the bill's payments-out.
  final double paidTotal;
  final bool isOverdue;
  final bool isActive;
  final String? category;
  final String? categoryName;
  final String? cycle;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String? notes;

  bool get isPaid => paidAt != null;

  /// What a new payment-out may be worth, at most.
  double get remaining {
    final left = amount - paidTotal;
    return left <= 0 ? 0 : left;
  }

  /// Status word in the same vocabulary [StatusChip] understands.
  String get status {
    if (isPaid) return 'paid';
    if (isOverdue) return 'overdue';
    if (paidTotal > 0) return 'partial';
    return 'pending';
  }

  factory StaffBill.fromJson(Map<String, dynamic> json) {
    final category = json.object('bill_category');
    final payments = json.list('payments', StaffPaymentOut.fromJson);
    return StaffBill(
      id: json.id(),
      name: json.strOr('name', '—'),
      amount: json.money('amount'),
      paidTotal: payments.fold<double>(0, (sum, p) => sum + p.amount),
      isOverdue: json.flag('is_overdue'),
      isActive: json.flag('is_active', fallback: true),
      category: json.str('category'),
      categoryName: category == null
          ? null
          : [
              category.str('parent_name'),
              category.str('name'),
            ].whereType<String>().join(' › '),
      cycle: json.str('cycle'),
      issueDate: json.date('issue_date'),
      dueDate: json.date('due_date'),
      paidAt: json.date('paid_at'),
      notes: json.str('notes'),
    );
  }
}

/// A payment made against a bill (`PaymentOutResource`).
class StaffPaymentOut {
  const StaffPaymentOut({
    required this.id,
    required this.amount,
    this.billId,
    this.paymentDate,
    this.paymentMethod,
    this.controlNumber,
    this.reference,
    this.notes,
    this.receiptUrl,
    this.billName,
    this.billAmount,
    this.billDueDate,
  });

  final String id;
  final double amount;
  final String? billId;
  final DateTime? paymentDate;
  final String? paymentMethod;

  /// The government control number for statutory payments (TRA/NSSF style).
  final String? controlNumber;
  final String? reference;
  final String? notes;
  final String? receiptUrl;
  final String? billName;
  final double? billAmount;
  final DateTime? billDueDate;

  factory StaffPaymentOut.fromJson(Map<String, dynamic> json) {
    // `bill` is `new BillResource($this->whenLoaded('bill'))`, which serialises
    // as `{}` when the relation was not loaded — `object()` treats that as null.
    final bill = json.object('bill');
    return StaffPaymentOut(
      id: json.id(),
      amount: json.money('amount'),
      billId: json.str('bill_id') ?? bill?.str('id'),
      paymentDate: json.date('payment_date'),
      paymentMethod: json.str('payment_method'),
      controlNumber: json.str('control_number'),
      reference: json.str('reference'),
      notes: json.str('notes'),
      receiptUrl: json.str('receipt_url'),
      billName: bill?.str('name'),
      billAmount: bill == null || bill['amount'] == null
          ? null
          : bill.money('amount'),
      billDueDate: bill?.date('due_date'),
    );
  }
}

/// An upcoming recurring charge (`NextBillController::index`).
///
/// Not a persisted record — the controller projects active subscriptions whose
/// product has a repeating `billing_cycle` and computes the next due date by
/// walking the cycle forward from `start_date`, skipping dates that already have
/// a paid invoice in `recurring_invoice_logs`.
class NextBill {
  const NextBill({
    required this.subscriptionId,
    required this.clientId,
    required this.clientName,
    required this.productServiceName,
    required this.billingCycle,
    required this.price,
    required this.quantity,
    required this.isOverdue,
    this.clientEmail,
    this.productServiceId,
    this.lastBilled,
    this.nextBill,
  });

  final String subscriptionId;
  final String clientId;
  final String clientName;

  /// Product name, already suffixed with the subscription label by the server.
  final String productServiceName;
  final String billingCycle;
  final double price;
  final int quantity;

  /// True when the computed due date is in the past — i.e. the recurring job
  /// has not produced (or nobody has paid) the invoice it should have.
  final bool isOverdue;
  final String? clientEmail;
  final String? productServiceId;
  final DateTime? lastBilled;
  final DateTime? nextBill;

  /// Value of the charge when it lands. The server sends the unit price only.
  double get lineTotal => price * quantity;

  bool get hasNeverBeenBilled => lastBilled == null;

  /// Cycle wording from the web's `NextBills.tsx`, so both clients read alike.
  String get cycleLabel => switch (billingCycle) {
    'monthly' => 'Monthly',
    'quarterly' => 'Quarterly',
    'half_yearly' => 'Semi-Annual',
    'yearly' => 'Annually',
    _ => billingCycle,
  };

  factory NextBill.fromJson(Map<String, dynamic> json) => NextBill(
    subscriptionId: json.id('subscription_id'),
    clientId: json.id('client_id'),
    clientName: json.strOr('client_name', '—'),
    productServiceName: json.strOr('product_service_name', '—'),
    billingCycle: json.strOr('billing_cycle', 'monthly'),
    price: json.money('price'),
    quantity: json.count('quantity', fallback: 1),
    isOverdue: json.flag('is_overdue'),
    clientEmail: json.str('client_email'),
    productServiceId: json.str('product_service_id'),
    lastBilled: json.date('last_billed'),
    nextBill: json.date('next_bill'),
  );
}

/// Result of `ClientSubscriptionController::generateInvoice` — the only write
/// action reachable from the next-bills schedule.
class GeneratedInvoice {
  const GeneratedInvoice({
    required this.message,
    this.documentId,
    this.documentNumber,
  });

  /// Server-composed confirmation ("Invoice INV-0007 created and sent to ...").
  /// Shown verbatim: it names the invoice and the recipient, which is exactly
  /// what the person who tapped Generate needs to confirm.
  final String message;
  final String? documentId;
  final String? documentNumber;

  factory GeneratedInvoice.fromJson(Map<String, dynamic> json) {
    final data = json.object('data');
    return GeneratedInvoice(
      message: json.strOr('message', 'Invoice created.'),
      documentId: data?.str('document_id'),
      documentNumber: data?.str('document_number'),
    );
  }
}
