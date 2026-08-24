import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<SupportAdminService> supportAdminServiceProvider =
    Provider<SupportAdminService>(
      (ref) => SupportAdminService(ref.watch(apiClientProvider)),
    );

final AutoDisposeFutureProvider<List<CannedReply>> cannedRepliesProvider =
    FutureProvider.autoDispose<List<CannedReply>>(
      (ref) => ref.watch(supportAdminServiceProvider).cannedReplies(),
    );

final AutoDisposeFutureProvider<List<StaffAnnouncement>>
staffAnnouncementsProvider =
    FutureProvider.autoDispose<List<StaffAnnouncement>>(
      (ref) => ref.watch(supportAdminServiceProvider).announcements(),
    );

final AutoDisposeFutureProvider<List<StaffKbCategory>> kbCategoriesProvider =
    FutureProvider.autoDispose<List<StaffKbCategory>>(
      (ref) => ref.watch(supportAdminServiceProvider).kbCategories(),
    );

/// Articles keyed by category id (null = every article).
final AutoDisposeFutureProviderFamily<List<StaffKbArticle>, String?>
kbArticlesProvider = FutureProvider.autoDispose
    .family<List<StaffKbArticle>, String?>(
      (ref, categoryId) => ref
          .watch(supportAdminServiceProvider)
          .kbArticles(categoryId: categoryId),
    );

final AutoDisposeFutureProvider<StaffDomainStats> domainStatsProvider =
    FutureProvider.autoDispose<StaffDomainStats>(
      (ref) => ref.watch(supportAdminServiceProvider).domainStats(),
    );

/// One domain, freshly read — the actions sheet's source of truth, so a retry
/// or a renew updates the sheet without closing it.
final AutoDisposeFutureProviderFamily<StaffDomain, String> staffDomainProvider =
    FutureProvider.autoDispose.family<StaffDomain, String>(
      (ref, domainId) =>
          ref.watch(supportAdminServiceProvider).domain(domainId),
    );

final AutoDisposeFutureProviderFamily<List<StaffDomainLog>, String>
domainLogsProvider = FutureProvider.autoDispose
    .family<List<StaffDomainLog>, String>(
      (ref, domainId) =>
          ref.watch(supportAdminServiceProvider).domainLogs(domainId),
    );

/// The prepaid registrar balance. The API caches it for five minutes, so this
/// is cheap to watch from the list header.
final AutoDisposeFutureProvider<StaffRegistrarCredit> registrarCreditProvider =
    FutureProvider.autoDispose<StaffRegistrarCredit>(
      (ref) => ref.watch(supportAdminServiceProvider).registrarCredit(),
    );

final AutoDisposeFutureProviderFamily<List<ProvisioningLogEntry>, String>
hostingLogsProvider = FutureProvider.autoDispose
    .family<List<ProvisioningLogEntry>, String>(
      (ref, accountId) =>
          ref.watch(supportAdminServiceProvider).hostingLogs(accountId),
    );
