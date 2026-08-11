import '../api_client.dart';
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

  /// POST /documents/{id}/send — email it to the client. Needs
  /// `documents.send`.
  Future<String?> sendDocument(String id) async {
    final body =
        await _api.post<Map<String, dynamic>>('/documents/$id/send');
    return body['message']?.toString();
  }

  /// POST /documents/{id}/convert — quotation/proforma → invoice. Needs
  /// `documents.convert`.
  Future<String?> convertDocument(String id) async {
    final body =
        await _api.post<Map<String, dynamic>>('/documents/$id/convert');
    return body['message']?.toString();
  }

  /// PATCH /documents/{id}/cancel and /uncancel.
  Future<void> cancelDocument(String id) =>
      _api.patch<dynamic>('/documents/$id/cancel');

  Future<void> uncancelDocument(String id) =>
      _api.patch<dynamic>('/documents/$id/uncancel');

  /// PATCH /documents/{id}/due-date — needs `documents.extend_due_date`.
  Future<void> extendDueDate(String id, DateTime dueDate) =>
      _api.patch<dynamic>('/documents/$id/due-date',
          body: {'due_date': _ymd(dueDate)});

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
    final body = await _api.get<dynamic>(
      '/coupons',
      query: {'search': search},
    );
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
  static const documentsSend = 'documents.send';
  static const documentsConvert = 'documents.convert';
  static const documentsUpdate = 'documents.update';
  static const documentsExtendDueDate = 'documents.extend_due_date';
  static const productsRead = 'products.read';
  static const subscriptionsRead = 'client_subscriptions.read';
}
