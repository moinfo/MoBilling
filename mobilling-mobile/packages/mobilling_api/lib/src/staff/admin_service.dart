import '../api_client.dart';
import '../paginated.dart';
import 'admin_models.dart';

/// Tenant administration.
///
/// Deliberate scope note: this is the *tenant's* own administration, not the
/// platform super-admin area (`/admin/*`, `/tenants/*`), which stays web-only.
class AdminService {
  const AdminService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // The tenant's own MoBilling plan
  // ---------------------------------------------------------------------

  /// GET /subscription/current — status, days remaining and the active plan.
  Future<TenantSubscription> currentSubscription() async {
    final body = await _api.get<dynamic>('/subscription/current');
    return TenantSubscription.fromJson(body);
  }

  /// GET /subscription/plans.
  Future<List<SubscriptionPlan>> plans() async {
    final body = await _api.get<dynamic>('/subscription/plans');
    return Paginated.fromJson(body, SubscriptionPlan.fromJson).items;
  }

  /// GET /subscription/history — past payments.
  Future<List<SubscriptionHistoryEntry>> subscriptionHistory() async {
    final body = await _api.get<dynamic>('/subscription/history');
    return Paginated.fromJson(body, SubscriptionHistoryEntry.fromJson).items;
  }

  /// POST /subscription/checkout — start a plan purchase.
  ///
  /// Returns the gateway redirect URL, which the caller opens in a browser —
  /// same pattern as the client app's invoice payment.
  Future<String?> checkoutSubscription(String planId) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/subscription/checkout',
      body: {'plan_id': planId},
    );
    return body['redirect_url']?.toString() ??
        body['url']?.toString();
  }

  // ---------------------------------------------------------------------
  // Automation
  // ---------------------------------------------------------------------

  /// GET /automation/summary — what the scheduled jobs did.
  /// [date] is Y-m-d; defaults server-side to today.
  Future<AutomationSummary> automationSummary({String? date}) async {
    final body = await _api.get<dynamic>(
      '/automation/summary',
      query: {'date': date},
    );
    return AutomationSummary.fromJson(body);
  }

  /// GET /automation/cron-logs — recent scheduled-job runs.
  Future<List<CronLogEntry>> cronLogs() async {
    final body = await _api.get<dynamic>('/automation/cron-logs');
    return Paginated.fromJson(body, CronLogEntry.fromJson).items;
  }

  // ---------------------------------------------------------------------
  // Team & roles
  // ---------------------------------------------------------------------

  /// GET /users — staff accounts, paginated. Needs `settings.users`.
  Future<Paginated<StaffUser>> users({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/users',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffUser.fromJson);
  }

  /// POST /users — add a staff account.
  Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required String roleId,
    String? phone,
  }) =>
      _api.post<dynamic>('/users', body: {
        'name': name,
        'email': email,
        'password': password,
        'role_id': roleId,
        'phone': ?phone,
      });

  /// PUT /users/{id}.
  Future<void> updateUser(
    String id, {
    String? name,
    String? phone,
    String? roleId,
  }) =>
      _api.put<dynamic>('/users/$id', body: {
        'name': ?name,
        'phone': ?phone,
        'role_id': ?roleId,
      });

  /// PATCH /users/{id}/toggle-active — deactivating blocks sign-in without
  /// deleting the account's history.
  Future<void> toggleUserActive(String id) =>
      _api.patch<dynamic>('/users/$id/toggle-active');

  /// GET /roles — with user counts and the permissions each grants.
  Future<List<StaffRole>> roles() async {
    final body = await _api.get<dynamic>('/roles');
    return Paginated.fromJson(body, StaffRole.fromJson).items;
  }

  /// GET /permissions — every permission the platform defines, for the
  /// role editor's checklist.
  Future<List<PermissionInfo>> permissions() async {
    final body = await _api.get<dynamic>('/permissions');
    return Paginated.fromJson(body, PermissionInfo.fromJson).items;
  }

  /// PUT /roles/{id} — replaces the role's permission set wholesale.
  Future<void> updateRole(
    String id, {
    required String name,
    required List<String> permissionNames,
  }) =>
      _api.put<dynamic>('/roles/$id', body: {
        'name': name,
        'permissions': permissionNames,
      });

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  /// GET /settings/company is not a route — the company profile comes back on
  /// `/auth/me`'s tenant. This reads it from the settings group that does
  /// exist, falling back to the reminder-settings payload's tenant.
  Future<CompanySettings> companySettings() async {
    final body = await _api.get<Map<String, dynamic>>('/auth/me');
    final user = body['user'];
    final tenant = user is Map ? user['tenant'] : null;
    return CompanySettings.fromJson(
      tenant is Map ? Map<String, dynamic>.from(tenant) : body,
    );
  }

  /// PUT /settings/company — the details that print on invoices.
  Future<void> updateCompany({
    required String name,
    String? email,
    String? phone,
    String? address,
    String? taxId,
    String? website,
  }) =>
      _api.put<dynamic>('/settings/company', body: {
        'name': name,
        'email': ?email,
        'phone': ?phone,
        'address': ?address,
        'tax_id': ?taxId,
        'website': ?website,
      });

  /// PUT /settings/profile — the signed-in user's own name/phone.
  Future<void> updateProfile({String? name, String? phone}) =>
      _api.put<dynamic>('/settings/profile',
          body: {'name': ?name, 'phone': ?phone});

  /// GET /bank-accounts — needs `bank_accounts.read`.
  Future<Paginated<BankAccount>> bankAccounts({
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _api.get<dynamic>(
      '/bank-accounts',
      query: {'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, BankAccount.fromJson);
  }
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class AdminPermissions {
  static const users = 'settings.users';
  static const settings = 'menu.settings';
  static const subscription = 'menu.subscription';
  static const automation = 'menu.automation';
  static const bankAccountsRead = 'bank_accounts.read';
}
