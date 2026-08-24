import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

/// Providers for the client-portal shell.
///
/// Every name here is `portal`-prefixed on purpose: this file and the staff
/// app's `providers.dart` are imported side by side by the portal screens, and
/// three names would otherwise collide outright (dashboard, tickets, ticket)
/// with the staff equivalents that return completely different types.

final Provider<PortalService> portalServiceProvider = Provider<PortalService>(
  (ref) => PortalService(ref.watch(apiClientProvider)),
);

/// Which bottom tab the portal shell is showing.
///
/// Lifted out of the shell's own State so the dashboard can send someone to
/// their invoices — the counters and the overdue warning are the two things
/// on that screen people try to tap, and both were inert while this was
/// private.
final StateProvider<int> portalTabProvider = StateProvider<int>((ref) => 0);

/// Tab indices, named so a caller never has to remember that 1 is invoices.
abstract final class PortalTab {
  static const int home = 0;
  static const int invoices = 1;
  static const int services = 2;
  static const int support = 3;
  static const int more = 4;
}

/// Dashboard payload. autoDispose so it refetches when the user navigates
/// back after being away, rather than showing stale figures forever.
final AutoDisposeFutureProvider<PortalDashboard> portalDashboardProvider =
    FutureProvider.autoDispose<PortalDashboard>(
      (ref) => ref.watch(portalServiceProvider).dashboard(),
    );

/// Full invoice detail, keyed by document id.
final AutoDisposeFutureProviderFamily<PortalDocument, String>
portalDocumentProvider = FutureProvider.autoDispose
    .family<PortalDocument, String>(
      (ref, id) => ref.watch(portalServiceProvider).document(id),
    );

/// Tickets, open first (the endpoint is unpaginated).
final AutoDisposeFutureProvider<List<PortalTicket>> portalTicketsProvider =
    FutureProvider.autoDispose<List<PortalTicket>>(
      (ref) => ref.watch(portalServiceProvider).tickets(),
    );

/// One ticket with its reply thread.
final AutoDisposeFutureProviderFamily<PortalTicket, String>
portalTicketProvider = FutureProvider.autoDispose.family<PortalTicket, String>(
  (ref, id) => ref.watch(portalServiceProvider).ticket(id),
);

final AutoDisposeFutureProvider<List<Announcement>>
portalAnnouncementsProvider = FutureProvider.autoDispose<List<Announcement>>(
  (ref) => ref.watch(portalServiceProvider).announcements(),
);

/// Knowledgebase categories, keyed by search term (null = everything).
final AutoDisposeFutureProviderFamily<List<KbCategory>, String?>
portalKnowledgebaseProvider = FutureProvider.autoDispose
    .family<List<KbCategory>, String?>(
      (ref, search) =>
          ref.watch(portalServiceProvider).knowledgebase(search: search),
    );

final AutoDisposeFutureProviderFamily<KbArticle, String>
portalKbArticleProvider = FutureProvider.autoDispose.family<KbArticle, String>(
  (ref, slug) => ref.watch(portalServiceProvider).kbArticle(slug),
);

final AutoDisposeFutureProvider<List<ClientSubscription>>
portalSubscriptionsProvider =
    FutureProvider.autoDispose<List<ClientSubscription>>(
      (ref) => ref.watch(portalServiceProvider).subscriptions(),
    );

final AutoDisposeFutureProvider<List<HostingAccount>> portalHostingProvider =
    FutureProvider.autoDispose<List<HostingAccount>>(
      (ref) => ref.watch(portalServiceProvider).hostingAccounts(),
    );

final AutoDisposeFutureProviderFamily<HostingDetail, String>
portalHostingDetailProvider = FutureProvider.autoDispose
    .family<HostingDetail, String>(
      (ref, id) => ref.watch(portalServiceProvider).hostingAccount(id),
    );

final AutoDisposeFutureProvider<DomainList> portalDomainsProvider =
    FutureProvider.autoDispose<DomainList>(
      (ref) => ref.watch(portalServiceProvider).domains(),
    );

final AutoDisposeFutureProviderFamily<DomainDetail, String>
portalDomainDetailProvider = FutureProvider.autoDispose
    .family<DomainDetail, String>(
      (ref, id) => ref.watch(portalServiceProvider).domain(id),
    );

/// Reseller membership, wallet balance and wholesale pricing.
///
/// Readable by every portal client — a non-member gets `is_reseller: false`
/// and the membership price, which is what the join screen is built from.
final AutoDisposeFutureProvider<ResellerStatus> portalResellerStatusProvider =
    FutureProvider.autoDispose<ResellerStatus>(
      (ref) => ref.watch(portalServiceProvider).resellerStatus(),
    );

final AutoDisposeFutureProvider<PortalProfile> portalProfileProvider =
    FutureProvider.autoDispose<PortalProfile>(
      (ref) => ref.watch(portalServiceProvider).profile(),
    );

final AutoDisposeFutureProvider<List<PortalUser>> portalUsersProvider =
    FutureProvider.autoDispose<List<PortalUser>>(
      (ref) => ref.watch(portalServiceProvider).portalUsers(),
    );

final AutoDisposeFutureProvider<CreditWallet> portalCreditProvider =
    FutureProvider.autoDispose<CreditWallet>(
      (ref) => ref.watch(portalServiceProvider).credit(),
    );

final AutoDisposeFutureProvider<List<CatalogGroup>> portalCatalogProvider =
    FutureProvider.autoDispose<List<CatalogGroup>>(
      (ref) => ref.watch(portalServiceProvider).catalog(),
    );

final AutoDisposeFutureProviderFamily<List<ProductAddon>, String>
portalProductAddonsProvider = FutureProvider.autoDispose
    .family<List<ProductAddon>, String>(
      (ref, productId) =>
          ref.watch(portalServiceProvider).productAddons(productId),
    );

final AutoDisposeFutureProviderFamily<List<ConfigOptionGroup>, String>
portalConfigOptionsProvider = FutureProvider.autoDispose
    .family<List<ConfigOptionGroup>, String>(
      (ref, productId) =>
          ref.watch(portalServiceProvider).configOptions(productId),
    );

/// The TLDs this tenant sells, with retail pricing. Drives the price list on
/// the domain search screen — without it a client has to guess which
/// extensions are on offer before the availability check can tell them
/// anything.
final AutoDisposeFutureProvider<List<TldPricing>> portalTldsProvider =
    FutureProvider.autoDispose<List<TldPricing>>(
      (ref) => ref.watch(portalServiceProvider).tlds(),
    );

final AutoDisposeFutureProvider<List<DomainAddon>> portalDomainAddonsProvider =
    FutureProvider.autoDispose<List<DomainAddon>>(
      (ref) => ref.watch(portalServiceProvider).domainAddons(),
    );

/// Statement for an optional date window. Keyed by the (start, end) pair so
/// switching ranges caches each window separately.
final AutoDisposeFutureProviderFamily<Statement, ({String? start, String? end})>
portalStatementProvider = FutureProvider.autoDispose
    .family<Statement, ({String? start, String? end})>(
      (ref, range) => ref
          .watch(portalServiceProvider)
          .statement(startDate: range.start, endDate: range.end),
    );
