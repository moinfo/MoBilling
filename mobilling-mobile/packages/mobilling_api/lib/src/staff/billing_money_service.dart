import 'dart:typed_data';

import 'package:dio/dio.dart';

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
      final body = await _api.get<dynamic>('/settings/payment-methods');
      final methods = Paginated.fromJson(
        body,
        TenantPaymentMethod.fromJson,
      ).items;
      final usable = methods
          .where((m) => m.value.isNotEmpty)
          .toList(growable: false);
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

  /// GET /payments-in — the tenant's payment history, newest first.
  ///
  /// `search` matches the reference, the invoice number or the client name.
  Future<Paginated<StaffPaymentIn>> paymentsIn({
    String? search,
    String? documentId,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/payments-in',
      query: {
        'search': search,
        'document_id': documentId,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, StaffPaymentIn.fromJson);
  }

  /// POST /payments-in — record a payment received.
  ///
  /// [clientId] is required by the API even when [documentId] is given.
  /// [sendEmail] mirrors the web's default (checked): the controller reads it
  /// as `boolean('send_email', true)` and only mails when a `document_id` is
  /// present, so a standalone payment never sends whatever this says.
  /// Returns the server's message so the caller can show it verbatim.
  Future<String?> recordPaymentIn({
    required String clientId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? documentId,
    String? reference,
    String? notes,
    bool sendEmail = true,
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
        'send_email': sendEmail,
      },
    );
    return body['message']?.toString();
  }

  /// PUT /payments-in/{id} — correct a recorded payment. Needs
  /// `payments_in.update`.
  ///
  /// The route re-validates with `StorePaymentInRequest`, so every required
  /// field goes back up — `client_id` included, even when only the amount
  /// changed. The controller recomputes the invoice's paid/partial/sent status
  /// inside the same transaction.
  Future<void> updatePaymentIn({
    required String id,
    required String clientId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? documentId,
    String? reference,
    String? notes,
  }) => _api.put<dynamic>(
    '/payments-in/$id',
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

  /// DELETE /payments-in/{id} — needs `payments_in.delete`. The invoice's
  /// status is recomputed, so deleting the only payment sends it back to
  /// `sent`. Returns the server's message ("Payment deleted").
  Future<String?> deletePaymentIn(String id) async {
    final body = await _api.delete<Map<String, dynamic>>('/payments-in/$id');
    return body['message']?.toString();
  }

  /// POST /payments-in/{id}/resend-receipt — needs
  /// `payments_in.resend_receipt`.
  ///
  /// A 422 with "Client has no email address" is the API's own answer when
  /// there is nobody to mail, so let it surface as an [ApiException] message.
  Future<String?> resendReceipt(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/payments-in/$id/resend-receipt',
    );
    return body['message']?.toString();
  }

  /// GET /payments-in/{id}/receipt-pdf — the receipt as PDF bytes. Needs
  /// `payments_in.read`, the same permission as the list itself.
  Future<Uint8List> receiptPdf(String id) =>
      _download('/payments-in/$id/receipt-pdf');

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
  /// [receiptPath] attaches proof of payment (the bank slip or control-number
  /// receipt). The API accepts `pdf,jpg,jpeg,png` up to 5 MB and stores it as
  /// `receipt_path`; the request only becomes multipart when a file is given,
  /// because Laravel reads the plain JSON body faster and the field is
  /// optional.
  Future<void> recordPaymentOut({
    required String billId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? controlNumber,
    String? reference,
    String? notes,
    String? receiptPath,
  }) async {
    final fields = <String, dynamic>{
      'bill_id': billId,
      'amount': amount,
      'payment_date': _ymd(paymentDate),
      'payment_method': paymentMethod,
      'control_number': ?controlNumber,
      'reference': ?reference,
      'notes': ?notes,
    };

    if (receiptPath == null || receiptPath.isEmpty) {
      await _api.post<dynamic>('/payments-out', body: fields);
      return;
    }

    // `amount` must go up as a string in multipart — Dio would otherwise send
    // the double's `toString()`, which is the same text but via a code path
    // that trips on `1.0E+3` for large values.
    final form = FormData.fromMap({...fields, 'amount': amount.toString()});
    form.files.add(
      MapEntry('receipt', await MultipartFile.fromFile(receiptPath)),
    );

    try {
      await _api.raw.post<dynamic>('/payments-out', data: form);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// PUT /payments-out/{id} — correct a payment made. Needs
  /// `payments_out.update`.
  ///
  /// Unlike the store route this validates with `sometimes` rules and has no
  /// remaining-balance check, so an edit may legitimately push the bill past
  /// its amount; the controller recomputes `paid_at` either way. The receipt
  /// file cannot be replaced here — the route ignores it.
  Future<void> updatePaymentOut({
    required String id,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? controlNumber,
    String? reference,
    String? notes,
  }) => _api.put<dynamic>(
    '/payments-out/$id',
    body: {
      'amount': amount,
      'payment_date': _ymd(paymentDate),
      'payment_method': paymentMethod,
      'control_number': ?controlNumber,
      'reference': ?reference,
      'notes': ?notes,
    },
  );

  /// DELETE /payments-out/{id} — needs `payments_out.delete`. The bill's
  /// `paid_at` is recomputed, so removing the payment that settled it reopens
  /// it. Returns the server's message ("Payment deleted").
  Future<String?> deletePaymentOut(String id) async {
    final body = await _api.delete<Map<String, dynamic>>('/payments-out/$id');
    return body['message']?.toString();
  }

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

  /// Fetch a PDF as raw bytes. Goes through [ApiClient.raw] because the typed
  /// helpers decode JSON, and re-wraps the failure so callers still only ever
  /// catch [ApiException].
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

  /// The API takes dates as Y-m-d; sending an ISO timestamp trips
  /// `before_or_equal:today` around midnight in a non-UTC zone.
  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class BillingMoneyPermissions {
  /// Also gates the receipt PDF — `receipt-pdf` is a read route.
  static const paymentsInRead = 'payments_in.read';
  static const paymentsInCreate = 'payments_in.create';
  static const paymentsInUpdate = 'payments_in.update';
  static const paymentsInDelete = 'payments_in.delete';
  static const paymentsInResendReceipt = 'payments_in.resend_receipt';
  static const paymentsOutRead = 'payments_out.read';
  static const paymentsOutCreate = 'payments_out.create';
  static const paymentsOutUpdate = 'payments_out.update';
  static const paymentsOutDelete = 'payments_out.delete';
  static const billsRead = 'bills.read';
  static const subscriptionsRead = 'client_subscriptions.read';
  static const subscriptionsCreate = 'client_subscriptions.create';
}
