import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<FinanceService> financeServiceProvider = Provider<FinanceService>(
  (ref) => FinanceService(ref.watch(apiClientProvider)),
);

/// Category tree — read by both the expense list (for names) and the record
/// form (for the sub-category picker), so it is not autoDisposed.
final FutureProvider<List<ExpenseCategory>> expenseCategoriesProvider =
    FutureProvider<List<ExpenseCategory>>(
  (ref) => ref.watch(financeServiceProvider).expenseCategories(),
);

final AutoDisposeFutureProvider<PettyCash> pettyCashProvider =
    FutureProvider.autoDispose<PettyCash>(
  (ref) => ref.watch(financeServiceProvider).pettyCash(),
);

final AutoDisposeFutureProvider<StatutorySchedule> statutoryScheduleProvider =
    FutureProvider.autoDispose<StatutorySchedule>(
  (ref) => ref.watch(financeServiceProvider).statutorySchedule(),
);

final AutoDisposeFutureProvider<List<BillCategory>> billCategoriesProvider =
    FutureProvider.autoDispose<List<BillCategory>>(
  (ref) => ref.watch(financeServiceProvider).billCategories(),
);
