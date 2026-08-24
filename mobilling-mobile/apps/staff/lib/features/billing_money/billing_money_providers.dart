import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<BillingMoneyService> billingMoneyServiceProvider =
    Provider<BillingMoneyService>(
      (ref) => BillingMoneyService(ref.watch(apiClientProvider)),
    );

/// The tenant's configured payment methods. Not autoDisposed — it is read by
/// two different forms and never changes during a session.
final FutureProvider<List<TenantPaymentMethod>> paymentMethodsProvider =
    FutureProvider<List<TenantPaymentMethod>>(
      (ref) => ref.watch(billingMoneyServiceProvider).paymentMethods(),
    );

final AutoDisposeFutureProvider<List<NextBill>> nextBillsProvider =
    FutureProvider.autoDispose<List<NextBill>>(
      (ref) => ref.watch(billingMoneyServiceProvider).nextBills(),
    );
