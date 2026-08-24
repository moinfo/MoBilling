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
    // `SubscriptionController::checkout` wraps the service result:
    // `{message, data: {redirect_url, ...}}`. Bank-transfer plans have no
    // redirect by design — the message then carries the instructions.
    final data = body['data'];
    final inner = data is Map ? data : body;
    return inner['redirect_url']?.toString() ?? inner['url']?.toString();
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
  }) => _api.post<dynamic>(
    '/users',
    body: {
      'name': name,
      'email': email,
      'password': password,
      'role_id': roleId,
      'phone': ?phone,
    },
  );

  /// PUT /users/{id}.
  ///
  /// `UserController::update` re-validates the whole record: `name`, `email`
  /// and `role_id` are all `required` there, so a partial body 422s. Send the
  /// current values back for anything the form did not change. `password` is
  /// the one genuinely optional field — omitted, the existing one stands.
  Future<void> updateUser(
    String id, {
    String? name,
    String? email,
    String? phone,
    String? roleId,
    String? password,
  }) => _api.put<dynamic>(
    '/users/$id',
    body: {
      'name': ?name,
      'email': ?email,
      'phone': ?phone,
      'role_id': ?roleId,
      'password': ?password,
    },
  );

  /// PATCH /users/{id}/toggle-active — deactivating blocks sign-in without
  /// deleting the account's history.
  Future<void> toggleUserActive(String id) =>
      _api.patch<dynamic>('/users/$id/toggle-active');

  /// GET /roles — with user counts and the permissions each grants.
  Future<List<StaffRole>> roles() async {
    final body = await _api.get<dynamic>('/roles');
    return Paginated.fromJson(body, StaffRole.fromJson).items;
  }

  /// GET /available-permissions — the set this tenant may grant, which is
  /// what a role can be built from. Nested `{category: {group: [...]}}`.
  Future<PermissionCatalogue> availablePermissions() async {
    final body = await _api.get<Map<String, dynamic>>('/available-permissions');
    return PermissionCatalogue.fromJson(body);
  }

  /// POST /roles. [name] is the slug (`^[a-z0-9_]+$`, unique per tenant),
  /// [label] the human name, [permissionIds] the UUIDs from
  /// [availablePermissions] — the API rejects an empty list.
  Future<void> createRole({
    required String name,
    required String label,
    required List<String> permissionIds,
  }) => _api.post<dynamic>(
    '/roles',
    body: {'name': name, 'label': label, 'permissions': permissionIds},
  );

  /// PUT /roles/{id}. The slug is immutable server-side — only the label and
  /// the permission set can change, and the set is synced, not merged.
  Future<void> updateRole(
    String id, {
    required String label,
    required List<String> permissionIds,
  }) => _api.put<dynamic>(
    '/roles/$id',
    body: {'label': label, 'permissions': permissionIds},
  );

  /// DELETE /roles/{id}. Refused (422) for system roles and for any role that
  /// still has users, so the message is worth showing verbatim.
  Future<String?> deleteRole(String id) async {
    final body = await _api.delete<Map<String, dynamic>>('/roles/$id');
    return body['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Two-factor authentication (self-service, no permission)
  // ---------------------------------------------------------------------

  /// GET /auth/2fa/status.
  Future<TwoFactorStatus> twoFactorStatus() async {
    final body = await _api.get<Map<String, dynamic>>('/auth/2fa/status');
    return TwoFactorStatus.fromJson(body);
  }

  /// POST /auth/2fa/enable — mints a new secret and returns it with the
  /// otpauth URI. Nothing is active until [confirmTwoFactor] succeeds.
  Future<TwoFactorSetup> enableTwoFactor() async {
    final body = await _api.post<Map<String, dynamic>>('/auth/2fa/enable');
    return TwoFactorSetup.fromJson(body);
  }

  /// POST /auth/2fa/confirm — verifies the first code and turns 2FA on.
  ///
  /// Returns the recovery codes, which the server only ever sends once: it
  /// stores hashes, so a code not written down here is gone.
  Future<List<String>> confirmTwoFactor(String code) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/auth/2fa/confirm',
      body: {'code': code},
    );
    return _recoveryCodes(body);
  }

  /// POST /auth/2fa/disable. The controller demands the account password —
  /// a stolen unlocked phone must not be able to strip the second factor.
  Future<String?> disableTwoFactor(String password) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/auth/2fa/disable',
      body: {'password': password},
    );
    return body['message']?.toString();
  }

  /// POST /auth/2fa/recovery-codes/regenerate — password-confirmed, and the
  /// previous codes stop working the moment it returns.
  Future<List<String>> regenerateRecoveryCodes(String password) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/auth/2fa/recovery-codes/regenerate',
      body: {'password': password},
    );
    return _recoveryCodes(body);
  }

  static List<String> _recoveryCodes(Map<String, dynamic> body) {
    final codes = body['recovery_codes'];
    if (codes is! List) return const [];
    return codes.map((c) => c.toString()).toList(growable: false);
  }

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

  /// PUT /settings/company — the details that print on invoices. Needs
  /// `settings.company`. `email` and `currency` are required server-side,
  /// so pass the current currency through unchanged when only editing the
  /// contact details.
  Future<void> updateCompany({
    required String name,
    required String email,
    required String currency,
    String? phone,
    String? address,
    String? taxId,
    String? website,
  }) => _api.put<dynamic>(
    '/settings/company',
    body: {
      'name': name,
      'email': email,
      'currency': currency,
      'phone': ?phone,
      'address': ?address,
      'tax_id': ?taxId,
      'website': ?website,
    },
  );

  /// PUT /settings/profile — the signed-in user's own name/phone.
  Future<void> updateProfile({String? name, String? phone}) =>
      _api.put<dynamic>(
        '/settings/profile',
        body: {'name': ?name, 'phone': ?phone},
      );

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

  /// Creating, editing and deleting roles. Named separately because it reads
  /// as its own capability, but it is deliberately the same string: the
  /// `/roles` write routes sit inside `middleware('permission:settings.users')`
  /// and `RoleController` re-checks `settings.users`, so gating the buttons on
  /// anything else would show controls the API answers with 403.
  static const roles = 'settings.users';
  static const settings = 'menu.settings';
  static const subscription = 'menu.subscription';
  static const automation = 'menu.automation';
  static const bankAccountsRead = 'bank_accounts.read';
}
