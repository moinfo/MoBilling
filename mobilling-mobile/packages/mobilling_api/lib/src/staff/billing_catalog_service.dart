import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../paginated.dart';
import 'billing_catalog_models.dart';
import 'staff_models.dart' show StaffInvoiceRow;

/// Document detail, the other document types, and the product catalog.
///
/// Endpoint quirks:
///   * Quotations and proformas are `/documents?type=…`; **credit notes have a
///     dedicated `/credit-notes` endpoint** despite living in the same table.
///   * Configurable options are at **`/config-option-groups`**, not
///     `/config-options`.
///   * Add-ons, config groups and coupons are **unpaginated** (`->get()`),
///     while products and documents paginate.
class BillingCatalogService {
  const BillingCatalogService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------

  /// GET /documents/{id} — the full document with items, payments, refunds and
  /// any linked credit notes.
  Future<StaffDocument> document(String id) async {
    final body = await _api.get<Map<String, dynamic>>('/documents/$id');
    return StaffDocument.fromJson(_unwrap(body));
  }

  /// POST /documents — raise a quotation, proforma or invoice. Needs
  /// `documents.create`.
  ///
  /// The document is always created as a **draft**; there is no send-on-save
  /// flag, so getting it to the client is a separate call ([sendDocument],
  /// [submitForApproval]) made from the document itself. [type] must be one of
  /// [DocumentType]'s three document wire values — a credit note goes through
  /// [createCreditNote] instead.
  ///
  /// Every money figure is derived server-side from the items, so nothing here
  /// sends a subtotal, a tax amount or a total.
  Future<StaffDocument> createDocument({
    required String clientId,
    required String type,
    required DateTime date,
    required List<DocumentItemInput> items,
    DateTime? dueDate,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/documents',
      body: {
        'client_id': clientId,
        'type': type,
        'date': _ymd(date),
        if (dueDate != null) 'due_date': _ymd(dueDate),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'items': [for (final item in items) item.toJson()],
      },
    );
    return StaffDocument.fromJson(_unwrap(body));
  }

  /// PUT /documents/{id} — replace a document's client, dates, notes and
  /// **every one of its items**. Needs `documents.update`.
  ///
  /// Two things follow from "replace": an item omitted here is deleted, and
  /// the financial status is rederived from the payments already recorded
  /// (paid / partial / sent). A cancelled document is refused with a 422 —
  /// restore it first.
  Future<StaffDocument> updateDocument(
    String id, {
    required String clientId,
    required String type,
    required DateTime date,
    required List<DocumentItemInput> items,
    DateTime? dueDate,
    String? notes,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/documents/$id',
      body: {
        'client_id': clientId,
        'type': type,
        'date': _ymd(date),
        if (dueDate != null) 'due_date': _ymd(dueDate),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'items': [for (final item in items) item.toJson()],
      },
    );
    return StaffDocument.fromJson(_unwrap(body));
  }

  /// POST /credit-notes — raise a credit note against a client, optionally
  /// linked to the invoice it credits. Needs `documents.create` (credit notes
  /// reuse the document permissions).
  ///
  /// Created as a draft: the client's wallet is **not** credited until
  /// [issueCreditNote] runs, and `cancel_source_invoice` is honoured there
  /// rather than here.
  Future<StaffDocument> createCreditNote({
    required String clientId,
    required List<DocumentItemInput> items,
    String? sourceInvoiceId,
    DateTime? date,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/credit-notes',
      body: {
        'client_id': clientId,
        'source_invoice_id': ?sourceInvoiceId,
        if (date != null) 'date': _ymd(date),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'items': [for (final item in items) item.toJson()],
      },
    );
    return StaffDocument.fromJson(_unwrap(body));
  }

  /// DELETE /credit-notes/{id} — needs `documents.delete`. Only a draft
  /// (un-issued) credit note may go; the controller 422s otherwise.
  ///
  /// Prefer this over [deleteDocument] for a credit note: this endpoint clears
  /// the note's items too, where the generic one leaves them behind.
  Future<String?> deleteCreditNote(String id) async {
    final body = await _api.delete<Map<String, dynamic>>('/credit-notes/$id');
    return body['message']?.toString();
  }

  /// GET /credit-notes/{id}/pdf — the same renderer as a document's PDF, but
  /// behind the endpoint that checks the row really is a credit note. Needs
  /// `documents.download`.
  Future<Uint8List> creditNotePdf(String id) =>
      _download('/credit-notes/$id/pdf');

  /// POST /documents/{id}/send — email it to the client. Needs
  /// `documents.send`.
  Future<String?> sendDocument(String id) async {
    final body = await _api.post<Map<String, dynamic>>('/documents/$id/send');
    return body['message']?.toString();
  }

  /// GET /documents/{id}/pdf — the rendered document as PDF bytes, for the
  /// share sheet. Needs `documents.download`.
  Future<Uint8List> documentPdf(String id) => _download('/documents/$id/pdf');

  /// POST /documents/{id}/send-whatsapp — delivers the WhatsApp invoice
  /// template (with a Pay Now button when payable) regardless of the tenant's
  /// reminder-channel toggles. Needs `documents.send`, WhatsApp linked on the
  /// tenant, and a phone number on the client — the controller 422s otherwise.
  Future<String?> sendDocumentWhatsApp(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/documents/$id/send-whatsapp',
    );
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/submit-for-approval — draft → pending_approval.
  /// Needs `documents.send`; the controller rejects anything but a draft.
  Future<String?> submitForApproval(String id) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/documents/$id/submit-for-approval',
    );
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/approve — pending_approval → sent, re-dating the
  /// document to today and shifting the due date by the same payment window.
  /// Needs `documents.approve`. With [sendEmail] the client is notified in the
  /// same call; a delivery failure does **not** undo the approval, it just
  /// comes back in the message.
  Future<String?> approveDocument(String id, {bool sendEmail = true}) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/documents/$id/approve',
      body: {'send_email': sendEmail},
    );
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/reject — pending_approval → draft. Needs
  /// `documents.approve`. [reason] is recorded by the caller's own audit only;
  /// the controller validates it but does not persist it today.
  Future<String?> rejectDocument(String id, {String? reason}) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/documents/$id/reject',
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/return-to-draft — reopens a sent/overdue/partial or
  /// pending invoice for editing. Needs `documents.update`; refused once any
  /// payment is recorded.
  Future<String?> returnToDraft(String id) async {
    final body = await _api.patch<Map<String, dynamic>>(
      '/documents/$id/return-to-draft',
    );
    return body['message']?.toString();
  }

  /// DELETE /documents/{id} — needs `documents.delete`. Only draft, rejected
  /// or cancelled documents with no payments may go; anything else must be
  /// cancelled first (the controller 422s with that instruction).
  Future<String?> deleteDocument(String id) async {
    final body = await _api.delete<Map<String, dynamic>>('/documents/$id');
    return body['message']?.toString();
  }

  /// POST /documents/{invoice}/refunds — refund money already taken on an
  /// invoice. Needs `payments_in.create`. [method] must be one of
  /// [RefundMethod]'s wire values; `wallet` adds reusable account credit,
  /// every other method records an external refund. Either way the invoice's
  /// paid amount drops and its status is recomputed.
  Future<String?> recordRefund(
    String invoiceId, {
    required double amount,
    required String method,
    String? reference,
    String? reason,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/documents/$invoiceId/refunds',
      body: {
        'amount': amount,
        'method': method,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return body['message']?.toString();
  }

  /// POST /documents/remind-unpaid — chase unpaid invoices. Needs
  /// `documents.send`.
  ///
  /// The invoices are named by id, and the server filters them down to
  /// `type=invoice` in sent | overdue | partial, then groups them **by client**
  /// so one client with three invoices gets one bundled reminder rather than
  /// three. [channel] is one of [RemindChannel]'s wire values.
  ///
  /// Sending to nobody at all still returns 200 with a message saying so; a
  /// batch where every send failed comes back 422, i.e. as an [ApiException].
  Future<RemindUnpaidResult> remindUnpaid({
    required List<String> documentIds,
    required String channel,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/documents/remind-unpaid',
      body: {'document_ids': documentIds, 'channel': channel},
    );
    return RemindUnpaidResult.fromJson(body);
  }

  /// POST /documents/{id}/convert — quotation → proforma/invoice, or
  /// proforma → invoice. Needs `documents.convert`. [targetType] is
  /// `invoice` or `proforma`; the controller requires it.
  Future<String?> convertDocument(
    String id, {
    String targetType = 'invoice',
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/documents/$id/convert',
      body: {'target_type': targetType},
    );
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/cancel and /uncancel.
  Future<void> cancelDocument(String id) =>
      _api.patch<dynamic>('/documents/$id/cancel');

  Future<void> uncancelDocument(String id) =>
      _api.patch<dynamic>('/documents/$id/uncancel');

  /// PATCH /documents/{id}/due-date — needs `documents.extend_due_date`.
  Future<void> extendDueDate(String id, DateTime dueDate) =>
      _api.patch<dynamic>(
        '/documents/$id/due-date',
        body: {'due_date': _ymd(dueDate)},
      );

  /// GET /credit-notes — same table as documents, different endpoint.
  Future<Paginated<StaffInvoiceRow>> creditNotes({
    String? status,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/credit-notes',
      query: {
        'status': status,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, StaffInvoiceRow.fromJson);
  }

  /// POST /credit-notes/{id}/issue — moves a draft credit note to issued.
  Future<void> issueCreditNote(String id) =>
      _api.post<dynamic>('/credit-notes/$id/issue');

  // ---------------------------------------------------------------------
  // Catalog
  // ---------------------------------------------------------------------

  /// GET /product-services — paginated.
  Future<Paginated<ProductService>> products({
    String? type,
    String? search,
    bool activeOnly = false,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/product-services',
      query: {
        'type': type,
        'search': search,
        'active_only': activeOnly ? 1 : null,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, ProductService.fromJson);
  }

  /// GET /product-addons — unpaginated.
  Future<List<StaffProductAddon>> addons({String? search}) async {
    final body = await _api.get<dynamic>(
      '/product-addons',
      query: {'search': search},
    );
    return Paginated.fromJson(body, StaffProductAddon.fromJson).items;
  }

  /// GET /config-option-groups — unpaginated, with options and choices nested.
  Future<List<StaffConfigGroup>> configGroups({String? search}) async {
    final body = await _api.get<dynamic>(
      '/config-option-groups',
      query: {'search': search},
    );
    return Paginated.fromJson(body, StaffConfigGroup.fromJson).items;
  }

  /// GET /coupons — unpaginated, with redemption counts.
  Future<List<StaffCoupon>> coupons({String? search}) async {
    final body = await _api.get<dynamic>('/coupons', query: {'search': search});
    return Paginated.fromJson(body, StaffCoupon.fromJson).items;
  }

  /// GET /client-subscriptions — tenant-wide, paginated.
  Future<Paginated<StaffSubscription>> subscriptions({
    String? status,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/client-subscriptions',
      query: {
        'status': status,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, StaffSubscription.fromJson);
  }

  /// Binary GET through the same bearer-token channel as everything else, so
  /// no URL ever has to carry a token. Mirrors `HrService._download`.
  Future<Uint8List> _download(String path) async {
    try {
      final response = await _api.raw.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class BillingCatalogPermissions {
  static const documentsRead = 'documents.read';
  static const documentsCreate = 'documents.create';
  static const documentsSend = 'documents.send';
  static const documentsConvert = 'documents.convert';
  static const documentsUpdate = 'documents.update';
  static const documentsDelete = 'documents.delete';
  static const documentsDownload = 'documents.download';
  static const documentsApprove = 'documents.approve';
  static const documentsExtendDueDate = 'documents.extend_due_date';

  /// Refunds hang off the invoice but are money **in** being given back, so
  /// the route guards them with the payments-in permission, not a document one.
  static const paymentsInCreate = 'payments_in.create';

  static const productsRead = 'products.read';
  static const subscriptionsRead = 'client_subscriptions.read';
}
