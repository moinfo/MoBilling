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
  bool get isPayable =>
      isInvoice && !isCancelled && !isDraft && balanceDue > 0;

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
      linkedCreditNotes:
          json.list('linked_credit_notes', LinkedCreditNote.fromJson),
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

  factory StaffDocumentItem.fromJson(Map<String, dynamic> json) =>
      StaffDocumentItem(
        id: json.id(),
        description: json.strOr('description', '—'),
        quantity: json.money('quantity', fallback: 1),
        price: json.money('price'),
        total: json.money('total'),
        unit: json.str('unit'),
        taxPercent:
            json['tax_percent'] == null ? null : json.money('tax_percent'),
        serviceFrom: json.date('service_from'),
        serviceTo: json.date('service_to'),
      );
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
        taxPercent:
            json['tax_percent'] == null ? null : json.money('tax_percent'),
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
        taxPercent:
            json['tax_percent'] == null ? null : json.money('tax_percent'),
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
        unitPrice:
            json['unit_price'] == null ? null : json.money('unit_price'),
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
