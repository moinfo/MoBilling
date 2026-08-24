import '../api_client.dart';
import '../paginated.dart';
import 'hosting_service_models.dart';
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
///   * **`/hosting-services`** is the billing side of the same thing and keys
///     off the client_subscription id, on `client_subscriptions.*`. Its
///     responses are `{"data": {...}}` objects, not paginators.
class SupportAdminService {
  const SupportAdminService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Canned replies
  // ---------------------------------------------------------------------

  /// GET /canned-replies — readable with `tickets.reply`.
  Future<List<CannedReply>> cannedReplies() async {
    final body = await _api.get<dynamic>('/canned-replies');
    return Paginated.fromJson(body, CannedReply.fromJson).items;
  }

  /// POST /canned-replies — needs `tickets.manage`.
  Future<void> createCannedReply({
    required String title,
    required String body,
  }) => _api.post<dynamic>(
    '/canned-replies',
    body: {'title': title, 'body': body},
  );

  /// PUT /canned-replies/{id}.
  Future<void> updateCannedReply(
    String id, {
    required String title,
    required String body,
  }) => _api.put<dynamic>(
    '/canned-replies/$id',
    body: {'title': title, 'body': body},
  );

  /// DELETE /canned-replies/{id}.
  Future<void> deleteCannedReply(String id) =>
      _api.delete<dynamic>('/canned-replies/$id');

  // ---------------------------------------------------------------------
  // Announcements
  // ---------------------------------------------------------------------

  /// GET /announcements — includes drafts (staff view).
  Future<List<StaffAnnouncement>> announcements() async {
    final body = await _api.get<dynamic>('/announcements');
    return Paginated.fromJson(body, StaffAnnouncement.fromJson).items;
  }

  /// POST /announcements. Publishing stamps `published_at` server-side.
  Future<void> createAnnouncement({
    required String title,
    required String body,
    bool isPublished = false,
  }) => _api.post<dynamic>(
    '/announcements',
    body: {'title': title, 'body': body, 'is_published': isPublished},
  );

  /// PUT /announcements/{id} — also the publish/unpublish action.
  Future<void> updateAnnouncement(
    String id, {
    required String title,
    required String body,
    required bool isPublished,
  }) => _api.put<dynamic>(
    '/announcements/$id',
    body: {'title': title, 'body': body, 'is_published': isPublished},
  );

  Future<void> deleteAnnouncement(String id) =>
      _api.delete<dynamic>('/announcements/$id');

  // ---------------------------------------------------------------------
  // Knowledgebase
  // ---------------------------------------------------------------------

  /// GET /kb/categories — with article counts.
  Future<List<StaffKbCategory>> kbCategories() async {
    final body = await _api.get<dynamic>('/kb/categories');
    return Paginated.fromJson(body, StaffKbCategory.fromJson).items;
  }

  Future<void> createKbCategory({
    required String name,
    String? description,
    bool isActive = true,
  }) => _api.post<dynamic>(
    '/kb/categories',
    body: {'name': name, 'description': ?description, 'is_active': isActive},
  );

  Future<void> updateKbCategory(
    String id, {
    required String name,
    String? description,
    required bool isActive,
  }) => _api.put<dynamic>(
    '/kb/categories/$id',
    body: {'name': name, 'description': ?description, 'is_active': isActive},
  );

  Future<void> deleteKbCategory(String id) =>
      _api.delete<dynamic>('/kb/categories/$id');

  /// GET /kb/articles — all articles, optionally one category's.
  Future<List<StaffKbArticle>> kbArticles({String? categoryId}) async {
    final body = await _api.get<dynamic>(
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
  }) => _api.post<dynamic>(
    '/kb/articles',
    body: {
      'title': title,
      'body': body,
      'kb_category_id': ?categoryId,
      'is_published': isPublished,
    },
  );

  Future<void> updateKbArticle(
    String id, {
    required String title,
    required String body,
    String? categoryId,
    required bool isPublished,
  }) => _api.put<dynamic>(
    '/kb/articles/$id',
    body: {
      'title': title,
      'body': body,
      'kb_category_id': ?categoryId,
      'is_published': isPublished,
    },
  );

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
    final body = await _api.get<dynamic>(
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
    final body = await _api.get<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/logs',
    );
    return Paginated.fromJson(body, ProvisioningLogEntry.fromJson).items;
  }

  /// POST /hosting-accounts/{id}/suspend — needs `hosting.suspend`.
  Future<void> suspendHosting(String accountId, {String? reason}) =>
      _api.post<dynamic>(
        '/hosting-accounts/$accountId/suspend',
        body: {'reason': ?reason},
      );

  Future<void> unsuspendHosting(String accountId) =>
      _api.post<dynamic>('/hosting-accounts/$accountId/unsuspend');

  /// POST /hosting-accounts/{id}/refresh-usage — re-read disk from cPanel.
  Future<void> refreshHostingUsage(String accountId) =>
      _api.post<dynamic>('/hosting-accounts/$accountId/refresh-usage');

  /// POST /hosting-accounts/{id}/sso — a one-time cPanel login URL.
  Future<String> hostingSsoUrl(String accountId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/sso',
    );
    return body['url']?.toString() ?? '';
  }

  /// POST /hosting-accounts/{id}/terminate — needs `hosting.terminate`.
  ///
  /// Irreversible: the queued job deletes the cPanel account and everything
  /// on it. Answers 202 with a message, because the WHM call happens on the
  /// queue rather than in the request.
  Future<String?> terminateHosting(String accountId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/terminate',
    );
    return body['message']?.toString();
  }

  /// POST /hosting-accounts/{id}/change-package — needs
  /// `hosting.change_package`. [package] is the WHM package name, which must
  /// match the server's spelling exactly; also queued, so 202 + message.
  ///
  /// The package list itself lives behind `GET /servers/{server}/packages`,
  /// which needs `hosting.settings` and a server id the list rows do not
  /// carry — callers ask staff to type the name.
  Future<String?> changeHostingPackage(String accountId, String package) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/change-package',
      body: {'package': package},
    );
    return body['message']?.toString();
  }

  /// POST /hosting-accounts/{id}/password — set the cPanel password on the
  /// server. Needs `hosting.change_package`. [password] must be at least 8
  /// characters or the API rejects it. Synchronous: a 422 here means WHM
  /// itself refused the password.
  ///
  /// The client is notified that the password changed; the password is never
  /// part of that notice.
  Future<String?> changeHostingPassword(
    String accountId,
    String password,
  ) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/password',
      body: {'password': password},
    );
    return body['message']?.toString();
  }

  /// POST /hosting-accounts/{id}/reset-welcome — the server generates a new
  /// cPanel password and sends the client the welcome message carrying it.
  /// Needs `hosting.change_package`.
  ///
  /// The response also echoes the generated password; it is deliberately not
  /// returned — the client's welcome message is the delivery channel, and
  /// staff have no reason to hold it. Only the message comes back.
  Future<String?> resetHostingWelcome(String accountId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/$accountId/reset-welcome',
    );
    return body['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Hosting services — the admin Products/Services tab
  // ---------------------------------------------------------------------
  //
  // These key off the **client_subscription**, not the hosting account: the
  // subscription is the billing record and exists whether or not anything was
  // ever provisioned. The module commands above (suspend, terminate, change
  // package/password) act on the account the subscription links to, so a
  // service with `hostingAccount == null` can be edited but not commanded.

  /// GET /hosting-services?client_id= — one client's services, newest first.
  /// Needs `client_subscriptions.read`. Not paginated: the controller maps a
  /// plain collection into `{"data": [...]}`.
  Future<List<ClientServiceRow>> clientServices(String clientId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/hosting-services',
      query: {'client_id': clientId},
    );
    final data = body['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => ClientServiceRow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET /hosting-services/{clientSubscription} — the edit form's record plus
  /// the option lists its selects are built from.
  Future<HostingServiceDetail> hostingService(String subscriptionId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/hosting-services/$subscriptionId');
    return HostingServiceDetail.fromJson(_unwrap(body));
  }

  /// PUT /hosting-services/{clientSubscription} — needs
  /// `client_subscriptions.update`. Returns the saved record, so the form can
  /// re-seed itself from what the server actually stored.
  ///
  /// Every nullable field is sent even when null: the controller clears
  /// `dedicated_ip`, `termination_date`, `payment_method` and `promo_code` by
  /// key presence, so omitting a key would silently keep the old value.
  ///
  /// [recalculate] re-derives the recurring amount from the product's current
  /// price × quantity and ignores [recurringAmount] — the two are mutually
  /// exclusive on the server, so a form offering both must disable the field.
  Future<HostingServiceDetail> updateHostingService(
    String subscriptionId, {
    required String productServiceId,
    required String status,
    required int quantity,
    String? domain,
    String? dedicatedIp,
    String? username,
    String? package,
    String? serverId,
    DateTime? startDate,
    double? firstPaymentAmount,
    double? recurringAmount,
    DateTime? nextDueDate,
    DateTime? terminationDate,
    String? paymentMethod,
    String? promoCode,
    bool recalculate = false,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/hosting-services/$subscriptionId',
      body: {
        'product_service_id': productServiceId,
        'status': status,
        'quantity': quantity,
        'domain': domain,
        'dedicated_ip': dedicatedIp,
        'username': username,
        'package': package,
        'server_id': serverId,
        'start_date': startDate == null ? null : _ymd(startDate),
        'first_payment_amount': firstPaymentAmount,
        'recurring_amount': recurringAmount,
        'next_due_date': nextDueDate == null ? null : _ymd(nextDueDate),
        'termination_date':
            terminationDate == null ? null : _ymd(terminationDate),
        'payment_method': paymentMethod,
        'promo_code': promoCode,
        'recalculate': recalculate,
      },
    );
    return HostingServiceDetail.fromJson(_unwrap(body));
  }

  /// GET /hosting-services/{clientSubscription}/upgrade-options.
  ///
  /// 422s rather than returning an empty list when the service has no product,
  /// or is still billed in WHMCS during parallel operation — the message is
  /// the explanation to show.
  Future<ServiceUpgradeOptions> serviceUpgradeOptions(
      String subscriptionId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/hosting-services/$subscriptionId/upgrade-options',
    );
    return ServiceUpgradeOptions.fromJson(_unwrap(body));
  }

  /// POST /hosting-services/{clientSubscription}/upgrade — needs
  /// `client_subscriptions.update`.
  ///
  /// `mode: 'invoice'` raises the prorated invoice and the plan switches when
  /// it is paid; `mode: 'immediate'` switches now with no charge. A change
  /// that costs nothing is applied immediately whichever mode is asked for.
  Future<ServiceUpgradeResult> applyServiceUpgrade(
    String subscriptionId, {
    required String productServiceId,
    required String mode,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-services/$subscriptionId/upgrade',
      body: {'product_service_id': productServiceId, 'mode': mode},
    );
    return ServiceUpgradeResult.fromJson(body);
  }

  /// POST /hosting-services/{clientSubscription}/resend-welcome — the welcome
  /// message again, without a password. Needs `client_subscriptions.update`.
  Future<String?> resendServiceWelcome(String subscriptionId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-services/$subscriptionId/resend-welcome',
    );
    return body['message']?.toString();
  }

  /// POST /hosting-services/{clientSubscription}/send-message — a free-form
  /// email to the client under the tenant's branding. The API caps [subject]
  /// at 255 characters and [body] at 20 000.
  Future<String?> sendServiceMessage(
    String subscriptionId, {
    required String subject,
    required String body,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      '/hosting-services/$subscriptionId/send-message',
      body: {'subject': subject, 'body': body},
    );
    return response['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Domains
  // ---------------------------------------------------------------------

  /// GET /domains — tenant-wide. [expiring] applies the 45-day window and
  /// sorts by expiry. [ours] narrows to live domains the registry confirms are
  /// sponsored by our own registrar handle ('1') or to everything else ('0').
  Future<Paginated<StaffDomain>> domains({
    String? status,
    String? search,
    bool? expiring,
    String? ours,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/domains',
      query: {
        'status': status,
        'search': search,
        'expiring': expiring == true ? 1 : null,
        'ours': ours,
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
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// PUT /domains/{id}/auto-renew — needs `domains.renew`.
  Future<void> setDomainAutoRenew(String domainId, bool enabled) =>
      _api.put<dynamic>(
        '/domains/$domainId/auto-renew',
        body: {'enabled': enabled},
      );

  /// GET /domains/{id}/nameservers.
  Future<StaffNameservers> domainNameservers(String domainId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/domains/$domainId/nameservers',
    );
    final data = body['data'];
    return StaffNameservers.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  /// PUT /domains/{id}/nameservers — needs `domains.manage_dns`.
  Future<void> updateDomainNameservers(
    String domainId,
    List<String> nameservers,
  ) => _api.put<dynamic>(
    '/domains/$domainId/nameservers',
    body: {'nameservers': nameservers},
  );

  /// GET /domains/{id}/auth-info — the EPP transfer code. Needs
  /// `domains.transfer`.
  Future<String> domainAuthInfo(String domainId) async {
    final body = await _api.get<dynamic>('/domains/$domainId/auth-info');
    return body['auth_info']?.toString() ??
        (body['data'] is Map
            ? (body['data'] as Map)['auth_info']?.toString() ?? ''
            : '');
  }

  /// GET /domains/{id} — one domain with its client, registrar account and
  /// subscription. Fresher than the list row, which is why the actions sheet
  /// re-reads it after a renew or a retry.
  Future<StaffDomain> domain(String domainId) async {
    final body = await _api.get<Map<String, dynamic>>('/domains/$domainId');
    return StaffDomain.fromJson(_unwrap(body));
  }

  /// GET /domains/{id}/logs — the registry log, newest 50 entries. Returns a
  /// bare list under `data`, not a paginator.
  Future<List<StaffDomainLog>> domainLogs(String domainId) async {
    final body = await _api.get<dynamic>('/domains/$domainId/logs');
    return Paginated.fromJson(body, StaffDomainLog.fromJson).items;
  }

  /// POST /domains/{id}/renew — creates the renewal invoice. Nothing happens
  /// at the registry until it is paid, and the renewal then draws real prepaid
  /// registrar credit. [years] is 1–10; needs `domains.renew`.
  Future<String?> renewDomain(String domainId, int years) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/domains/$domainId/renew',
      body: {'years': years},
    );
    return body['message']?.toString();
  }

  /// POST /domains/{id}/retry — re-run the register/transfer/renew that
  /// failed. No new invoice; the client already paid for the original order.
  /// 422 unless the domain is `failed` with a recorded pending action. Needs
  /// `domains.create`.
  Future<String?> retryDomain(String domainId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/domains/$domainId/retry',
    );
    return body['message']?.toString();
  }

  /// GET /domains/whois — a live port-43 lookup at the TZNIC registry. 422 for
  /// anything that is not a .tz name.
  Future<StaffWhoisResult> domainWhois(String name) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/domains/whois',
      query: {'name': name},
    );
    return StaffWhoisResult.fromJson(_unwrap(body));
  }

  /// GET /domains/registrar-credit — prepaid TZNIC balance per zone, plus the
  /// funded zones running low. Cached 5 minutes server-side.
  Future<StaffRegistrarCredit> registrarCredit() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/domains/registrar-credit',
    );
    return StaffRegistrarCredit.fromJson(_unwrap(body));
  }

  /// POST /domains/add-existing — record a domain that is already registered
  /// so it shows under a client for renewal tracking. Bookkeeping only: no
  /// invoice, no EPP call. [registrar] is `tznic` or `external`; `tznic` only
  /// marks it as one of ours, it does not take over sponsorship at the
  /// registry. Needs `domains.create`.
  Future<String?> addExistingDomain({
    required String name,
    required String clientId,
    required String registrar,
    DateTime? expiresAt,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/domains/add-existing',
      body: {
        'name': name,
        'client_id': clientId,
        'registrar': registrar,
        'expires_at': ?(expiresAt == null ? null : _ymd(expiresAt)),
        'notes': ?notes,
      },
    );
    return body['message']?.toString();
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

  /// `{"data": {...}}` from the hosting-service endpoints. Falls back to the
  /// body itself so an unwrapped variant still parses.
  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  /// The API takes dates as Y-m-d; an ISO timestamp would be re-interpreted in
  /// UTC and land a day early in a non-UTC zone.
  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class SupportAdminPermissions {
  static const ticketsReply = 'tickets.reply';
  static const ticketsManage = 'tickets.manage';
  static const announcementsManage = 'announcements.manage';
  static const hostingRead = 'hosting.read';
  static const hostingSuspend = 'hosting.suspend';
  static const hostingSso = 'hosting.sso';
  static const hostingTerminate = 'hosting.terminate';

  /// Also gates the two password endpoints, not just the package change.
  static const hostingChangePackage = 'hosting.change_package';
  /// The admin Products/Services tab: reading a client's services and their
  /// detail. Distinct from `hosting.read`, which is the server-side view.
  static const clientSubscriptionsRead = 'client_subscriptions.read';

  /// Saving the service form, the plan change, the welcome resend and the
  /// free-form message all share this one.
  static const clientSubscriptionsUpdate = 'client_subscriptions.update';
  static const domainsRead = 'domains.read';

  /// Ordering, adding an existing domain, and retrying a failed registry
  /// action all share this one.
  static const domainsCreate = 'domains.create';
  static const domainsRenew = 'domains.renew';
  static const domainsManageDns = 'domains.manage_dns';
  static const domainsTransfer = 'domains.transfer';
}
