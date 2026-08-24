import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<AdminService> adminServiceProvider = Provider<AdminService>(
  (ref) => AdminService(ref.watch(apiClientProvider)),
);

final AutoDisposeFutureProvider<TenantSubscription>
currentSubscriptionProvider = FutureProvider.autoDispose<TenantSubscription>(
  (ref) => ref.watch(adminServiceProvider).currentSubscription(),
);

final AutoDisposeFutureProvider<List<SubscriptionPlan>> plansProvider =
    FutureProvider.autoDispose<List<SubscriptionPlan>>(
      (ref) => ref.watch(adminServiceProvider).plans(),
    );

final AutoDisposeFutureProvider<List<SubscriptionHistoryEntry>>
subscriptionHistoryProvider =
    FutureProvider.autoDispose<List<SubscriptionHistoryEntry>>(
      (ref) => ref.watch(adminServiceProvider).subscriptionHistory(),
    );

/// Automation digest keyed by date (null = today).
final AutoDisposeFutureProviderFamily<AutomationSummary, String?>
automationSummaryProvider = FutureProvider.autoDispose
    .family<AutomationSummary, String?>(
      (ref, date) =>
          ref.watch(adminServiceProvider).automationSummary(date: date),
    );

final AutoDisposeFutureProvider<List<CronLogEntry>> cronLogsProvider =
    FutureProvider.autoDispose<List<CronLogEntry>>(
      (ref) => ref.watch(adminServiceProvider).cronLogs(),
    );

final AutoDisposeFutureProvider<List<StaffRole>> rolesProvider =
    FutureProvider.autoDispose<List<StaffRole>>(
      (ref) => ref.watch(adminServiceProvider).roles(),
    );

/// The permission catalogue the role editor picks from. Kept out of
/// [rolesProvider] so the list still renders when this one fails.
final AutoDisposeFutureProvider<PermissionCatalogue>
availablePermissionsProvider = FutureProvider.autoDispose<PermissionCatalogue>(
  (ref) => ref.watch(adminServiceProvider).availablePermissions(),
);

/// Whether the signed-in account has an authenticator app attached.
final AutoDisposeFutureProvider<TwoFactorStatus> twoFactorStatusProvider =
    FutureProvider.autoDispose<TwoFactorStatus>(
      (ref) => ref.watch(adminServiceProvider).twoFactorStatus(),
    );

final AutoDisposeFutureProvider<CompanySettings> companySettingsProvider =
    FutureProvider.autoDispose<CompanySettings>(
      (ref) => ref.watch(adminServiceProvider).companySettings(),
    );

final AutoDisposeFutureProvider<List<BankAccount>> bankAccountsProvider =
    FutureProvider.autoDispose<List<BankAccount>>(
      (ref) async =>
          (await ref.watch(adminServiceProvider).bankAccounts()).items,
    );
