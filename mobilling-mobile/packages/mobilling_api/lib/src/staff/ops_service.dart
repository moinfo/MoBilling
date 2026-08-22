import '../api_client.dart';
import '../json.dart';
import '../paginated.dart';
import '../portal/order_models.dart';
import 'ops_models.dart';

/// Tenant operations that arrived with the Aug 2026 web sidebar: active
/// sessions, the portal user directory, cPanel discovery, and staff placing
/// orders on a client's behalf.
class OpsService {
  const OpsService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Active sessions — needs `settings.users`
  // ---------------------------------------------------------------------

  /// GET /sessions — every live token for the tenant's staff and clients,
  /// most recently used first. Filters are applied server-side; the summary
  /// counts always describe the unfiltered set.
  Future<SessionsPage> sessions({
    String? type, // staff | client
    bool? active,
    String? search,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/sessions',
      query: {
        'type': type,
        'status': active == null ? null : (active ? 1 : 0),
        'search': search,
      },
    );
    return SessionsPage.fromJson(body);
  }

  /// DELETE /sessions/{id} — force-logout one session.
  Future<void> revokeSession(String id) => _api.delete<dynamic>('/sessions/$id');

  /// POST /sessions/revoke-inactive — revoke every session on deactivated
  /// accounts, optionally also never-used tokens. Never touches a session on
  /// a genuinely active account. Returns the server's summary message.
  Future<String?> revokeInactiveSessions({bool includeNeverUsed = false}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/sessions/revoke-inactive',
      body: {'include_never_used': includeNeverUsed},
    );
    return body['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Portal user directory — needs `clients.update`
  // ---------------------------------------------------------------------

  /// GET /portal-users — every client's portal logins, paginated and ordered
  /// by last login. The paginator is nested under `data` (one level deeper
  /// than most list endpoints).
  Future<Paginated<PortalUserRow>> portalUsers({
    String? search,
    String? role,
    bool? active,
    int page = 1,
    int perPage = 25,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/portal-users',
      query: {
        'search': search,
        'role': role,
        'is_active': active == null ? null : (active ? 1 : 0),
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body['data'], PortalUserRow.fromJson);
  }

  /// PUT /clients/{client}/portal-users/{user} — name, phone, role, active.
  Future<void> updatePortalUser(
    String clientId,
    String userId, {
    String? name,
    String? phone,
    String? role,
    bool? isActive,
  }) =>
      _api.put<dynamic>('/clients/$clientId/portal-users/$userId', body: {
        'name': ?name,
        'phone': ?phone,
        'role': ?role,
        'is_active': ?isActive,
      });

  /// POST /clients/{client}/portal-password — set a new password for one of
  /// the client's portal logins. Needs `clients.portal_password`.
  Future<String?> resetPortalPassword(
    String clientId, {
    required String portalUserId,
    required String password,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/clients/$clientId/portal-password',
      body: {'password': password, 'portal_user_id': portalUserId},
    );
    return body['message']?.toString();
  }

  /// DELETE /clients/{client}/portal-users/{user}
  Future<void> deletePortalUser(String clientId, String userId) =>
      _api.delete<dynamic>('/clients/$clientId/portal-users/$userId');

  // ---------------------------------------------------------------------
  // cPanel discovery — needs `hosting.read`; import needs `hosting.create`
  // ---------------------------------------------------------------------

  /// GET /hosting-accounts/discover — lists every account on every active
  /// WHM server, live, and marks which ones MoBilling already tracks. Slow
  /// (one WHM call per server); the screen shows it once and filters
  /// client-side where it can.
  Future<DiscoveryResult> discoverAccounts({
    String? serverId,
    String? search,
    bool? imported,
  }) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/hosting-accounts/discover',
      query: {
        'server_id': serverId,
        'search': search,
        'imported': imported == null ? null : (imported ? 1 : 0),
      },
    );
    return DiscoveryResult.fromJson(body);
  }

  /// POST /hosting-accounts/import — link an existing cPanel account to a
  /// client: creates the subscription it never had, then the hosting record.
  /// No WHM write happens. Returns the server's confirmation message.
  Future<String?> importAccount({
    required String serverId,
    required String cpanelUsername,
    required String domain,
    required String clientId,
    required String productServiceId,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/hosting-accounts/import',
      body: {
        'server_id': serverId,
        'cpanel_username': cpanelUsername,
        'domain': domain,
        'client_id': clientId,
        'product_service_id': productServiceId,
      },
    );
    return body['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Orders on a client's behalf — needs `orders.create`
  // ---------------------------------------------------------------------
  //
  // These reuse `PortalOrderController`; the only difference from the client
  // portal is that staff name the client explicitly. The response shapes are
  // therefore the portal ones (`order_models.dart`).

  /// GET /orders/catalog
  Future<List<CatalogGroup>> orderCatalog() async {
    final body = await _api.get<dynamic>('/orders/catalog');
    return Paginated.fromJson(body, CatalogGroup.fromJson).items;
  }

  /// GET /orders/domain-tlds
  Future<List<TldPricing>> orderTlds() async {
    final body = await _api.get<dynamic>('/orders/domain-tlds');
    return Paginated.fromJson(body, TldPricing.fromJson).items;
  }

  /// GET /orders/domain-addons
  Future<List<DomainAddon>> orderDomainAddons() async {
    final body = await _api.get<dynamic>('/orders/domain-addons');
    return Paginated.fromJson(body, DomainAddon.fromJson).items;
  }

  /// GET /orders/products/{id}/addons
  Future<List<ProductAddon>> orderProductAddons(String productId) async {
    final body = await _api.get<dynamic>('/orders/products/$productId/addons');
    return Paginated.fromJson(body, ProductAddon.fromJson).items;
  }

  /// GET /orders/products/{id}/config-options
  Future<List<ConfigOptionGroup>> orderConfigOptions(String productId) async {
    final body =
        await _api.get<dynamic>('/orders/products/$productId/config-options');
    return Paginated.fromJson(body, ConfigOptionGroup.fromJson).items;
  }

  /// POST /orders/coupons/validate
  Future<CouponResult> validateOrderCoupon({
    required String clientId,
    required String code,
    required String productId,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/orders/coupons/validate',
      body: {
        'client_id': clientId,
        'code': code,
        'product_service_id': productId,
      },
    );
    return CouponResult.fromJson(body);
  }

  /// POST /orders — place a product order for [clientId]. Creates the
  /// pending subscription and its invoice; paying the invoice activates.
  Future<PlacedOrder> placeOrder({
    required String clientId,
    required String productId,
    String? label,
    String? domainMode,
    String? authInfo,
    int? years,
    List<String> domainAddonIds = const [],
    List<String> productAddonIds = const [],
    List<ConfigSelection> configOptions = const [],
    String? couponCode,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/orders',
      body: {
        'client_id': clientId,
        'product_service_id': productId,
        'label': ?label,
        'domain_mode': ?domainMode,
        'auth_info': ?authInfo,
        'years': ?years,
        if (domainAddonIds.isNotEmpty) 'addons': domainAddonIds,
        if (productAddonIds.isNotEmpty) 'product_addon_ids': productAddonIds,
        if (configOptions.isNotEmpty)
          'config_options': configOptions.map((c) => c.toJson()).toList(),
        'coupon_code': ?couponCode,
      },
    );
    return PlacedOrder.fromJson(body);
  }

  /// POST /domains/order — a standalone domain registration/transfer for a
  /// client. Needs `domains.create`. The registry action fires when the
  /// invoice is paid.
  Future<PlacedOrder> orderDomain({
    required String clientId,
    required String name,
    required int years,
    required String action, // register | transfer
    String? authInfo,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/domains/order',
      body: {
        'client_id': clientId,
        'name': name,
        'years': years,
        'action': action,
        'auth_info': ?authInfo,
      },
    );
    // Unlike /orders, this endpoint puts the domain under `data` and the
    // invoice under `document`.
    final document = body['document'];
    final doc = document is Map
        ? Map<String, dynamic>.from(document)
        : const <String, dynamic>{};
    return PlacedOrder(
      documentId: doc.id(),
      documentNumber: doc.strOr('document_number', '—'),
      total: doc.money('total'),
      message: body['message']?.toString(),
    );
  }
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class OpsPermissions {
  static const settingsUsers = 'settings.users';
  static const clientsUpdate = 'clients.update';
  static const portalPassword = 'clients.portal_password';
  static const hostingCreate = 'hosting.create';
  static const ordersCreate = 'orders.create';
  static const domainsCreate = 'domains.create';
}
