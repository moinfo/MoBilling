import '../api_client.dart';
import '../api_exception.dart';
import '../paginated.dart';
import 'billing_money_models.dart';

/// Money movement for the staff app: recording payments received, paying
/// bills out, and the upcoming recurring-billing schedule.
///
/// Validation notes that shape the request bodies below (from
/// `StorePaymentInRequest` / `StorePaymentOutRequest`):
///   * payments-in needs `client_id` — NOT just the document. The invoice row
///     carries it, which is why [UnpaidInvoice] keeps `clientId`.
///   * `payment_date` on a payment-in is `before_or_equal:today`; a future date
///     is a 422.
///   * `payment_method` must be one of the tenant's configured method *values*
///     (not labels) — see [paymentMethods].
///   * payments-out rejects an amount above the bill's remaining balance, and
///     rejects a bill that is already settled.
class BillingMoneyService {
  const BillingMoneyService(this._api);

  final ApiClient _api;

  /// GET /settings/payment-methods — the tenant's configured methods.
  ///
  /// Falls back to [TenantPaymentMethod.defaults] when the tenant never saved
  /// the setting or the caller lacks permission, because the create forms must
  /// stay usable and those defaults are what the backend's own fallback
  /// `Rule::in` accepts anyway.
  Future<List<TenantPaymentMethod>> paymentMethods() async {
    try {
      final body =
          await _api.get<dynamic>('/settings/payment-methods');
      final methods =
          Paginated.fromJson(body, TenantPaymentMethod.fromJson).items;
      final usable =
          methods.where((m) => m.value.isNotEmpty).toList(growable: false);
      return usable.isEmpty ? TenantPaymentMethod.defaults : usable;
    } on ApiException {
      return TenantPaymentMethod.defaults;
    }
  }

  /// GET /documents?type=invoice&status=sent — invoices a payment can go
  /// against. `sent` expands server-side to sent + overdue + partial.
  Future<Paginated<UnpaidInvoice>> unpaidInvoices({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/documents',
      query: {
        'type': 'invoice',
        'status': 'sent',
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, UnpaidInvoice.fromJson);
  }

  /// POST /payments-in — record a payment received.
  ///
  /// [clientId] is required by the API even when [documentId] is given.
  /// Returns the server's message so the caller can show it verbatim.
  Future<String?> recordPaymentIn({
    required String clientId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? documentId,
    String? reference,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/payments-in',
      body: {
        'client_id': clientId,
        'document_id': ?documentId,
        'amount': amount,
        'payment_date': _ymd(paymentDate),
        'payment_method': paymentMethod,
        'reference': ?reference,
        'notes': ?notes,
      },
    );
    return body['message']?.toString();
  }

  /// GET /payments-out — paginated, newest first. [billId] narrows to one bill.
  Future<Paginated<StaffPaymentOut>> paymentsOut({
    String? billId,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/payments-out',
      query: {'bill_id': billId, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffPaymentOut.fromJson);
  }

  /// GET /bills — the bills a payment-out can be recorded against.
  ///
  /// The index eager-loads `payments`, so [StaffBill.remaining] is exact and
  /// can cap the amount field client-side before the server's validator does.
  Future<Paginated<StaffBill>> bills({
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _api.get<dynamic>(
      '/bills',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffBill.fromJson);
  }

  /// POST /payments-out — pay a bill.
  ///
  /// The `receipt` file upload the API also accepts is omitted: it needs
  /// multipart plus a file picker, and the staff app has neither wired yet.
  Future<void> recordPaymentOut({
    required String billId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? controlNumber,
    String? reference,
    String? notes,
  }) =>
      _api.post<dynamic>('/payments-out', body: {
        'bill_id': billId,
        'amount': amount,
        'payment_date': _ymd(paymentDate),
        'payment_method': paymentMethod,
        'control_number': ?controlNumber,
        'reference': ?reference,
        'notes': ?notes,
      });

  /// GET /next-bills — projected upcoming recurring charges (not persisted
  /// rows; the controller walks each active subscription's cycle forward).
  Future<List<NextBill>> nextBills() async {
    final body = await _api.get<dynamic>('/next-bills');
    return Paginated.fromJson(body, NextBill.fromJson).items;
  }

  /// POST /client-subscriptions/{id}/generate-invoice — bill a subscription
  /// now instead of waiting for the recurring job. Needs
  /// `client_subscriptions.create`.
  Future<GeneratedInvoice> generateInvoice(String subscriptionId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/client-subscriptions/$subscriptionId/generate-invoice',
    );
    return GeneratedInvoice.fromJson(body);
  }

  /// The API takes dates as Y-m-d; sending an ISO timestamp trips
  /// `before_or_equal:today` around midnight in a non-UTC zone.
  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class BillingMoneyPermissions {
  static const paymentsInCreate = 'payments_in.create';
  static const paymentsOutRead = 'payments_out.read';
  static const paymentsOutCreate = 'payments_out.create';
  static const billsRead = 'bills.read';
  static const subscriptionsRead = 'client_subscriptions.read';
  static const subscriptionsCreate = 'client_subscriptions.create';
}
