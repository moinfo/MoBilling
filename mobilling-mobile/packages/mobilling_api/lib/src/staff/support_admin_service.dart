import '../api_client.dart';
import '../paginated.dart';
import 'support_admin_models.dart';

/// Staff-side support content and service administration.
///
/// Route-shape notes:
///   * Staff hosting lives at **`/hosting-accounts`**, not `/hosting` (that is
///     the portal prefix), and there is **no show route** — the list row plus
///     `/logs` is everything the API offers per account.
///   * `/hosting-accounts` and `/domains` return
///     `{"data": {<Laravel paginator>}}` — the paginator is nested one level
///     deeper than usual, so [_page] unwraps before parsing.
///   * Knowledgebase management is gated on `announcements.manage`, the same
///     permission as announcements, and lives under `/kb/*`.
class SupportAdminService {
  const SupportAdminService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Canned replies
  // ---------------------------------------------------------------------

  /// GET /canned-replies — readable with `tickets.reply`.
  Future<List<CannedReply>> cannedReplies() async {
    final body = await _api.get<Map<String, dynamic>>('/canned-replies');
    return Paginated.fromJson(body, CannedReply.fromJson).items;
  }

  /// POST /canned-replies — needs `tickets.manage`.
  Future<void> createCannedReply({
    required String title,
    required String body,
  }) =>
      _api.post<dynamic>('/canned-replies',
          body: {'title': title, 'body': body});

  /// PUT /canned-replies/{id}.
  Future<void> updateCannedReply(
    String id, {
    required String title,
    required String body,
  }) =>
      _api.put<dynamic>('/canned-replies/$id',
          body: {'title': title, 'body': body});

  /// DELETE /canned-replies/{id}.
  Future<void> deleteCannedReply(String id) =>
      _api.delete<dynamic>('/canned-replies/$id');

  // ---------------------------------------------------------------------
  // Announcements
  // ---------------------------------------------------------------------

  /// GET /announcements — includes drafts (staff view).
  Future<List<StaffAnnouncement>> announcements() async {
    final body = await _api.get<Map<String, dynamic>>('/announcements');
    return Paginated.fromJson(body, StaffAnnouncement.fromJson).items;
  }

  /// POST /announcements. Publishing stamps `published_at` server-side.
  Future<void> createAnnouncement({
    required String title,
    required String body,
    bool isPublished = false,
  }) =>
      _api.post<dynamic>('/announcements', body: {
        'title': title,
        'body': body,
        'is_published': isPublished,
      });

  /// PUT /announcements/{id} — also the publish/unpublish action.
  Future<void> updateAnnouncement(
    String id, {
    required String title,
    required String body,
    required bool isPublished,
  }) =>
      _api.put<dynamic>('/announcements/$id', body: {
        'title': title,
        'body': body,
        'is_published': isPublished,
      });

  Future<void> deleteAnnouncement(String id) =>
      _api.delete<dynamic>('/announcements/$id');

  // ---------------------------------------------------------------------
  // Knowledgebase
  // ---------------------------------------------------------------------

  /// GET /kb/categories — with article counts.
  Future<List<StaffKbCategory>> kbCategories() async {
    final body = await _api.get<Map<String, dynamic>>('/kb/categories');
    return Paginated.fromJson(body, StaffKbCategory.fromJson).items;
  }

  Future<void> createKbCategory({
    required String name,
    String? description,
    bool isActive = true,
  }) =>
      _api.post<dynamic>('/kb/categories', body: {
        'name': name,
        'description': ?description,
        'is_active': isActive,
      });

  Future<void> updateKbCategory(
    String id, {
    required String name,
    String? description,
    required bool isActive,
  }) =>
      _api.put<dynamic>('/kb/categories/$id', body: {
        'name': name,
        'description': ?description,
        'is_active': isActive,
      });

  Future<void> deleteKbCategory(String id) =>
      _api.delete<dynamic>('/kb/categories/$id');

  /// GET /kb/articles — all articles, optionally one category's.
  Future<List<StaffKbArticle>> kbArticles({String? categoryId}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/kb/articles',
      query: {'category_id': categoryId},
    );
    return Paginated.fromJson(body, StaffKbArticle.fromJson).items;
  }

  Future<void> createKbArticle({
    required String title,
    required String body,
    String? categoryId,
    bool isPublished = false,
  }) =>
      _api.post<dynamic>('/kb/articles', body: {
        'title': title,
        'body': body,
        'kb_category_id': ?categoryId,
        'is_published': isPublished,
      });

  Future<void> updateKbArticle(
    String id, {
    required String title,
    required String body,
    String? categoryId,
    required bool isPublished,
  }) =>
      _api.put<dynamic>('/kb/articles/$id', body: {
        'title': title,
        'body': body,
        'kb_category_id': ?categoryId,
        'is_published': isPublished,
      });

  Future<void> deleteKbArticle(String id) =>
      _api.delete<dynamic>('/kb/articles/$id');

  // ---------------------------------------------------------------------
  // Hosting accounts
  // ---------------------------------------------------------------------

  /// GET /hosting-accounts — tenant-wide, searchable by domain or cPanel user.
  Future<Paginated<StaffHostingAccount>> hostingAccounts({
    String? status,
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/hosting-accounts',
      query: {
        'status': status,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return _page(body, StaffHostingAccount.fromJson);
  }

  /// GET /hosting-accounts/{id}/logs — provisioning history.
  Future<List<ProvisioningLogEntry>> hostingLogs(String accountId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/hosting-accounts/$accountId/logs');
    return Paginated.fromJson(body, ProvisioningLogEntry.fromJson).items;
  }

  /// POST /hosting-accounts/{id}/suspend — needs `hosting.suspend`.
  Future<void> suspendHosting(String accountId, {String? reason}) =>
      _api.post<dynamic>('/hosting-accounts/$accountId/suspend',
          body: {'reason': ?reason});

  Future<void> unsuspendHosting(String accountId) =>
      _api.post<dynamic>('/hosting-accounts/$accountId/unsuspend');

  /// POST /hosting-accounts/{id}/refresh-usage — re-read disk from cPanel.
  Future<void> refreshHostingUsage(String accountId) =>
      _api.post<dynamic>('/hosting-accounts/$accountId/refresh-usage');

  /// POST /hosting-accounts/{id}/sso — a one-time cPanel login URL.
  Future<String> hostingSsoUrl(String accountId) async {
    final body =
        await _api.post<Map<String, dynamic>>('/hosting-accounts/$accountId/sso');
    return body['url']?.toString() ?? '';
  }

  // ---------------------------------------------------------------------
  // Domains
  // ---------------------------------------------------------------------

  /// GET /domains — tenant-wide. [expiring] applies the 45-day window and
  /// sorts by expiry.
  Future<Paginated<StaffDomain>> domains({
    String? status,
    String? search,
    bool? expiring,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/domains',
      query: {
        'status': status,
        'search': search,
        'expiring': expiring == true ? 1 : null,
        'page': page,
        'per_page': perPage,
      },
    );
    return _page(body, StaffDomain.fromJson);
  }

  /// GET /domains/stats — status counters for the header.
  Future<StaffDomainStats> domainStats() async {
    final body = await _api.get<Map<String, dynamic>>('/domains/stats');
    final data = body['data'];
    return StaffDomainStats.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : body);
  }

  /// PUT /domains/{id}/auto-renew — needs `domains.renew`.
  Future<void> setDomainAutoRenew(String domainId, bool enabled) =>
      _api.put<dynamic>('/domains/$domainId/auto-renew',
          body: {'enabled': enabled});

  /// GET /domains/{id}/nameservers.
  Future<StaffNameservers> domainNameservers(String domainId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/domains/$domainId/nameservers');
    final data = body['data'];
    return StaffNameservers.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : body);
  }

  /// PUT /domains/{id}/nameservers — needs `domains.manage_dns`.
  Future<void> updateDomainNameservers(
          String domainId, List<String> nameservers) =>
      _api.put<dynamic>('/domains/$domainId/nameservers',
          body: {'nameservers': nameservers});

  /// GET /domains/{id}/auth-info — the EPP transfer code. Needs
  /// `domains.transfer`.
  Future<String> domainAuthInfo(String domainId) async {
    final body =
        await _api.get<Map<String, dynamic>>('/domains/$domainId/auth-info');
    return body['auth_info']?.toString() ??
        (body['data'] is Map
            ? (body['data'] as Map)['auth_info']?.toString() ?? ''
            : '');
  }

  /// These two endpoints wrap their paginator in `data`, one level deeper than
  /// the rest of the API.
  Paginated<T> _page<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final data = body['data'];
    return Paginated.fromJson(data is Map ? data : body, fromJson);
  }
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class SupportAdminPermissions {
  static const ticketsReply = 'tickets.reply';
  static const ticketsManage = 'tickets.manage';
  static const announcementsManage = 'announcements.manage';
  static const hostingRead = 'hosting.read';
  static const hostingSuspend = 'hosting.suspend';
  static const hostingSso = 'hosting.sso';
  static const domainsRead = 'domains.read';
  static const domainsRenew = 'domains.renew';
  static const domainsManageDns = 'domains.manage_dns';
  static const domainsTransfer = 'domains.transfer';
}
