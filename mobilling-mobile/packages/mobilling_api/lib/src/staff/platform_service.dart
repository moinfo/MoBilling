import '../api_client.dart';
import '../paginated.dart';
import 'admin_models.dart' show PermissionInfo, StaffRole, StaffUser;
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
    final body = await _api.get<Map<String, dynamic>>('/admin/dashboard');
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
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/tenants',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(_unwrapPage(body), PlatformTenant.fromJson);
  }

  Future<PlatformTenant> tenant(String id) async {
    final body =
        await _api.get<Map<String, dynamic>>('/admin/tenants/$id');
    return PlatformTenant.fromJson(_unwrap(body));
  }

  /// PATCH /admin/tenants/{id}/toggle-active — suspends or restores a whole
  /// tenant; every one of their users is locked out at login.
  Future<void> toggleTenantActive(String id) =>
      _api.patch<dynamic>('/admin/tenants/$id/toggle-active');

  /// GET /admin/tenants/{id}/users.
  Future<List<StaffUser>> tenantUsers(String tenantId) async {
    final body =
        await _api.get<Map<String, dynamic>>('/admin/tenants/$tenantId/users');
    return Paginated.fromJson(body, StaffUser.fromJson).items;
  }

  Future<void> toggleTenantUserActive(String tenantId, String userId) =>
      _api.patch<dynamic>('/admin/tenants/$tenantId/users/$userId/toggle-active');

  /// GET /admin/tenants/{id}/subscriptions — their payment records.
  Future<List<TenantSubscriptionRecord>> tenantSubscriptions(
      String tenantId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/admin/tenants/$tenantId/subscriptions');
    return Paginated.fromJson(body, TenantSubscriptionRecord.fromJson).items;
  }

  /// POST /admin/tenants/{id}/subscriptions/extend — grant time directly,
  /// the manual counterpart to a paid renewal.
  Future<void> extendSubscription(
    String tenantId, {
    required int days,
    String? notes,
  }) =>
      _api.post<dynamic>('/admin/tenants/$tenantId/subscriptions/extend',
          body: {'days': days, 'notes': ?notes});

  /// POST /admin/subscriptions/{id}/confirm-payment — accept an uploaded
  /// proof and activate the subscription.
  Future<void> confirmSubscriptionPayment(String subscriptionId) =>
      _api.post<dynamic>('/admin/subscriptions/$subscriptionId/confirm-payment');

  // ---------------------------------------------------------------------
  // Per-tenant settings
  // ---------------------------------------------------------------------

  Future<TenantEmailSettings> tenantEmailSettings(String tenantId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/admin/tenants/$tenantId/email-settings');
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
  }) =>
      _api.put<dynamic>('/admin/tenants/$tenantId/email-settings', body: {
        'email_enabled': emailEnabled,
        'smtp_from_name': ?fromName,
        'smtp_from_address': ?fromAddress,
        'smtp_host': ?host,
        'smtp_port': ?port,
        'smtp_username': ?username,
        'smtp_password': ?password,
        'smtp_encryption': ?encryption,
      });

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
    final body = await _api
        .get<Map<String, dynamic>>('/admin/tenants/$tenantId/sms-settings');
    return TenantSmsSettings.fromJson(body);
  }

  Future<void> updateTenantSmsSettings(
    String tenantId, {
    required bool smsEnabled,
    String? senderId,
    String? authorization,
  }) =>
      _api.put<dynamic>('/admin/tenants/$tenantId/sms-settings', body: {
        'sms_enabled': smsEnabled,
        'sms_sender_id': ?senderId,
        'sms_authorization': ?authorization,
      });

  /// Credit adjustments. Recharge adds messages, deduct removes them —
  /// separate endpoints rather than a signed amount, so an accidental sign
  /// flip cannot silently drain a tenant's balance.
  Future<void> rechargeSms(String tenantId, int quantity, {String? notes}) =>
      _api.post<dynamic>('/admin/tenants/$tenantId/sms-recharge',
          body: {'quantity': quantity, 'notes': ?notes});

  Future<void> deductSms(String tenantId, int quantity, {String? notes}) =>
      _api.post<dynamic>('/admin/tenants/$tenantId/sms-deduct',
          body: {'quantity': quantity, 'notes': ?notes});

  Future<List<TenantTemplate>> tenantTemplates(String tenantId) async {
    final body = await _api
        .get<Map<String, dynamic>>('/admin/tenants/$tenantId/templates');
    return Paginated.fromJson(body, TenantTemplate.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Catalog: plans, currencies, SMS packages
  // ---------------------------------------------------------------------

  Future<List<PlatformPlan>> plans() async {
    final body =
        await _api.get<Map<String, dynamic>>('/admin/subscription-plans');
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
    final body = await _api.get<Map<String, dynamic>>('/admin/currencies');
    return Paginated.fromJson(_unwrapPage(body), PlatformCurrency.fromJson)
        .items;
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
    final body = await _api.get<Map<String, dynamic>>('/admin/sms-packages');
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
    final body = await _api.get<Map<String, dynamic>>(
      '/admin/sms-purchases',
      query: {'status': status, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(_unwrapPage(body), PlatformSmsPurchase.fromJson);
  }

  // ---------------------------------------------------------------------
  // Permissions, role templates, platform settings
  // ---------------------------------------------------------------------

  /// The permission catalogue every tenant role is built from.
  Future<List<PermissionInfo>> permissions() async {
    final body = await _api.get<Map<String, dynamic>>('/permissions');
    return Paginated.fromJson(body, PermissionInfo.fromJson).items;
  }

  /// Role templates — the starting roles a new tenant is seeded with.
  Future<List<StaffRole>> roleTemplates() async {
    final body =
        await _api.get<Map<String, dynamic>>('/admin/role-templates');
    return Paginated.fromJson(body, StaffRole.fromJson).items;
  }

  Future<PlatformSettings> platformSettings() async {
    final body =
        await _api.get<Map<String, dynamic>>('/admin/platform-settings');
    return PlatformSettings.fromJson(body);
  }

  Future<void> updatePlatformSettings(Map<String, String> values) =>
      _api.put<dynamic>('/admin/platform-settings', body: values);

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
