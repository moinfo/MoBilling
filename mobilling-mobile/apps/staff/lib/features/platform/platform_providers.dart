import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

/// Providers for the platform super-admin shell.
///
/// `platform`-prefixed where a plainer name would collide with the staff or
/// portal equivalents — `plansProvider` already means "the tenant's own plan
/// options" in the admin (tenant-settings) feature.
final Provider<PlatformService> platformServiceProvider =
    Provider<PlatformService>(
      (ref) => PlatformService(ref.watch(apiClientProvider)),
    );

final AutoDisposeFutureProvider<PlatformDashboard> platformDashboardProvider =
    FutureProvider.autoDispose<PlatformDashboard>(
      (ref) => ref.watch(platformServiceProvider).dashboard(),
    );

final AutoDisposeFutureProviderFamily<PlatformTenant, String>
platformTenantProvider = FutureProvider.autoDispose
    .family<PlatformTenant, String>(
      (ref, id) => ref.watch(platformServiceProvider).tenant(id),
    );

final AutoDisposeFutureProviderFamily<List<StaffUser>, String>
tenantUsersProvider = FutureProvider.autoDispose
    .family<List<StaffUser>, String>(
      (ref, tenantId) =>
          ref.watch(platformServiceProvider).tenantUsers(tenantId),
    );

final AutoDisposeFutureProviderFamily<List<TenantSubscriptionRecord>, String>
tenantSubscriptionsProvider = FutureProvider.autoDispose
    .family<List<TenantSubscriptionRecord>, String>(
      (ref, tenantId) =>
          ref.watch(platformServiceProvider).tenantSubscriptions(tenantId),
    );

final AutoDisposeFutureProviderFamily<TenantEmailSettings, String>
tenantEmailSettingsProvider = FutureProvider.autoDispose
    .family<TenantEmailSettings, String>(
      (ref, tenantId) =>
          ref.watch(platformServiceProvider).tenantEmailSettings(tenantId),
    );

final AutoDisposeFutureProviderFamily<TenantSmsSettings, String>
tenantSmsSettingsProvider = FutureProvider.autoDispose
    .family<TenantSmsSettings, String>(
      (ref, tenantId) =>
          ref.watch(platformServiceProvider).tenantSmsSettings(tenantId),
    );

final AutoDisposeFutureProviderFamily<List<TenantTemplate>, String>
tenantTemplatesProvider = FutureProvider.autoDispose
    .family<List<TenantTemplate>, String>(
      (ref, tenantId) =>
          ref.watch(platformServiceProvider).tenantTemplates(tenantId),
    );

final AutoDisposeFutureProvider<List<PlatformPlan>> platformPlansProvider =
    FutureProvider.autoDispose<List<PlatformPlan>>(
      (ref) => ref.watch(platformServiceProvider).plans(),
    );

final AutoDisposeFutureProvider<List<PlatformCurrency>> currenciesProvider =
    FutureProvider.autoDispose<List<PlatformCurrency>>(
      (ref) => ref.watch(platformServiceProvider).currencies(),
    );

final AutoDisposeFutureProvider<List<SmsPackage>> smsPackagesProvider =
    FutureProvider.autoDispose<List<SmsPackage>>(
      (ref) => ref.watch(platformServiceProvider).smsPackages(),
    );

final AutoDisposeFutureProvider<List<PermissionInfo>>
platformPermissionsProvider = FutureProvider.autoDispose<List<PermissionInfo>>(
  (ref) => ref.watch(platformServiceProvider).permissions(),
);

final AutoDisposeFutureProvider<List<StaffRole>> roleTemplatesProvider =
    FutureProvider.autoDispose<List<StaffRole>>(
      (ref) => ref.watch(platformServiceProvider).roleTemplates(),
    );

final AutoDisposeFutureProvider<PlatformSettings> platformSettingsProvider =
    FutureProvider.autoDispose<PlatformSettings>(
      (ref) => ref.watch(platformServiceProvider).platformSettings(),
    );
