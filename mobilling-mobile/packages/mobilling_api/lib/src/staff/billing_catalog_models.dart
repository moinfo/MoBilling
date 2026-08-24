/// The billing catalog and full document detail for the staff app.
///
/// Document-type notes that matter here:
///   * `documents.type` is quotation | proforma | invoice | credit_note.
///   * Quotations and proformas come from `/documents?type=…`, but **credit
///     notes have their own endpoint** (`/credit-notes`) even though they are
///     the same table — so they get the same row model, different service call.
///   * `DocumentResource` passes `decimal:2` casts straight through, so every
///     money field arrives as a STRING while `refunds[].amount` is hand-cast
///     to a float. Tolerant parsing handles both.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Document detail — DocumentController::show (DocumentResource)
// ---------------------------------------------------------------------------

class StaffDocument {
  const StaffDocument({
    required this.id,
    required this.type,
    required this.documentNumber,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.paidAmount,
    required this.balanceDue,
    required this.reminderCount,
    required this.items,
    required this.payments,
    required this.refunds,
    required this.linkedCreditNotes,
    this.clientId,
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.date,
    this.dueDate,
    this.notes,
    this.overdueStage,
  });

  final String id;
  final String type;
  final String documentNumber;
  final String status;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final double paidAmount;
  final double balanceDue;

  /// How many overdue reminders have gone out — staff context the portal
  /// never sees.
  final int reminderCount;

  final List<StaffDocumentItem> items;
  final List<StaffDocumentPayment> payments;
  final List<StaffRefund> refunds;
  final List<LinkedCreditNote> linkedCreditNotes;
  final String? clientId;
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final DateTime? date;
  final DateTime? dueDate;
  final String? notes;

  /// Which stage of the dunning ladder this invoice has reached.
  final String? overdueStage;

  bool get isInvoice => type == 'invoice';
  bool get isCancelled => status == 'cancelled';
  bool get isDraft => status == 'draft';

  /// Only an issued, unsettled invoice can take a payment.
  bool get isPayable => isInvoice && !isCancelled && !isDraft && balanceDue > 0;

  /// Sitting in the approval queue: nothing may be sent, paid or edited until
  /// someone with `documents.approve` clears it.
  bool get isPendingApproval => status == 'pending_approval';

  /// `returnToDraft` accepts exactly these, and refuses once money is on it.
  bool get canReturnToDraft =>
      const {
        'sent',
        'overdue',
        'partial',
        'pending_approval',
      }.contains(status) &&
      payments.isEmpty;

  /// `destroy` allows only a document that never became (or is no longer) a
  /// live financial record, and never one carrying payments.
  bool get isDeletable =>
      const {'draft', 'rejected', 'cancelled'}.contains(status) &&
      payments.isEmpty;

  /// There is money on this invoice to give back.
  bool get isRefundable => isInvoice && paidAmount > 0;

  /// An issued, unsettled invoice — what `remindUnpaid` will actually chase.
  bool get isChaseable =>
      isInvoice && const {'sent', 'overdue', 'partial'}.contains(status);

  /// Quotations and proformas can be turned into an invoice.
  bool get isConvertible =>
      (type == 'quotation' || type == 'proforma') &&
      !isCancelled &&
      status != 'rejected';

  factory StaffDocument.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    return StaffDocument(
      id: json.id(),
      type: json.strOr('type', 'invoice'),
      documentNumber: json.strOr('document_number', '—'),
      status: json.strOr('status', 'draft'),
      subtotal: json.money('subtotal'),
      discountAmount: json.money('discount_amount'),
      taxAmount: json.money('tax_amount'),
      total: json.money('total'),
      paidAmount: json.money('paid_amount'),
      balanceDue: json.money('balance_due'),
      reminderCount: json.count('reminder_count'),
      items: json.list('items', StaffDocumentItem.fromJson),
      payments: json.list('payments', StaffDocumentPayment.fromJson),
      refunds: json.list('refunds', StaffRefund.fromJson),
      linkedCreditNotes: json.list(
        'linked_credit_notes',
        LinkedCreditNote.fromJson,
      ),
      clientId: json.str('client_id') ?? client?.str('id'),
      clientName: client?.str('name'),
      clientEmail: client?.str('email'),
      clientPhone: client?.str('phone'),
      date: json.date('date'),
      dueDate: json.date('due_date'),
      notes: json.str('notes'),
      overdueStage: json.str('overdue_stage'),
    );
  }
}

class StaffDocumentItem {
  const StaffDocumentItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.price,
    required this.total,
    this.unit,
    this.taxPercent,
    this.serviceFrom,
    this.serviceTo,
    this.productServiceId,
    this.itemType,
    this.discountType,
    this.discountValue,
  });

  final String id;
  final String description;
  final double quantity;
  final double price;
  final double total;
  final String? unit;
  final double? taxPercent;
  final DateTime? serviceFrom;
  final DateTime? serviceTo;

  /// The catalog row this line was seeded from, when it was.
  final String? productServiceId;

  /// 'product' or 'service' — required on the way back in, so it is read on
  /// the way out too, otherwise editing a document would have to guess.
  final String? itemType;

  /// 'percent' or 'flat'. The phone does not edit per-line discounts, but it
  /// must carry the web's back out untouched: `PUT /documents/{id}` replaces
  /// every item, so a field that is not sent is a field that is deleted.
  final String? discountType;
  final double? discountValue;

  factory StaffDocumentItem.fromJson(Map<String, dynamic> json) =>
      StaffDocumentItem(
        id: json.id(),
        description: json.strOr('description', '—'),
        quantity: json.money('quantity', fallback: 1),
        price: json.money('price'),
        total: json.money('total'),
        unit: json.str('unit'),
        taxPercent: json['tax_percent'] == null
            ? null
            : json.money('tax_percent'),
        serviceFrom: json.date('service_from'),
        serviceTo: json.date('service_to'),
        productServiceId: json.str('product_service_id'),
        itemType: json.str('item_type'),
        discountType: json.str('discount_type'),
        discountValue: json['discount_value'] == null
            ? null
            : json.money('discount_value'),
      );
}

// ---------------------------------------------------------------------------
// Raising a document — StoreDocumentRequest / StoreCreditNoteRequest
// ---------------------------------------------------------------------------

/// The four kinds of row in the `documents` table.
///
/// Only the first three are valid on `POST /documents`; a credit note is
/// raised through `POST /credit-notes` instead, which is why [isDocumentType]
/// exists rather than the caller hard-coding the set.
enum DocumentType {
  invoice('invoice', 'Invoice'),
  quotation('quotation', 'Quotation'),
  proforma('proforma', 'Proforma'),
  creditNote('credit_note', 'Credit note');

  const DocumentType(this.wire, this.label);

  /// What the API validates against.
  final String wire;

  /// What a human is shown.
  final String label;

  /// True for the three `type` values `StoreDocumentRequest` accepts.
  bool get isDocumentType => this != DocumentType.creditNote;

  /// 'a quotation', 'an invoice' — for a sentence.
  String get article => this == DocumentType.invoice ? 'an' : 'a';

  static DocumentType fromWire(String? wire) => switch (wire) {
    'quotation' => DocumentType.quotation,
    'proforma' => DocumentType.proforma,
    'credit_note' => DocumentType.creditNote,
    _ => DocumentType.invoice,
  };
}

/// One line on a document being raised or edited.
///
/// Mutable on purpose: the form edits a line in place through a sheet, and a
/// list of these *is* the draft document. Everything the API accepts is here
/// even where the phone does not offer it — a value read off an existing
/// document has to survive the round trip untouched.
class DocumentItemInput {
  DocumentItemInput({
    required this.description,
    required this.quantity,
    required this.price,
    this.itemType = 'service',
    this.productServiceId,
    this.taxPercent,
    this.unit,
    this.discountType,
    this.discountValue,
    this.serviceFrom,
    this.serviceTo,
  });

  String description;
  double quantity;
  double price;

  /// 'product' or 'service' — required by both FormRequests.
  String itemType;
  String? productServiceId;
  double? taxPercent;
  String? unit;
  String? discountType;
  double? discountValue;
  DateTime? serviceFrom;
  DateTime? serviceTo;

  /// A catalog row, priced and taxed as the catalog has it.
  factory DocumentItemInput.fromProduct(ProductService product) =>
      DocumentItemInput(
        description: product.name,
        quantity: 1,
        price: product.price,
        // `type` is nullable on the resource but the request requires one;
        // a service is the safer default for a catalog row without it.
        itemType: product.type == 'product' ? 'product' : 'service',
        productServiceId: product.id,
        taxPercent: product.taxPercent,
        unit: product.unit,
      );

  /// A line off a document already on the server, for editing.
  factory DocumentItemInput.fromDocumentItem(StaffDocumentItem item) =>
      DocumentItemInput(
        description: item.description,
        quantity: item.quantity,
        price: item.price,
        itemType: item.itemType == 'product' ? 'product' : 'service',
        productServiceId: item.productServiceId,
        taxPercent: item.taxPercent,
        unit: item.unit,
        discountType: item.discountType,
        discountValue: item.discountValue,
        serviceFrom: item.serviceFrom,
        serviceTo: item.serviceTo,
      );

  DocumentItemInput copy() => DocumentItemInput(
    description: description,
    quantity: quantity,
    price: price,
    itemType: itemType,
    productServiceId: productServiceId,
    taxPercent: taxPercent,
    unit: unit,
    discountType: discountType,
    discountValue: discountValue,
    serviceFrom: serviceFrom,
    serviceTo: serviceTo,
  );

  /// Quantity × price, before anything is taken off or added on.
  double get base => quantity * price;

  /// What the discount takes off this line. Mirrors the controller exactly —
  /// a flat discount is capped at the line, a percentage is not applied to
  /// more than the line either.
  double get discountAmount {
    final value = discountValue ?? 0;
    if (value <= 0) return 0;
    return discountType == 'flat'
        ? (value < base ? value : base)
        : base * (value / 100);
  }

  /// Tax is charged on what is left after the discount, as the server does.
  double get taxAmount => (base - discountAmount) * ((taxPercent ?? 0) / 100);

  double get lineTotal => base - discountAmount + taxAmount;

  /// The line as `items[]` wants it. `tax_amount` and `total` are deliberately
  /// absent: the controller computes both and would overwrite anything sent.
  Map<String, dynamic> toJson() => {
    'item_type': itemType,
    'description': description,
    'quantity': quantity,
    'price': price,
    if (productServiceId != null) 'product_service_id': productServiceId,
    if (taxPercent != null) 'tax_percent': taxPercent,
    if (unit != null && unit!.isNotEmpty) 'unit': unit,
    if (discountType != null) 'discount_type': discountType,
    if (discountValue != null) 'discount_value': discountValue,
    if (serviceFrom != null) 'service_from': _ymd(serviceFrom!),
    if (serviceTo != null) 'service_to': _ymd(serviceTo!),
  };

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// What a set of lines adds up to, computed the way the controller computes
/// it so the figure on the form is the figure that comes back from the server.
class DocumentTotals {
  const DocumentTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
  });

  final double subtotal;
  final double discount;
  final double tax;

  double get total => subtotal - discount + tax;

  factory DocumentTotals.of(Iterable<DocumentItemInput> items) {
    var subtotal = 0.0;
    var discount = 0.0;
    var tax = 0.0;
    for (final item in items) {
      subtotal += item.base;
      discount += item.discountAmount;
      tax += item.taxAmount;
    }
    return DocumentTotals(subtotal: subtotal, discount: discount, tax: tax);
  }

  static const empty = DocumentTotals(subtotal: 0, discount: 0, tax: 0);
}

class StaffDocumentPayment {
  const StaffDocumentPayment({
    required this.id,
    required this.amount,
    this.paymentDate,
    this.paymentMethod,
    this.reference,
  });

  final String id;
  final double amount;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? reference;

  factory StaffDocumentPayment.fromJson(Map<String, dynamic> json) =>
      StaffDocumentPayment(
        id: json.id(),
        amount: json.money('amount'),
        paymentDate: json.date('payment_date'),
        paymentMethod: json.str('payment_method'),
        reference: json.str('reference'),
      );
}

class StaffRefund {
  const StaffRefund({
    required this.id,
    required this.amount,
    this.method,
    this.reference,
    this.notes,
    this.createdAt,
  });

  final String id;
  final double amount;
  final String? method;
  final String? reference;
  final String? notes;
  final DateTime? createdAt;

  factory StaffRefund.fromJson(Map<String, dynamic> json) => StaffRefund(
    id: json.id(),
    amount: json.money('amount'),
    method: json.str('method'),
    reference: json.str('reference'),
    notes: json.str('notes'),
    createdAt: json.date('created_at'),
  );
}

class LinkedCreditNote {
  const LinkedCreditNote({
    required this.id,
    required this.documentNumber,
    required this.total,
    required this.status,
  });

  final String id;
  final String documentNumber;
  final double total;
  final String status;

  factory LinkedCreditNote.fromJson(Map<String, dynamic> json) =>
      LinkedCreditNote(
        id: json.id(),
        documentNumber: json.strOr('document_number', '—'),
        total: json.money('total'),
        status: json.strOr('status', 'draft'),
      );
}

// ---------------------------------------------------------------------------
// Refunds — RefundController::store (StoreRefundRequest)
// ---------------------------------------------------------------------------

/// The only `method` values `POST /documents/{invoice}/refunds` validates.
///
/// `wallet` is the odd one out: it credits the client's account for reuse,
/// while the rest merely record that money went back out of band. Both reduce
/// the invoice's paid amount, so both can flip a paid invoice back to partial.
enum RefundMethod {
  wallet('wallet', 'Account credit'),
  cash('cash', 'Cash'),
  bank('bank', 'Bank transfer'),
  mpesa('mpesa', 'M-Pesa'),
  pesapal('pesapal', 'Pesapal'),
  other('other', 'Other');

  const RefundMethod(this.wire, this.label);

  /// What the API validates against.
  final String wire;

  /// What a human is shown.
  final String label;
}

// ---------------------------------------------------------------------------
// Unpaid reminders — DocumentController::remindUnpaid
// ---------------------------------------------------------------------------

/// The channels `POST /documents/remind-unpaid` accepts. `both` is email + SMS
/// — WhatsApp is never part of it, which is why it stands alone.
enum RemindChannel {
  email('email', 'Email'),
  sms('sms', 'SMS'),
  whatsapp('whatsapp', 'WhatsApp'),
  both('both', 'Email and SMS');

  const RemindChannel(this.wire, this.label);

  final String wire;
  final String label;
}

/// What a reminder run did. The counts are **clients**, not invoices — the
/// controller groups by client and bundles — while [message] already spells
/// out both, so screens can simply show it.
class RemindUnpaidResult {
  const RemindUnpaidResult({
    required this.sent,
    required this.failed,
    required this.skipped,
    required this.errors,
    this.message,
  });

  /// Clients reminded.
  final int sent;

  /// Clients whose reminder threw.
  final int failed;

  /// Clients skipped for want of an email/phone on the chosen channel.
  final int skipped;

  /// One line per failure, `client: reason`.
  final List<String> errors;

  final String? message;

  factory RemindUnpaidResult.fromJson(Map<String, dynamic> json) =>
      RemindUnpaidResult(
        sent: json.count('sent'),
        failed: json.count('failed'),
        skipped: json.count('skipped'),
        errors: json.strings('errors'),
        message: json.str('message'),
      );
}

// ---------------------------------------------------------------------------
// Products & services — ProductServiceResource
// ---------------------------------------------------------------------------

class ProductService {
  const ProductService({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
    this.type,
    this.code,
    this.description,
    this.taxPercent,
    this.unit,
    this.category,
    this.billingCycle,
  });

  final String id;
  final String name;
  final double price;
  final bool isActive;

  /// 'product' or 'service'.
  final String? type;
  final String? code;
  final String? description;
  final double? taxPercent;
  final String? unit;
  final String? category;
  final String? billingCycle;

  bool get isRecurring => billingCycle != null && billingCycle != 'once';

  factory ProductService.fromJson(Map<String, dynamic> json) => ProductService(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    isActive: json.flag('is_active', fallback: true),
    type: json.str('type'),
    code: json.str('code'),
    description: json.str('description'),
    taxPercent: json['tax_percent'] == null ? null : json.money('tax_percent'),
    unit: json.str('unit'),
    category: json.str('category'),
    billingCycle: json.str('billing_cycle'),
  );
}

// ---------------------------------------------------------------------------
// Product add-ons — ProductAddonController::present
// ---------------------------------------------------------------------------

class StaffProductAddon {
  const StaffProductAddon({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
    required this.productNames,
    this.description,
    this.billingCycle,
    this.taxPercent,
  });

  final String id;
  final String name;
  final double price;
  final bool isActive;

  /// Which products offer this add-on.
  final List<String> productNames;
  final String? description;
  final String? billingCycle;
  final double? taxPercent;

  factory StaffProductAddon.fromJson(Map<String, dynamic> json) =>
      StaffProductAddon(
        id: json.id(),
        name: json.strOr('name', '—'),
        price: json.money('price'),
        isActive: json.flag('is_active', fallback: true),
        productNames: json
            .list('products', (p) => p.strOr('name', ''))
            .where((n) => n.isNotEmpty)
            .toList(growable: false),
        description: json.str('description'),
        billingCycle: json.str('billing_cycle'),
        taxPercent: json['tax_percent'] == null
            ? null
            : json.money('tax_percent'),
      );
}

// ---------------------------------------------------------------------------
// Configurable options — ConfigOptionGroupController::present
// ---------------------------------------------------------------------------

class StaffConfigGroup {
  const StaffConfigGroup({
    required this.id,
    required this.name,
    required this.isActive,
    required this.options,
    required this.productNames,
    this.description,
  });

  final String id;
  final String name;
  final bool isActive;
  final List<StaffConfigOption> options;
  final List<String> productNames;
  final String? description;

  factory StaffConfigGroup.fromJson(Map<String, dynamic> json) =>
      StaffConfigGroup(
        id: json.id(),
        name: json.strOr('name', '—'),
        isActive: json.flag('is_active', fallback: true),
        options: json.list('options', StaffConfigOption.fromJson),
        productNames: json
            .list('products', (p) => p.strOr('name', ''))
            .where((n) => n.isNotEmpty)
            .toList(growable: false),
        description: json.str('description'),
      );
}

class StaffConfigOption {
  const StaffConfigOption({
    required this.id,
    required this.name,
    required this.optionType,
    required this.choices,
    this.unitPrice,
  });

  final String id;
  final String name;

  /// dropdown | radio | quantity | yesno.
  final String optionType;
  final List<StaffConfigChoice> choices;
  final double? unitPrice;

  factory StaffConfigOption.fromJson(Map<String, dynamic> json) =>
      StaffConfigOption(
        id: json.id(),
        name: json.strOr('name', '—'),
        optionType: json.strOr('option_type', 'dropdown'),
        choices: json.list('choices', StaffConfigChoice.fromJson),
        unitPrice: json['unit_price'] == null ? null : json.money('unit_price'),
      );
}

class StaffConfigChoice {
  const StaffConfigChoice({
    required this.id,
    required this.label,
    required this.price,
  });

  final String id;
  final String label;
  final double price;

  factory StaffConfigChoice.fromJson(Map<String, dynamic> json) =>
      StaffConfigChoice(
        id: json.id(),
        label: json.strOr('label', '—'),
        price: json.money('price'),
      );
}

// ---------------------------------------------------------------------------
// Coupons — CouponController::present
// ---------------------------------------------------------------------------

class StaffCoupon {
  const StaffCoupon({
    required this.id,
    required this.code,
    required this.type,
    required this.value,
    required this.uses,
    required this.redemptionsCount,
    required this.isActive,
    required this.recurring,
    required this.productNames,
    this.description,
    this.appliesTo,
    this.maxUses,
    this.minOrder,
    this.startsAt,
    this.expiresAt,
    this.lastUsedAt,
  });

  final String id;
  final String code;

  /// 'percent' or 'fixed'.
  final String type;
  final double value;
  final int uses;
  final int redemptionsCount;
  final bool isActive;

  /// Whether the discount repeats on renewals, not just the first invoice.
  final bool recurring;
  final List<String> productNames;
  final String? description;
  final String? appliesTo;
  final int? maxUses;
  final double? minOrder;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;

  bool get isExhausted => maxUses != null && uses >= maxUses!;

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  /// Status word for [StatusChip] — the reason a code is unusable matters more
  /// than a bare active flag.
  String get status {
    if (!isActive) return 'draft';
    if (isExpired) return 'expired';
    if (isExhausted) return 'suspended';
    return 'active';
  }

  /// True when [value] is a percentage rather than a money amount. A fixed
  /// discount has to be rendered with the tenant's currency, which only the
  /// UI layer knows how to do.
  bool get isPercent => type == 'percent';

  /// '20%' for a percentage discount; null for a fixed one, which the caller
  /// must format via `Formatting.currency(value)`.
  String? get percentLabel =>
      isPercent ? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%' : null;

  factory StaffCoupon.fromJson(Map<String, dynamic> json) => StaffCoupon(
    id: json.id(),
    code: json.strOr('code', '—'),
    type: json.strOr('type', 'percent'),
    value: json.money('value'),
    uses: json.count('uses'),
    redemptionsCount: json.count('redemptions_count'),
    isActive: json.flag('is_active', fallback: true),
    recurring: json.flag('recurring'),
    productNames: json
        .list('products', (p) => p.strOr('name', ''))
        .where((n) => n.isNotEmpty)
        .toList(growable: false),
    description: json.str('description'),
    appliesTo: json.str('applies_to'),
    maxUses: json['max_uses'] == null ? null : json.count('max_uses'),
    minOrder: json['min_order'] == null ? null : json.money('min_order'),
    startsAt: json.date('starts_at'),
    expiresAt: json.date('expires_at'),
    lastUsedAt: json.date('last_used_at'),
  );
}

// ---------------------------------------------------------------------------
// Client subscriptions (staff) — ClientSubscriptionController::index
// ---------------------------------------------------------------------------

class StaffSubscription {
  const StaffSubscription({
    required this.id,
    required this.status,
    required this.quantity,
    required this.price,
    this.label,
    this.clientId,
    this.clientName,
    this.productName,
    this.billingCycle,
    this.startDate,
    this.expireDate,
  });

  final String id;
  final String status;
  final int quantity;
  final double price;
  final String? label;
  final String? clientId;
  final String? clientName;
  final String? productName;
  final String? billingCycle;
  final DateTime? startDate;
  final DateTime? expireDate;

  double get lineTotal => price * quantity;

  /// `/client-subscriptions` flattens the client and product into
  /// `client_name`, `product_service_name` and a top-level `price`, while
  /// other endpoints nest them. Reading only the nested shape left every row
  /// titled "—" at TZS 0.00 with the real values sitting in the payload, so
  /// the flat keys are preferred and the nested ones kept as the fallback.
  factory StaffSubscription.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final product = json.object('product_service');
    return StaffSubscription(
      id: json.id(),
      status: json.strOr('status', 'active'),
      quantity: json.count('quantity', fallback: 1),
      price: json['price'] != null
          ? json.money('price')
          : readDouble(product?['price']),
      label: json.str('label'),
      clientId: json.str('client_id') ?? client?.str('id'),
      clientName: json.str('client_name') ?? client?.str('name'),
      productName: json.str('product_service_name') ?? product?.str('name'),
      billingCycle: json.str('billing_cycle') ?? product?.str('billing_cycle'),
      startDate: json.date('start_date'),
      expireDate: json.date('expire_date'),
    );
  }
}
