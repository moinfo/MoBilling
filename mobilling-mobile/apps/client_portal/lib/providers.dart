import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import 'config/app_config.dart';

/// Secure token storage — one instance so its in-memory cache is shared.
final Provider<TokenStore> tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore());

/// The HTTP client every service is built on.
///
/// There is a deliberate cycle here: [ApiClient] needs a way to read the token
/// and to report 401s, both of which live on [SessionController] — which in
/// turn needs an [ApiClient]. Passing a closure that resolves the session
/// lazily (rather than the object itself) breaks it at *runtime*.
///
/// Every provider in this cycle is annotated with an explicit type because
/// Dart's top-level inference cannot walk a cycle even when the runtime
/// resolution is sound; without the annotations the analyzer reports
/// `top_level_cycle` and every downstream type degrades to `dynamic`.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStoreProvider);

  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenReader: tokens.read,
    onUnauthenticated: (request) =>
        ref.read(sessionControllerProvider).handleUnauthenticated(request),
  );
});

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

/// Owns the signed-in session. Long-lived; never auto-disposed.
final ChangeNotifierProvider<SessionController> sessionControllerProvider =
    ChangeNotifierProvider<SessionController>(
  (ref) => SessionController(
    authService: ref.watch(authServiceProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

/// Narrow view of the session for widgets that only care about status, so a
/// profile change does not rebuild every screen watching for sign-out.
final Provider<SessionStatus> sessionStatusProvider = Provider<SessionStatus>(
  (ref) => ref.watch(sessionControllerProvider).status,
);

final Provider<AuthUser?> currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(sessionControllerProvider).user,
);

final Provider<PortalService> portalServiceProvider = Provider<PortalService>(
  (ref) => PortalService(ref.watch(apiClientProvider)),
);

/// Dashboard payload. autoDispose so it refetches when the user navigates
/// back after being away, rather than showing stale figures forever.
final AutoDisposeFutureProvider<PortalDashboard> dashboardProvider =
    FutureProvider.autoDispose<PortalDashboard>(
  (ref) => ref.watch(portalServiceProvider).dashboard(),
);

/// Full invoice detail, keyed by document id.
final AutoDisposeFutureProviderFamily<PortalDocument, String>
    documentProvider = FutureProvider.autoDispose.family<PortalDocument, String>(
  (ref, id) => ref.watch(portalServiceProvider).document(id),
);

/// Tickets, open first (the endpoint is unpaginated).
final AutoDisposeFutureProvider<List<PortalTicket>> ticketsProvider =
    FutureProvider.autoDispose<List<PortalTicket>>(
  (ref) => ref.watch(portalServiceProvider).tickets(),
);

/// One ticket with its reply thread.
final AutoDisposeFutureProviderFamily<PortalTicket, String> ticketProvider =
    FutureProvider.autoDispose.family<PortalTicket, String>(
  (ref, id) => ref.watch(portalServiceProvider).ticket(id),
);

final AutoDisposeFutureProvider<List<Announcement>> announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>(
  (ref) => ref.watch(portalServiceProvider).announcements(),
);

/// Knowledgebase categories, keyed by search term (null = everything).
final AutoDisposeFutureProviderFamily<List<KbCategory>, String?>
    knowledgebaseProvider =
    FutureProvider.autoDispose.family<List<KbCategory>, String?>(
  (ref, search) => ref.watch(portalServiceProvider).knowledgebase(search: search),
);

final AutoDisposeFutureProviderFamily<KbArticle, String> kbArticleProvider =
    FutureProvider.autoDispose.family<KbArticle, String>(
  (ref, slug) => ref.watch(portalServiceProvider).kbArticle(slug),
);

final AutoDisposeFutureProvider<List<ClientSubscription>>
    subscriptionsProvider =
    FutureProvider.autoDispose<List<ClientSubscription>>(
  (ref) => ref.watch(portalServiceProvider).subscriptions(),
);

final AutoDisposeFutureProvider<List<HostingAccount>> hostingProvider =
    FutureProvider.autoDispose<List<HostingAccount>>(
  (ref) => ref.watch(portalServiceProvider).hostingAccounts(),
);

final AutoDisposeFutureProviderFamily<HostingDetail, String>
    hostingDetailProvider =
    FutureProvider.autoDispose.family<HostingDetail, String>(
  (ref, id) => ref.watch(portalServiceProvider).hostingAccount(id),
);

final AutoDisposeFutureProvider<DomainList> domainsProvider =
    FutureProvider.autoDispose<DomainList>(
  (ref) => ref.watch(portalServiceProvider).domains(),
);

final AutoDisposeFutureProviderFamily<DomainDetail, String>
    domainDetailProvider =
    FutureProvider.autoDispose.family<DomainDetail, String>(
  (ref, id) => ref.watch(portalServiceProvider).domain(id),
);

final AutoDisposeFutureProvider<PortalProfile> profileProvider =
    FutureProvider.autoDispose<PortalProfile>(
  (ref) => ref.watch(portalServiceProvider).profile(),
);

final AutoDisposeFutureProvider<List<PortalUser>> portalUsersProvider =
    FutureProvider.autoDispose<List<PortalUser>>(
  (ref) => ref.watch(portalServiceProvider).portalUsers(),
);

final AutoDisposeFutureProvider<CreditWallet> creditProvider =
    FutureProvider.autoDispose<CreditWallet>(
  (ref) => ref.watch(portalServiceProvider).credit(),
);

final AutoDisposeFutureProvider<List<CatalogGroup>> catalogProvider =
    FutureProvider.autoDispose<List<CatalogGroup>>(
  (ref) => ref.watch(portalServiceProvider).catalog(),
);

final AutoDisposeFutureProviderFamily<List<ProductAddon>, String>
    productAddonsProvider =
    FutureProvider.autoDispose.family<List<ProductAddon>, String>(
  (ref, productId) => ref.watch(portalServiceProvider).productAddons(productId),
);

final AutoDisposeFutureProviderFamily<List<ConfigOptionGroup>, String>
    configOptionsProvider =
    FutureProvider.autoDispose.family<List<ConfigOptionGroup>, String>(
  (ref, productId) => ref.watch(portalServiceProvider).configOptions(productId),
);

final AutoDisposeFutureProvider<List<DomainAddon>> domainAddonsProvider =
    FutureProvider.autoDispose<List<DomainAddon>>(
  (ref) => ref.watch(portalServiceProvider).domainAddons(),
);

/// Statement for an optional date window. Keyed by the (start, end) pair so
/// switching ranges caches each window separately.
final AutoDisposeFutureProviderFamily<Statement, ({String? start, String? end})>
    statementProvider = FutureProvider.autoDispose
        .family<Statement, ({String? start, String? end})>(
  (ref, range) => ref
      .watch(portalServiceProvider)
      .statement(startDate: range.start, endDate: range.end),
);
