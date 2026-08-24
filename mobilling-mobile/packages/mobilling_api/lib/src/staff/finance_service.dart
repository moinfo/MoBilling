import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
import '../paginated.dart';
import 'billing_money_models.dart' show StaffBill;
import 'finance_models.dart';
import 'staff_service.dart' show UploadProgress;

/// Money going out: expenses (with the petty-cash approval flow), the petty
/// cash float, statutory obligations and recurring bills.
///
/// Notes:
///   * Expenses attach to a **sub**-category, never a parent category.
///   * Files split two ways, and the difference matters. The receipt on an
///     expense and a signed voucher land on the server's **public** disk and
///     come back as absolute `*_attachment_url` / `attachment_url` links that
///     open without a token. The *blank* voucher PDF is generated on demand
///     and streamed from an authenticated route, so it has to be downloaded
///     with the bearer token like any other PDF in this app.
///   * `PUT /expenses/{id}` cannot carry a file — PHP does not parse a
///     multipart body on PUT — so [updateExpense] posts with `_method=PUT`,
///     exactly as the web client does.
///   * `/bills` is shared with `BillingMoneyService` (the pay-a-bill picker),
///     so [StaffBill] is reused rather than duplicated.
class FinanceService {
  const FinanceService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Expenses
  // ---------------------------------------------------------------------

  /// GET /expenses — paginated, newest first.
  Future<Paginated<Expense>> expenses({
    String? approvalStatus,
    String? subCategoryId,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/expenses',
      query: {
        'approval_status': approvalStatus,
        'sub_expense_category_id': subCategoryId,
        'search': search,
        'date_from': dateFrom,
        'date_to': dateTo,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, Expense.fromJson);
  }

  /// POST /expenses — record an expense.
  ///
  /// Passing [pettyCashAccountId] makes it a petty-cash expense, which then
  /// needs administrator approval before it leaves the verified balance;
  /// [givenByName]/[receivedByName] are the voucher signatories for that case.
  ///
  /// [attachmentPath] is the receipt — a photo straight off the camera or a
  /// file off the device. With one the call becomes multipart (field
  /// `attachment`, 10 MB, pdf/jpg/jpeg/png/doc/docx/xls/xlsx); without one it
  /// stays the plain JSON post it has always been.
  Future<void> createExpense({
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? subCategoryId,
    String? pettyCashAccountId,
    String? controlNumber,
    String? reference,
    String? notes,
    String? givenByName,
    String? receivedByName,
    String? attachmentPath,
    UploadProgress? onProgress,
  }) async {
    final fields = _expenseFields(
      description: description,
      amount: amount,
      expenseDate: expenseDate,
      paymentMethod: paymentMethod,
      subCategoryId: subCategoryId,
      pettyCashAccountId: pettyCashAccountId,
      controlNumber: controlNumber,
      reference: reference,
      notes: notes,
      givenByName: givenByName,
      receivedByName: receivedByName,
    );

    if (attachmentPath == null) {
      await _api.post<dynamic>('/expenses', body: fields);
      return;
    }
    await _multipart(
      '/expenses',
      fields,
      filePath: attachmentPath,
      fileField: 'attachment',
      onProgress: onProgress,
    );
  }

  /// POST /expenses/{id} with `_method=PUT` — needs `expenses.update`.
  ///
  /// The API re-validates every field, so this is a full replace rather than a
  /// patch: pass the whole expense back. Omitting [attachmentPath] leaves the
  /// receipt already on file untouched; passing one replaces it. Editing a
  /// petty-cash expense sends it back to `pending` server-side.
  Future<void> updateExpense(
    String id, {
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? subCategoryId,
    String? pettyCashAccountId,
    String? controlNumber,
    String? reference,
    String? notes,
    String? givenByName,
    String? receivedByName,
    String? attachmentPath,
    UploadProgress? onProgress,
  }) => _multipart(
    '/expenses/$id',
    {
      '_method': 'PUT',
      ..._expenseFields(
        description: description,
        amount: amount,
        expenseDate: expenseDate,
        paymentMethod: paymentMethod,
        subCategoryId: subCategoryId,
        pettyCashAccountId: pettyCashAccountId,
        controlNumber: controlNumber,
        reference: reference,
        notes: notes,
        givenByName: givenByName,
        receivedByName: receivedByName,
      ),
    },
    filePath: attachmentPath,
    fileField: 'attachment',
    onProgress: onProgress,
  );

  /// DELETE /expenses/{id} — needs `expenses.delete`. Soft delete; the
  /// receipt and voucher files are deliberately kept.
  Future<String?> deleteExpense(String id) =>
      _message(() => _api.delete<dynamic>('/expenses/$id'));

  /// POST /expenses/{id}/approve — needs `expenses.approve`.
  Future<void> approveExpense(String id) =>
      _api.post<dynamic>('/expenses/$id/approve');

  /// POST /expenses/{id}/reject — a reason is what the approver owes the
  /// person who submitted it.
  Future<void> rejectExpense(String id, {required String reason}) =>
      _api.post<dynamic>('/expenses/$id/reject', body: {'reason': reason});

  /// POST /expenses/{id}/unapprove — needs `expenses.approve`. Puts an
  /// approved petty-cash expense back to `pending` and returns its amount to
  /// the verified balance, which is how an approver undoes a mis-tap. The API
  /// answers 422 for a non-petty-cash expense or one that is not approved.
  Future<void> unapproveExpense(String id) =>
      _api.post<dynamic>('/expenses/$id/unapprove');

  /// GET /expenses/{id}/voucher — the blank petty-cash voucher PDF, generated
  /// on demand for both parties to sign. Needs `expenses.read`.
  Future<Uint8List> expenseVoucherPdf(String id) =>
      _download('/expenses/$id/voucher');

  /// POST /expenses/{id}/voucher — the signed voucher, scanned or
  /// photographed. Needs `expenses.update` (or `expenses.create` when you
  /// recorded the expense yourself). 10 MB, pdf/jpg/jpeg/png.
  Future<String?> uploadExpenseVoucher(
    String id, {
    required String filePath,
    UploadProgress? onProgress,
  }) async {
    final body = await _multipart(
      '/expenses/$id/voucher',
      const {},
      filePath: filePath,
      fileField: 'voucher',
      onProgress: onProgress,
    );
    return body['message'] as String?;
  }

  /// GET /expense-categories — parents with their sub-categories nested.
  Future<List<ExpenseCategory>> expenseCategories() async {
    final body = await _api.get<dynamic>('/expense-categories');
    return Paginated.fromJson(body, ExpenseCategory.fromJson).items;
  }

  /// POST /expense-categories — a parent when [parentId] is null, otherwise a
  /// sub-category.
  Future<void> createExpenseCategory({
    required String name,
    String? parentId,
  }) => _api.post<dynamic>(
    '/expense-categories',
    body: {'name': name, 'expense_category_id': ?parentId},
  );

  /// PUT /expense-categories/{id} — needs `expense_categories.update`. One
  /// route serves both levels: the API resolves [id] as a parent first, then
  /// as a sub-category.
  Future<void> updateExpenseCategory(
    String id, {
    required String name,
    String? parentId,
    bool? isActive,
  }) => _api.put<dynamic>(
    '/expense-categories/$id',
    body: {
      'name': name,
      'expense_category_id': ?parentId,
      'is_active': ?isActive,
    },
  );

  /// DELETE /expense-categories/{id} — needs `expense_categories.delete`.
  /// Refuses with 422 while any expense still points at the category or one
  /// of its sub-categories.
  Future<String?> deleteExpenseCategory(String id) =>
      _message(() => _api.delete<dynamic>('/expense-categories/$id'));

  // ---------------------------------------------------------------------
  // Petty cash
  // ---------------------------------------------------------------------

  /// GET /petty-cash — balances, unified history and recent reconciliations.
  Future<PettyCash> pettyCash() async {
    final body = await _api.get<Map<String, dynamic>>('/petty-cash');
    return PettyCash.fromJson(body);
  }

  /// POST /petty-cash/transactions — needs `petty_cash.topup`.
  /// [type] is top_up | return (adjustments are only ever written by a
  /// reconciliation).
  Future<void> pettyCashTransaction({
    required String type,
    required double amount,
    required DateTime transactionDate,
    String? notes,
  }) => _api.post<dynamic>(
    '/petty-cash/transactions',
    body: {
      'type': type,
      'amount': amount,
      'transaction_date': _ymd(transactionDate),
      'notes': ?notes,
    },
  );

  /// DELETE /petty-cash/transactions/{id} — needs `petty_cash.delete`.
  ///
  /// Only a `top_up` or a `return` can go: reconciliation adjustments are the
  /// ledger's own record of a cash count and the API answers 422 for them.
  /// The signed voucher file is destroyed with the row.
  Future<String?> deletePettyCashTransaction(String id) =>
      _message(() => _api.delete<dynamic>('/petty-cash/transactions/$id'));

  /// GET /petty-cash/transactions/{id}/voucher — the blank voucher PDF for a
  /// top-up or return. Needs `petty_cash.read`.
  Future<Uint8List> pettyCashVoucherPdf(String id) =>
      _download('/petty-cash/transactions/$id/voucher');

  /// POST /petty-cash/transactions/{id}/voucher — the signed copy back.
  /// Needs `petty_cash.topup` or `petty_cash.reconcile`.
  Future<String?> uploadPettyCashVoucher(
    String id, {
    required String filePath,
    UploadProgress? onProgress,
  }) async {
    final body = await _multipart(
      '/petty-cash/transactions/$id/voucher',
      const {},
      filePath: filePath,
      fileField: 'voucher',
      onProgress: onProgress,
    );
    return body['message'] as String?;
  }

  /// POST /petty-cash/reconciliations — record a physical cash count. Needs
  /// `petty_cash.reconcile`. [resolution] is `accepted` (book the
  /// difference as an adjustment) or `investigating` (leave the ledger as
  /// is and flag it).
  Future<void> reconcilePettyCash({
    required double countedBalance,
    required String resolution,
    String? notes,
  }) => _api.post<dynamic>(
    '/petty-cash/reconciliations',
    body: {
      'counted_balance': countedBalance,
      'resolution': resolution,
      'notes': ?notes,
    },
  );

  // ---------------------------------------------------------------------
  // Statutory
  // ---------------------------------------------------------------------

  /// GET /statutories — paginated, soonest due first.
  Future<Paginated<Statutory>> statutories({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/statutories',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, Statutory.fromJson);
  }

  /// GET /statutory-schedule — every obligation with status counters.
  Future<StatutorySchedule> statutorySchedule() async {
    final body = await _api.get<Map<String, dynamic>>('/statutory-schedule');
    return StatutorySchedule.fromJson(body);
  }

  // ---------------------------------------------------------------------
  // Bills
  // ---------------------------------------------------------------------

  /// GET /bills — recurring operating and statutory bills. Reuses
  /// [StaffBill] so the payment picker and this list agree on `remaining`.
  Future<Paginated<StaffBill>> bills({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/bills',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffBill.fromJson);
  }

  /// GET /bill-categories — nested one level.
  Future<List<BillCategory>> billCategories() async {
    final body = await _api.get<dynamic>('/bill-categories');
    return Paginated.fromJson(body, BillCategory.fromJson).items;
  }

  /// POST /bill-categories.
  Future<void> createBillCategory({
    required String name,
    String? parentId,
    String? billingCycle,
  }) => _api.post<dynamic>(
    '/bill-categories',
    body: {
      'name': name,
      'parent_id': ?parentId,
      'billing_cycle': ?billingCycle,
    },
  );

  /// PUT /bill-categories/{id} — needs `bills.update`.
  Future<void> updateBillCategory(
    String id, {
    required String name,
    String? parentId,
    String? billingCycle,
  }) => _api.put<dynamic>(
    '/bill-categories/$id',
    body: {
      'name': name,
      'parent_id': ?parentId,
      'billing_cycle': ?billingCycle,
    },
  );

  /// DELETE /bill-categories/{id} — needs `bills.delete`. Refuses with 422
  /// while a bill still points at the category, the same as its expense
  /// counterpart.
  Future<String?> deleteBillCategory(String id) =>
      _message(() => _api.delete<dynamic>('/bill-categories/$id'));

  // ---------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------

  /// The body `StoreExpenseRequest` validates, shared by create and update so
  /// the two can never drift. Null entries are dropped rather than sent as
  /// empty strings, which Laravel's `nullable` rules would still see.
  Map<String, dynamic> _expenseFields({
    required String description,
    required double amount,
    required DateTime expenseDate,
    required String paymentMethod,
    String? subCategoryId,
    String? pettyCashAccountId,
    String? controlNumber,
    String? reference,
    String? notes,
    String? givenByName,
    String? receivedByName,
  }) => {
    'description': description,
    'amount': amount,
    'expense_date': _ymd(expenseDate),
    'payment_method': paymentMethod,
    'sub_expense_category_id': ?subCategoryId,
    'petty_cash_account_id': ?pettyCashAccountId,
    'control_number': ?controlNumber,
    'reference': ?reference,
    'notes': ?notes,
    'given_by_name': ?givenByName,
    'received_by_name': ?receivedByName,
  };

  /// Multipart POST through the shared client.
  ///
  /// [ApiClient] pins a JSON content type for every ordinary call, so uploads
  /// take its documented `raw` escape hatch. Every interceptor still runs —
  /// bearer token, 401 handling, error shaping — only the body encoding
  /// differs, and failures are re-thrown as [ApiException] so no screen has to
  /// import Dio. A null [filePath] simply posts the fields, which is what an
  /// edit that keeps its existing receipt needs.
  Future<Map<String, dynamic>> _multipart(
    String path,
    Map<String, dynamic> fields, {
    String? filePath,
    String fileField = 'attachment',
    UploadProgress? onProgress,
  }) async {
    // Multipart carries text, not JSON types: a double would otherwise be
    // encoded by Dio's default `toString` anyway, so be explicit about it.
    final form = FormData.fromMap({
      for (final entry in fields.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    });
    if (filePath != null) {
      form.files.add(
        MapEntry(fileField, await MultipartFile.fromFile(filePath)),
      );
    }

    try {
      final response = await _api.raw.post<Map<String, dynamic>>(
        path,
        data: form,
        onSendProgress: onProgress,
      );
      return response.data ?? const {};
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// Authenticated byte download, for the PDFs the server generates on demand.
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

  /// The `message` from an endpoint that answers flat rather than wrapped in
  /// `data` — every destroy route does — so the screen can show what the
  /// server actually said.
  Future<String?> _message(Future<dynamic> Function() request) async {
    final body = await request();
    return body is Map ? body['message'] as String? : null;
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class FinancePermissions {
  static const expensesRead = 'expenses.read';
  static const expensesCreate = 'expenses.create';
  static const expensesUpdate = 'expenses.update';
  static const expensesDelete = 'expenses.delete';
  static const expensesApprove = 'expenses.approve';
  static const expenseCategoriesRead = 'expense_categories.read';
  static const expenseCategoriesCreate = 'expense_categories.create';
  static const expenseCategoriesUpdate = 'expense_categories.update';
  static const expenseCategoriesDelete = 'expense_categories.delete';
  static const pettyCashRead = 'petty_cash.read';
  static const pettyCashTopup = 'petty_cash.topup';
  static const pettyCashReconcile = 'petty_cash.reconcile';
  static const pettyCashDelete = 'petty_cash.delete';
  static const statutoriesRead = 'statutories.read';
  static const billsRead = 'bills.read';
  static const billsCreate = 'bills.create';
  static const billsUpdate = 'bills.update';
  static const billsDelete = 'bills.delete';
}
