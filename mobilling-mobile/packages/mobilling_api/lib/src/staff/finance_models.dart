/// Outgoing money: expenses, petty cash, statutory obligations and bills.
///
/// The one concept worth understanding before touching this file is petty
/// cash's **two balances**. `PettyCashAccount::balances()` computes:
///   * `verified` — the official float: opening + top-ups − returns −
///     *approved* expenses.
///   * `committed` — physically remaining cash: verified minus expenses that
///     are still awaiting a signed voucher.
/// The insufficient-funds guard uses `committed`, so that is the number a
/// person about to spend needs to see. Showing only `verified` would let them
/// plan against money already gone from the tin.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Expenses — ExpenseResource
// ---------------------------------------------------------------------------

class Expense {
  const Expense({
    required this.id,
    required this.description,
    required this.amount,
    required this.approvalStatus,
    this.categoryName,
    this.subCategoryName,
    this.subCategoryId,
    this.expenseDate,
    this.paymentMethod,
    this.controlNumber,
    this.reference,
    this.notes,
    this.recordedByName,
    this.approvedByName,
    this.approvedAt,
    this.rejectionReason,
    this.pettyCashAccountId,
    this.hasVoucher = false,
    this.attachmentUrl,
    this.voucherAttachmentUrl,
    this.givenByName,
    this.receivedByName,
  });

  final String id;
  final String description;
  final double amount;

  /// pending | approved | rejected. Petty-cash expenses need an administrator
  /// to approve them before they leave the verified balance.
  final String approvalStatus;
  final String? categoryName;
  final String? subCategoryName;
  final String? subCategoryId;
  final DateTime? expenseDate;
  final String? paymentMethod;
  final String? controlNumber;
  final String? reference;
  final String? notes;
  final String? recordedByName;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? rejectionReason;

  /// Set when this expense was paid out of the petty-cash float.
  final String? pettyCashAccountId;

  /// A signed voucher has been attached — what moves a petty-cash expense from
  /// "committed" to fully settled.
  final bool hasVoucher;

  /// The receipt, if one was attached. Both this and [voucherAttachmentUrl]
  /// are absolute links to the server's **public** disk, so they open in a
  /// browser without a token — unlike the generated voucher PDF, which is
  /// streamed from an authenticated route.
  final String? attachmentUrl;
  final String? voucherAttachmentUrl;

  /// The two names printed on a petty-cash voucher. Carried on the model
  /// because `PUT /expenses/{id}` re-validates every field — an edit that
  /// left these out would silently erase them.
  final String? givenByName;
  final String? receivedByName;

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved';
  bool get isPettyCash => pettyCashAccountId != null;
  bool get hasReceipt => attachmentUrl != null;

  /// Full category path for display: 'Utilities › Electricity'.
  String get categoryPath =>
      [categoryName, subCategoryName].whereType<String>().join(' › ');

  factory Expense.fromJson(Map<String, dynamic> json) {
    final sub = json.object('sub_category');
    return Expense(
      id: json.id(),
      description: json.strOr('description', '—'),
      amount: json.money('amount'),
      approvalStatus: json.strOr('approval_status', 'pending'),
      categoryName: sub?.object('category')?.str('name'),
      subCategoryName: sub?.str('name'),
      subCategoryId: json.str('sub_expense_category_id'),
      expenseDate: json.date('expense_date'),
      paymentMethod: json.str('payment_method'),
      controlNumber: json.str('control_number'),
      reference: json.str('reference'),
      notes: json.str('notes'),
      recordedByName: json.str('recorded_by_name'),
      approvedByName: json.str('approved_by_name'),
      approvedAt: json.date('approved_at'),
      rejectionReason: json.str('rejection_reason'),
      pettyCashAccountId: json.str('petty_cash_account_id'),
      hasVoucher: json.str('voucher_attachment_url') != null,
      attachmentUrl: json.str('attachment_url'),
      voucherAttachmentUrl: json.str('voucher_attachment_url'),
      givenByName: json.str('given_by_name'),
      receivedByName: json.str('received_by_name'),
    );
  }
}

/// A top-level expense category with its sub-categories. Expenses attach to a
/// SUB-category, never the parent.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.subCategories,
  });

  final String id;
  final String name;
  final List<ExpenseSubCategory> subCategories;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        id: json.id(),
        name: json.strOr('name', '—'),
        subCategories: json.list('sub_categories', ExpenseSubCategory.fromJson),
      );
}

class ExpenseSubCategory {
  const ExpenseSubCategory({
    required this.id,
    required this.name,
    this.categoryId,
  });

  final String id;
  final String name;
  final String? categoryId;

  factory ExpenseSubCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseSubCategory(
        id: json.id(),
        name: json.strOr('name', '—'),
        categoryId: json.str('expense_category_id'),
      );
}

// ---------------------------------------------------------------------------
// Petty cash — PettyCashController::index
// ---------------------------------------------------------------------------

class PettyCash {
  const PettyCash({
    required this.accountId,
    required this.accountName,
    required this.verifiedBalance,
    required this.committedBalance,
    required this.pendingVoucherCount,
    required this.pendingVoucherTotal,
    required this.history,
    required this.reconciliations,
    this.openingBalance = 0,
  });

  /// Needed when charging an expense to the float — `StoreExpenseRequest`
  /// validates `petty_cash_account_id` with a tenant-scoped `exists` rule.
  final String accountId;

  final String accountName;

  /// The official float. Expenses leave it once approved.
  final double verifiedBalance;

  /// Physically remaining cash — verified minus expenses still awaiting a
  /// signed voucher. This is what the insufficient-funds guard checks.
  final double committedBalance;

  final int pendingVoucherCount;
  final double pendingVoucherTotal;

  /// Top-ups, returns, adjustments and expenses merged into one timeline by
  /// the server, newest first.
  final List<PettyCashEntry> history;

  final List<PettyCashReconciliation> reconciliations;
  final double openingBalance;

  bool get hasPendingVouchers => pendingVoucherCount > 0;

  factory PettyCash.fromJson(Map<String, dynamic> json) {
    final account = json.object('account');
    final pending = json.object('pending_vouchers');
    return PettyCash(
      accountId: account?.id() ?? '',
      accountName: account?.strOr('name', 'Petty cash') ?? 'Petty cash',
      verifiedBalance: json.money('balance'),
      committedBalance: json.money('committed_balance'),
      pendingVoucherCount: pending?.count('count') ?? 0,
      pendingVoucherTotal: pending?.money('total') ?? 0,
      history: json.list('history', PettyCashEntry.fromJson),
      reconciliations: json.list(
        'reconciliations',
        PettyCashReconciliation.fromJson,
      ),
      openingBalance: account?.money('opening_balance') ?? 0,
    );
  }
}

class PettyCashEntry {
  const PettyCashEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.description,
    this.date,
    this.createdByName,
    this.approvalStatus,
    this.voucherAttached = false,
    this.voucherAttachmentUrl,
  });

  final String id;

  /// top_up | return | adjustment_in | adjustment_out | expense.
  final String kind;
  final double amount;
  final String description;
  final DateTime? date;
  final String? createdByName;

  /// Present on expense rows only.
  final String? approvalStatus;

  /// A signed voucher is on file for this movement.
  final bool voucherAttached;

  /// Absolute link to that signed voucher on the public disk, when there is
  /// one. The *blank* voucher PDF is a separate, authenticated download.
  final String? voucherAttachmentUrl;

  /// Money into the tin versus out of it.
  bool get isInflow => kind == 'top_up' || kind == 'adjustment_in';

  /// Expense rows are the petty-cash side of a row on the Expenses screen;
  /// their voucher belongs to the expense, not to this ledger line.
  bool get isExpense => kind == 'expense';

  /// Only hand-entered movements can be removed. Adjustments are the ledger's
  /// own record of a cash count, and the API refuses to delete them.
  bool get isDeletable => kind == 'top_up' || kind == 'return';

  factory PettyCashEntry.fromJson(Map<String, dynamic> json) => PettyCashEntry(
    id: json.id(),
    kind: json.strOr('kind', 'expense'),
    amount: json.money('amount'),
    description: json.strOr('description', '—'),
    date: json.date('date'),
    // The unified history emits `created_by` as a plain name string.
    createdByName:
        json.str('created_by_name') ??
        json.object('created_by')?.str('name') ??
        (json['created_by'] is String ? json.str('created_by') : null),
    // Expense rows carry `voucher_attached` rather than an approval
    // status; a missing voucher is what still needs attention.
    approvalStatus:
        json.str('approval_status') ??
        (json['voucher_attached'] == null
            ? null
            : (json.flag('voucher_attached') ? null : 'voucher_pending')),
    voucherAttached: json.flag('voucher_attached'),
    voucherAttachmentUrl: json.str('voucher_attachment_url'),
  );
}

class PettyCashReconciliation {
  const PettyCashReconciliation({
    required this.id,
    required this.countedAmount,
    required this.expectedAmount,
    this.reconciledAt,
    this.notes,
    this.createdByName,
  }) : _resolution = null;

  final String id;
  final double countedAmount;
  final double expectedAmount;
  final DateTime? reconciledAt;
  final String? notes;
  final String? createdByName;

  /// Positive means more cash than expected, negative means a shortfall.
  double get variance => countedAmount - expectedAmount;

  /// `accepted | investigating`, when the API sends it.
  String? get resolution => _resolution;
  final String? _resolution;

  factory PettyCashReconciliation.fromJson(Map<String, dynamic> json) =>
      PettyCashReconciliation._(
        id: json.id(),
        // Columns are `counted_balance` / `ledger_balance` (model
        // PettyCashReconciliation); older keys kept as fallbacks.
        countedAmount: json.money(
          'counted_balance',
          fallback: json.money('counted_amount'),
        ),
        expectedAmount: json.money(
          'ledger_balance',
          fallback: json.money('expected_amount'),
        ),
        reconciledAt: json.date('reconciled_at') ?? json.date('created_at'),
        notes: json.str('notes'),
        createdByName:
            json.object('reconciled_by')?.str('name') ??
            json.object('created_by')?.str('name') ??
            json.str('reconciled_by_name'),
        resolution: json.str('resolution'),
      );

  const PettyCashReconciliation._({
    required this.id,
    required this.countedAmount,
    required this.expectedAmount,
    this.reconciledAt,
    this.notes,
    this.createdByName,
    String? resolution,
  }) : _resolution = resolution;
}

// ---------------------------------------------------------------------------
// Statutory obligations — StatutoryResource
// ---------------------------------------------------------------------------

/// A recurring statutory obligation (TRA, NSSF, licences…).
///
/// `status`, `days_remaining` and the payment progress are computed
/// server-side off the *current* bill, so they need no client arithmetic.
class Statutory {
  const Statutory({
    required this.id,
    required this.name,
    required this.amount,
    required this.status,
    required this.daysRemaining,
    required this.paidAmount,
    required this.remainingAmount,
    required this.progressPercent,
    required this.isActive,
    this.categoryName,
    this.cycle,
    this.nextDueDate,
    this.notes,
    this.currentBillId,
  });

  final String id;
  final String name;
  final double amount;

  /// paid | overdue | due_soon | upcoming — server-computed.
  final String status;

  /// Negative once past due.
  final int daysRemaining;
  final double paidAmount;
  final double remainingAmount;
  final double progressPercent;
  final bool isActive;
  final String? categoryName;
  final String? cycle;
  final DateTime? nextDueDate;
  final String? notes;

  /// The bill a payment-out should be recorded against.
  final String? currentBillId;

  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';

  factory Statutory.fromJson(Map<String, dynamic> json) {
    final category = json.object('bill_category');
    final currentBill = json.object('current_bill');
    return Statutory(
      id: json.id(),
      name: json.strOr('name', '—'),
      amount: json.money('amount'),
      status: json.strOr('status', 'upcoming'),
      daysRemaining: json.count('days_remaining'),
      paidAmount: json.money('paid_amount'),
      remainingAmount: json.money('remaining_amount'),
      progressPercent: json.money('progress_percent'),
      isActive: json.flag('is_active', fallback: true),
      categoryName: category == null
          ? null
          : [
              category.str('parent_name'),
              category.str('name'),
            ].whereType<String>().join(' › '),
      cycle: json.str('cycle'),
      nextDueDate: json.date('next_due_date'),
      notes: json.str('notes'),
      currentBillId: currentBill?.str('id'),
    );
  }
}

class StatutoryScheduleStats {
  const StatutoryScheduleStats({
    required this.total,
    required this.overdue,
    required this.dueSoon,
    required this.paid,
  });

  final int total;
  final int overdue;
  final int dueSoon;
  final int paid;

  factory StatutoryScheduleStats.fromJson(Map<String, dynamic> json) =>
      StatutoryScheduleStats(
        total: json.count('total'),
        overdue: json.count('overdue'),
        dueSoon: json.count('due_soon'),
        paid: json.count('paid'),
      );
}

class StatutorySchedule {
  const StatutorySchedule({required this.items, required this.stats});

  final List<Statutory> items;
  final StatutoryScheduleStats stats;

  factory StatutorySchedule.fromJson(Map<String, dynamic> json) =>
      StatutorySchedule(
        items: json.list('data', Statutory.fromJson),
        stats: StatutoryScheduleStats.fromJson(
          json.object('stats') ?? const {},
        ),
      );
}

// ---------------------------------------------------------------------------
// Bill categories — BillCategoryResource
// ---------------------------------------------------------------------------

class BillCategory {
  const BillCategory({
    required this.id,
    required this.name,
    required this.isActive,
    required this.children,
    this.parentId,
    this.billingCycle,
  });

  final String id;
  final String name;
  final bool isActive;

  /// Categories nest one level (parent › child).
  final List<BillCategory> children;
  final String? parentId;
  final String? billingCycle;

  factory BillCategory.fromJson(Map<String, dynamic> json) => BillCategory(
    id: json.id(),
    name: json.strOr('name', '—'),
    isActive: json.flag('is_active', fallback: true),
    children: json.list('children', BillCategory.fromJson),
    parentId: json.str('parent_id'),
    billingCycle: json.str('billing_cycle'),
  );
}
