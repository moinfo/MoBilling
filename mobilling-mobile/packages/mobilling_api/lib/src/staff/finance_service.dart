import '../api_client.dart';
import '../paginated.dart';
import 'billing_money_models.dart' show StaffBill;
import 'finance_models.dart';

/// Money going out: expenses (with the petty-cash approval flow), the petty
/// cash float, statutory obligations and recurring bills.
///
/// Notes:
///   * Expenses attach to a **sub**-category, never a parent category.
///   * `file` uploads (expense attachment, expense voucher, petty-cash
///     transaction voucher) are all omitted — they need multipart plus a file
///     picker, which `apps/staff` has not wired. Everything else on those
///     endpoints works.
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
  }) =>
      _api.post<dynamic>('/expenses', body: {
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
      });

  /// POST /expenses/{id}/approve — needs `expenses.approve`.
  Future<void> approveExpense(String id) =>
      _api.post<dynamic>('/expenses/$id/approve');

  /// POST /expenses/{id}/reject — a reason is what the approver owes the
  /// person who submitted it.
  Future<void> rejectExpense(String id, {required String reason}) =>
      _api.post<dynamic>('/expenses/$id/reject', body: {'reason': reason});

  /// GET /expense-categories — parents with their sub-categories nested.
  Future<List<ExpenseCategory>> expenseCategories() async {
    final body =
        await _api.get<dynamic>('/expense-categories');
    return Paginated.fromJson(body, ExpenseCategory.fromJson).items;
  }

  /// POST /expense-categories — a parent when [parentId] is null, otherwise a
  /// sub-category.
  Future<void> createExpenseCategory({
    required String name,
    String? parentId,
  }) =>
      _api.post<dynamic>('/expense-categories',
          body: {'name': name, 'expense_category_id': ?parentId});

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
  }) =>
      _api.post<dynamic>('/petty-cash/transactions', body: {
        'type': type,
        'amount': amount,
        'transaction_date': _ymd(transactionDate),
        'notes': ?notes,
      });

  /// POST /petty-cash/reconciliations — record a physical cash count. Needs
  /// `petty_cash.reconcile`. [resolution] is `accepted` (book the
  /// difference as an adjustment) or `investigating` (leave the ledger as
  /// is and flag it).
  Future<void> reconcilePettyCash({
    required double countedBalance,
    required String resolution,
    String? notes,
  }) =>
      _api.post<dynamic>('/petty-cash/reconciliations', body: {
        'counted_balance': countedBalance,
        'resolution': resolution,
        'notes': ?notes,
      });

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
    final body =
        await _api.get<Map<String, dynamic>>('/statutory-schedule');
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
  }) =>
      _api.post<dynamic>('/bill-categories', body: {
        'name': name,
        'parent_id': ?parentId,
        'billing_cycle': ?billingCycle,
      });

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class FinancePermissions {
  static const expensesRead = 'expenses.read';
  static const expensesCreate = 'expenses.create';
  static const expensesApprove = 'expenses.approve';
  static const expenseCategoriesRead = 'expense_categories.read';
  static const expenseCategoriesCreate = 'expense_categories.create';
  static const pettyCashRead = 'petty_cash.read';
  static const pettyCashTopup = 'petty_cash.topup';
  static const pettyCashReconcile = 'petty_cash.reconcile';
  static const statutoriesRead = 'statutories.read';
  static const billsRead = 'bills.read';
  static const billsCreate = 'bills.create';
}
