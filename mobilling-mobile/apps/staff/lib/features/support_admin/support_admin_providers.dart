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
    kbArticlesProvider =
    FutureProvider.autoDispose.family<List<StaffKbArticle>, String?>(
  (ref, categoryId) =>
      ref.watch(supportAdminServiceProvider).kbArticles(categoryId: categoryId),
);

final AutoDisposeFutureProvider<StaffDomainStats> domainStatsProvider =
    FutureProvider.autoDispose<StaffDomainStats>(
  (ref) => ref.watch(supportAdminServiceProvider).domainStats(),
);

final AutoDisposeFutureProviderFamily<List<ProvisioningLogEntry>, String>
    hostingLogsProvider =
    FutureProvider.autoDispose.family<List<ProvisioningLogEntry>, String>(
  (ref, accountId) =>
      ref.watch(supportAdminServiceProvider).hostingLogs(accountId),
);
