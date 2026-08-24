import '../api_client.dart';
import '../paginated.dart';
import 'admin_models.dart' show PermissionCatalogue, PermissionInfo, StaffUser;
import 'platform_models.dart';

/// The platform super-admin area (`/admin/*`, behind `EnsureSuperAdmin`).
///
/// Everything here is cross-tenant by definition, so no call takes or implies
/// a tenant scope except where a tenant id is an explicit argument.
class PlatformService {
  const PlatformService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------

  Future<PlatformDashboard> dashboard() async {
    final body = await _api.get<dynamic>('/admin/dashboard');
    return PlatformDashboard.fromJson(body);
  }

  // ---------------------------------------------------------------------
  // Tenants
  // ---------------------------------------------------------------------

  Future<Paginated<PlatformTenant>> tenants({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/admin/tenants',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(_unwrapPage(body), PlatformTenant.fromJson);
  }

  Future<PlatformTenant> tenant(String id) async {
    final body = await _api.get<dynamic>('/admin/tenants/$id');
    return PlatformTenant.fromJson(_unwrap(body));
  }

  /// PATCH /admin/tenants/{id}/toggle-active — suspends or restores a whole
  /// tenant; every one of their users is locked out at login.
  Future<void> toggleTenantActive(String id) =>
      _api.patch<dynamic>('/admin/tenants/$id/toggle-active');

  /// GET /admin/tenants/{id}/users.
  Future<List<StaffUser>> tenantUsers(String tenantId) async {
    final body = await _api.get<dynamic>('/admin/tenants/$tenantId/users');
    return Paginated.fromJson(body, StaffUser.fromJson).items;
  }

  Future<void> toggleTenantUserActive(String tenantId, String userId) => _api
      .patch<dynamic>('/admin/tenants/$tenantId/users/$userId/toggle-active');

  /// GET /admin/tenants/{id}/subscriptions — their payment records.
  Future<List<TenantSubscriptionRecord>> tenantSubscriptions(
    String tenantId,
  ) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/tenants/$tenantId/subscriptions',
    );
    return Paginated.fromJson(body, TenantSubscriptionRecord.fromJson).items;
  }

  /// POST /admin/tenants/{id}/subscriptions/extend — grant time directly,
  /// the manual counterpart to a paid renewal.
  Future<void> extendSubscription(
    String tenantId, {
    required int days,
    String? notes,
  }) => _api.post<dynamic>(
    '/admin/tenants/$tenantId/subscriptions/extend',
    body: {'days': days, 'notes': ?notes},
  );

  /// POST /admin/subscriptions/{id}/confirm-payment — accept an uploaded
  /// proof and activate the subscription.
  Future<void> confirmSubscriptionPayment(String subscriptionId) => _api
      .post<dynamic>('/admin/subscriptions/$subscriptionId/confirm-payment');

  // ---------------------------------------------------------------------
  // Tenant management: create, edit, promote-from-client, impersonation and
  // permission grants — web parity for `mobilling-ui/src/pages/admin/Tenants.tsx`
  // and `TenantProfile.tsx`.
  // ---------------------------------------------------------------------

  Future<PlatformTenant> createTenant({
    required String name,
    required String email,
    String? phone,
    String? address,
    String? taxId,
    String? currency,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/tenants',
      body: {
        'name': name,
        'email': email,
        'phone': ?phone,
        'address': ?address,
        'tax_id': ?taxId,
        'currency': ?currency,
        'admin_name': adminName,
        'admin_email': adminEmail,
        'admin_password': adminPassword,
      },
    );
    return PlatformTenant.fromJson(_unwrap(body));
  }

  /// PUT /admin/tenants/{id} — never touches the tenant's admin user; there is
  /// no admin-account fields here to match, same as the web's `TenantForm` in
  /// edit mode.
  Future<PlatformTenant> updateTenant(
    String id, {
    required String name,
    required String email,
    String? phone,
    String? address,
    String? taxId,
    String? currency,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/admin/tenants/$id',
      body: {
        'name': name,
        'email': email,
        'phone': ?phone,
        'address': ?address,
        'tax_id': ?taxId,
        'currency': ?currency,
      },
    );
    return PlatformTenant.fromJson(_unwrap(body));
  }

  /// GET /admin/clients/search — cross-tenant, unlike the regular `/clients`
  /// which is scoped to the caller's own tenant (a super admin has none).
  /// The controller itself refuses anything under two characters.
  Future<List<ClientSearchResult>> searchClients(String search) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/clients/search',
      query: {'search': search},
    );
    final data = body['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map(
                (e) =>
                    ClientSearchResult.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : const [];
  }

  /// POST /admin/tenants/promote-from-client — spins an existing client out
  /// into its own independent, white-label tenant. Nothing about the
  /// originating client moves; see `TenantController::promoteFromClient`.
  Future<PlatformTenant> promoteClientToTenant({
    required String clientId,
    required String name,
    required String email,
    String? phone,
    String? address,
    String? taxId,
    String? currency,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/tenants/promote-from-client',
      body: {
        'client_id': clientId,
        'name': name,
        'email': email,
        'phone': ?phone,
        'address': ?address,
        'tax_id': ?taxId,
        'currency': ?currency,
        'admin_name': adminName,
        'admin_email': adminEmail,
        'admin_password': adminPassword,
      },
    );
    return PlatformTenant.fromJson(_unwrap(body));
  }

  /// POST /admin/tenants/{id}/impersonate — mints a token for that tenant's
  /// active admin. Returns the raw response (`{user, token,
  /// subscription_status, days_remaining}`, no `user_type` and no
  /// `permissions`) rather than a typed model: turning it into a session is
  /// `mobilling_auth`'s job, and this package does not depend on that one.
  Future<Map<String, dynamic>> impersonateTenant(String tenantId) =>
      _api.post<Map<String, dynamic>>('/admin/tenants/$tenantId/impersonate');

  /// POST /admin/tenants/{id}/users/{user}/impersonate — same shape, for one
  /// specific user of the tenant rather than its admin.
  Future<Map<String, dynamic>> impersonateTenantUser(
    String tenantId,
    String userId,
  ) => _api.post<Map<String, dynamic>>(
    '/admin/tenants/$tenantId/users/$userId/impersonate',
  );

  /// GET /admin/tenants/{id}/permissions — the ids currently enabled for this
  /// tenant, a subset of the full catalogue [permissions] returns.
  Future<List<String>> tenantPermissionIds(String tenantId) async {
    final body = await _api.get<dynamic>(
      '/admin/tenants/$tenantId/permissions',
    );
    final data = body is Map ? body['data'] : body;
    return data is List ? data.map((e) => e.toString()).toList() : const [];
  }

  /// PUT /admin/tenants/{id}/permissions — replaces the tenant's whole
  /// allowed set. The server also strips any of the tenant's own role
  /// permissions that fall outside it.
  Future<String?> updateTenantPermissions(
    String tenantId,
    List<String> permissionIds,
  ) => _message(
    () => _api.put<dynamic>(
      '/admin/tenants/$tenantId/permissions',
      body: {'permission_ids': permissionIds},
    ),
  );

  // ---------------------------------------------------------------------
  // Per-tenant settings
  // ---------------------------------------------------------------------

  Future<TenantEmailSettings> tenantEmailSettings(String tenantId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/tenants/$tenantId/email-settings',
    );
    return TenantEmailSettings.fromJson(body);
  }

  Future<void> updateTenantEmailSettings(
    String tenantId, {
    required bool emailEnabled,
    String? fromName,
    String? fromAddress,
    String? host,
    int? port,
    String? username,
    String? password,
    String? encryption,
  }) => _api.put<dynamic>(
    '/admin/tenants/$tenantId/email-settings',
    body: {
      'email_enabled': emailEnabled,
      'smtp_from_name': ?fromName,
      'smtp_from_address': ?fromAddress,
      'smtp_host': ?host,
      'smtp_port': ?port,
      'smtp_username': ?username,
      'smtp_password': ?password,
      'smtp_encryption': ?encryption,
    },
  );

  /// POST .../email-settings/test — sends a real message, so it is the only
  /// honest way to know the SMTP details work.
  Future<String?> testTenantEmail(String tenantId, {String? to}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/tenants/$tenantId/email-settings/test',
      body: {'to': ?to},
    );
    return body['message']?.toString();
  }

  Future<TenantSmsSettings> tenantSmsSettings(String tenantId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/tenants/$tenantId/sms-settings',
    );
    return TenantSmsSettings.fromJson(body);
  }

  Future<void> updateTenantSmsSettings(
    String tenantId, {
    required bool smsEnabled,
    String? senderId,
    String? authorization,
  }) => _api.put<dynamic>(
    '/admin/tenants/$tenantId/sms-settings',
    body: {
      'sms_enabled': smsEnabled,
      'sms_sender_id': ?senderId,
      'sms_authorization': ?authorization,
    },
  );

  /// Credit adjustments. Recharge adds messages, deduct removes them —
  /// separate endpoints rather than a signed amount, so an accidental sign
  /// flip cannot silently drain a tenant's balance.
  Future<void> rechargeSms(String tenantId, int quantity, {String? notes}) =>
      _api.post<dynamic>(
        '/admin/tenants/$tenantId/sms-recharge',
        body: {'quantity': quantity, 'notes': ?notes},
      );

  Future<void> deductSms(String tenantId, int quantity, {String? notes}) =>
      _api.post<dynamic>(
        '/admin/tenants/$tenantId/sms-deduct',
        body: {'quantity': quantity, 'notes': ?notes},
      );

  Future<List<TenantTemplate>> tenantTemplates(String tenantId) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/tenants/$tenantId/templates',
    );
    return Paginated.fromJson(body, TenantTemplate.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Catalog: plans, currencies, SMS packages
  // ---------------------------------------------------------------------

  Future<List<PlatformPlan>> plans() async {
    final body = await _api.get<dynamic>('/admin/subscription-plans');
    return Paginated.fromJson(_unwrapPage(body), PlatformPlan.fromJson).items;
  }

  Future<void> savePlan({
    String? id,
    required String name,
    required double price,
    String? billingCycle,
    int? durationDays,
    bool isActive = true,
  }) {
    final body = {
      'name': name,
      'price': price,
      'billing_cycle': ?billingCycle,
      'duration_days': ?durationDays,
      'is_active': isActive,
    };
    return id == null
        ? _api.post<dynamic>('/admin/subscription-plans', body: body)
        : _api.put<dynamic>('/admin/subscription-plans/$id', body: body);
  }

  Future<List<PlatformCurrency>> currencies() async {
    final body = await _api.get<dynamic>('/admin/currencies');
    return Paginated.fromJson(
      _unwrapPage(body),
      PlatformCurrency.fromJson,
    ).items;
  }

  Future<void> saveCurrency({
    String? id,
    required String code,
    String? name,
    String? symbol,
    bool isActive = true,
  }) {
    final body = {
      'code': code,
      'name': ?name,
      'symbol': ?symbol,
      'is_active': isActive,
    };
    return id == null
        ? _api.post<dynamic>('/admin/currencies', body: body)
        : _api.put<dynamic>('/admin/currencies/$id', body: body);
  }

  Future<List<SmsPackage>> smsPackages() async {
    final body = await _api.get<dynamic>('/admin/sms-packages');
    return Paginated.fromJson(_unwrapPage(body), SmsPackage.fromJson).items;
  }

  Future<void> saveSmsPackage({
    String? id,
    required String name,
    required int smsCount,
    required double price,
    bool isActive = true,
  }) {
    final body = {
      'name': name,
      'sms_count': smsCount,
      'price': price,
      'is_active': isActive,
    };
    return id == null
        ? _api.post<dynamic>('/admin/sms-packages', body: body)
        : _api.put<dynamic>('/admin/sms-packages/$id', body: body);
  }

  Future<Paginated<PlatformSmsPurchase>> smsPurchases({
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/admin/sms-purchases',
      query: {'status': status, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(_unwrapPage(body), PlatformSmsPurchase.fromJson);
  }

  // ---------------------------------------------------------------------
  // Permissions, role templates, platform settings
  // ---------------------------------------------------------------------

  /// The permission catalogue every tenant role is built from.
  ///
  /// `TenantPermissionController::allPermissions` is registered inside the
  /// `/admin` prefix group — the bare `/permissions` this called until now
  /// 404d every time the screen opened. (The tenant-scoped route editor uses
  /// a different endpoint, `/available-permissions`, in `admin_service.dart`
  /// — same nested shape, which is why [PermissionCatalogue] already knows
  /// how to read it.)
  Future<List<PermissionInfo>> permissions() async {
    final body = await _api.get<dynamic>('/admin/permissions');
    return PermissionCatalogue.fromJson(
      body is Map<String, dynamic> ? body : <String, dynamic>{},
    ).all;
  }

  /// Role templates — the starting roles a new tenant is seeded with.
  Future<List<RoleTemplate>> roleTemplates() async {
    final body = await _api.get<dynamic>('/admin/role-templates');
    return Paginated.fromJson(body, RoleTemplate.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Role templates — edit support (RoleTemplateController::show/update)
  //
  // Kept in its own clearly-marked section, next to [roleTemplates] above,
  // since other work lands nearby in this file at the same time.
  // ---------------------------------------------------------------------

  /// GET /admin/role-templates/{type} — the full permission catalogue for one
  /// template plus which ids it currently grants, for the edit checklist.
  Future<RoleTemplateDetail> roleTemplateDetail(String type) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/role-templates/$type',
    );
    return RoleTemplateDetail.fromJson(body);
  }

  /// PUT /admin/role-templates/{type} — syncs the permission set for every
  /// tenant's system role of this type at once ("Changes apply to all
  /// tenants", per the web's confirm copy). Only `admin` and `user` accept
  /// writes; `super_admin` 422s. Returns the confirmation message, which
  /// names how many tenants were updated.
  Future<String?> updateRoleTemplate(
    String type,
    List<String> permissionIds,
  ) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/admin/role-templates/$type',
      body: {'permission_ids': permissionIds},
    );
    return body['message']?.toString();
  }

  Future<PlatformSettings> platformSettings() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/platform-settings',
    );
    return PlatformSettings.fromJson(body);
  }

  Future<void> updatePlatformSettings(Map<String, String> values) =>
      _api.put<dynamic>('/admin/platform-settings', body: values);

  // ---------------------------------------------------------------------
  // Self-hosted licensing: licenses, their pricing catalog, and releases
  // ---------------------------------------------------------------------

  /// A short list, not an infinite scroll — self-hosted licensing is a rare
  /// workflow, so one generous page covers it (the web equally never expects
  /// more than a couple of screens' worth).
  Future<List<License>> licenses({String? search}) async {
    final body = await _api.get<dynamic>(
      '/admin/licenses',
      query: {'search': search, 'per_page': 100},
    );
    return Paginated.fromJson(_unwrapPage(body), License.fromJson).items;
  }

  Future<License> createLicense({
    required String customerName,
    required String customerEmail,
    String product = LicensePackages.general,
    required DateTime startsAt,
    required String billingPeriod,
    double? amountPaid,
    String? notes,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/licenses',
      body: {
        'customer_name': customerName,
        'customer_email': customerEmail,
        'product': product,
        'starts_at': _ymd(startsAt),
        'billing_period': billingPeriod,
        // Omitted (not null) when blank, so the server falls back to the
        // license-plans catalog price — see LicenseController::store.
        'amount_paid': ?amountPaid,
        'notes': ?notes,
      },
    );
    return License.fromJson(_unwrap(body));
  }

  /// Edits customer/status/notes, or — when [startsAt] and [billingPeriod]
  /// are both given — renews by recalculating `expires_at` from them (the
  /// same endpoint the web's Renew action uses).
  Future<License> updateLicense(
    String id, {
    required String customerName,
    required String customerEmail,
    required String status,
    String? product,
    DateTime? startsAt,
    String? billingPeriod,
    double? amountPaid,
    String? notes,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/admin/licenses/$id',
      body: {
        'customer_name': customerName,
        'customer_email': customerEmail,
        'status': status,
        'product': ?product,
        'starts_at': startsAt == null ? null : _ymd(startsAt),
        'billing_period': ?billingPeriod,
        'amount_paid': ?amountPaid,
        'notes': ?notes,
      },
    );
    return License.fromJson(_unwrap(body));
  }

  /// Clears the bound domain so the license can activate on a different
  /// install — the activation history goes with it.
  Future<License> unbindLicenseDomain(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/licenses/$id/unbind-domain',
    );
    return License.fromJson(_unwrap(body));
  }

  Future<String?> deleteLicense(String id) =>
      _message(() => _api.delete<dynamic>('/admin/licenses/$id'));

  /// Rows are seeded, one per [LicensePackages] value — this only ever reads
  /// and edits prices, never creates or deletes.
  Future<List<LicensePlan>> licensePlans() async {
    final body = await _api.get<dynamic>('/admin/license-plans');
    return Paginated.fromJson(body, LicensePlan.fromJson).items;
  }

  Future<LicensePlan> updateLicensePlan(
    String id, {
    required String name,
    String? description,
    double? monthlyPrice,
    double? quarterlyPrice,
    double? semiAnnualPrice,
    double? annualPrice,
    double? perpetualPrice,
    bool isActive = true,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/admin/license-plans/$id',
      body: {
        'name': name,
        'description': ?description,
        'monthly_price': monthlyPrice,
        'quarterly_price': quarterlyPrice,
        'semi_annual_price': semiAnnualPrice,
        'annual_price': annualPrice,
        'perpetual_price': perpetualPrice,
        'is_active': isActive,
      },
    );
    return LicensePlan.fromJson(_unwrap(body));
  }

  /// The "Check for Updates" catalog self-hosted installs compare their
  /// version against.
  Future<List<Release>> releases() async {
    final body = await _api.get<dynamic>('/admin/releases');
    return Paginated.fromJson(body, Release.fromJson).items;
  }

  Future<Release> createRelease({
    required String version,
    String? changelog,
    String? downloadUrl,
    required DateTime releasedAt,
    bool isActive = true,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/admin/releases',
      body: {
        'version': version,
        'changelog': ?changelog,
        'download_url': ?downloadUrl,
        'released_at': _ymd(releasedAt),
        'is_active': isActive,
      },
    );
    return Release.fromJson(_unwrap(body));
  }

  Future<Release> updateRelease(
    String id, {
    required String version,
    String? changelog,
    String? downloadUrl,
    required DateTime releasedAt,
    bool isActive = true,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/admin/releases/$id',
      body: {
        'version': version,
        'changelog': ?changelog,
        'download_url': ?downloadUrl,
        'released_at': _ymd(releasedAt),
        'is_active': isActive,
      },
    );
    return Release.fromJson(_unwrap(body));
  }

  Future<String?> deleteRelease(String id) =>
      _message(() => _api.delete<dynamic>('/admin/releases/$id'));

  /// The `message` from an endpoint that answers flat rather than wrapped in
  /// `data` — every destroy route does — so the screen can show what the
  /// server actually said.
  Future<String?> _message(Future<dynamic> Function() request) async {
    final body = await request();
    return body is Map ? body['message'] as String? : null;
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }

  /// apiResource endpoints return the paginator at the top level; a few of the
  /// hand-written ones nest it under `data`. Accept either.
  Map<String, dynamic> _unwrapPage(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map && data.containsKey('current_page')) {
      return Map<String, dynamic>.from(data);
    }
    return body;
  }
}
