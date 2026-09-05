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

/// Cron logs for one day (null = every run on file).
final AutoDisposeFutureProviderFamily<Paginated<CronLogEntry>, String?>
cronLogsProvider = FutureProvider.autoDispose
    .family<Paginated<CronLogEntry>, String?>(
      (ref, date) => ref.watch(adminServiceProvider).cronLogs(date: date),
    );

/// The forecast window (days ahead) for Upcoming Reminders.
final AutoDisposeFutureProviderFamily<List<ReminderForecastEvent>, int>
upcomingRemindersProvider = FutureProvider.autoDispose
    .family<List<ReminderForecastEvent>, int>(
      (ref, days) =>
          ref.watch(adminServiceProvider).upcomingReminders(days: days),
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

/// GET/PUT /settings/reminders — needs `settings.reminders`.
final AutoDisposeFutureProvider<ReminderSettings> reminderSettingsProvider =
    FutureProvider.autoDispose<ReminderSettings>(
      (ref) => ref.watch(adminServiceProvider).reminderSettings(),
    );

/// GET/PUT /settings/templates — needs `settings.templates`.
final AutoDisposeFutureProvider<MessageTemplates> messageTemplatesProvider =
    FutureProvider.autoDispose<MessageTemplates>(
      (ref) => ref.watch(adminServiceProvider).templates(),
    );

/// GET/PUT /settings/payment-methods — needs `settings.payment_methods`.
final AutoDisposeFutureProvider<PaymentMethodsSettings>
paymentMethodsSettingsProvider = FutureProvider.autoDispose<PaymentMethodsSettings>(
  (ref) => ref.watch(adminServiceProvider).paymentMethods(),
);

/// GET/PUT /settings/late-fee — gated on `settings.reminders`, not its own
/// permission (a confirmed backend quirk).
final AutoDisposeFutureProvider<LateFeeSettings> lateFeeSettingsProvider =
    FutureProvider.autoDispose<LateFeeSettings>(
      (ref) => ref.watch(adminServiceProvider).lateFeeSettings(),
    );

/// One staff member's HR profile, keyed by user id.
final AutoDisposeFutureProviderFamily<EmployeeProfilePage, String>
employeeProfileProvider = FutureProvider.autoDispose
    .family<EmployeeProfilePage, String>(
      (ref, userId) => ref.watch(adminServiceProvider).employeeProfile(userId),
    );
