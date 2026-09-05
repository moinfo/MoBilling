import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api_client.dart';
import '../api_exception.dart';
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

  /// GET /subscription/{id}/invoice — a PDF, generated on demand, for any
  /// subscription record regardless of status.
  Future<Uint8List> subscriptionInvoicePdf(String tenantSubscriptionId) async {
    try {
      final response = await _api.raw.get<List<int>>(
        '/subscription/$tenantSubscriptionId/invoice',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
  }

  /// POST /subscription/{id}/proof — attach proof of a manual/bank-transfer
  /// payment. Only valid while that subscription is still `pending`; 422s
  /// otherwise. Returns the stored file's path.
  Future<String?> uploadSubscriptionProof(
    String tenantSubscriptionId,
    String filePath,
  ) async {
    final form = FormData.fromMap({
      'proof': await MultipartFile.fromFile(filePath),
    });
    try {
      final response = await _api.raw.post<dynamic>(
        '/subscription/$tenantSubscriptionId/proof',
        data: form,
      );
      final body = response.data;
      final data = body is Map ? body['data'] : null;
      return data is Map ? data['payment_proof_path']?.toString() : null;
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
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

  /// GET /automation/cron-logs — scheduled-job runs, newest first.
  /// [date] (Y-m-d) narrows to that day; omitted, every run is returned.
  Future<Paginated<CronLogEntry>> cronLogs({
    String? date,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/automation/cron-logs',
      query: {'date': date, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, CronLogEntry.fromJson);
  }

  /// GET /automation/communication-logs.
  ///
  /// [search] (recipient or client name) overrides [date] server-side —
  /// looking someone up means their whole history, not just today's.
  Future<Paginated<CommunicationLogEntry>> communicationLogs({
    String? search,
    String? date,
    bool clientOnly = false,
    String? channel,
    String? type,
    String? status,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/automation/communication-logs',
      query: {
        'search': search,
        'date': date,
        if (clientOnly) 'client_only': true,
        'channel': channel,
        'type': type,
        'status': status,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, CommunicationLogEntry.fromJson);
  }

  /// GET /automation/upcoming-reminders — what the reminder crons will send
  /// over the next [days] (1-60, server defaults to 14).
  Future<List<ReminderForecastEvent>> upcomingReminders({int? days}) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/automation/upcoming-reminders',
      query: {'days': days},
    );
    return Paginated.fromJson(
      body,
      ReminderForecastEvent.fromJson,
    ).items;
  }

  /// GET /automation/upcoming-reminders/export — a PDF or CSV file, not
  /// JSON.
  Future<Uint8List> exportUpcomingReminders({
    int? days,
    required String format, // pdf | csv
  }) async {
    try {
      final response = await _api.raw.get<List<int>>(
        '/automation/upcoming-reminders/export',
        queryParameters: {'days': days, 'format': format},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final error = e.error;
      throw error is ApiException ? error : ApiException.fromDio(e);
    }
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

  /// POST /users/{id}/impersonate — sign in as one of this tenant's own
  /// staff members. Needs `settings.users`; 422s on an inactive user or on
  /// yourself. Returns the raw response (`{user, token,
  /// subscription_status, days_remaining}`, no `user_type`) — building the
  /// session from it is the caller's job, same as the platform's tenant
  /// impersonation in `PlatformService.impersonateTenant`.
  Future<Map<String, dynamic>> impersonateUser(String id) =>
      _api.post<Map<String, dynamic>>('/users/$id/impersonate');

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

  /// PUT /settings/profile — the signed-in user's own account. No
  /// permission gate — self-service for whoever is signed in.
  /// [currentPassword] is required by the server whenever [password] is
  /// sent; omitted otherwise.
  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    String? currentPassword,
    String? password,
  }) => _api.put<dynamic>(
    '/settings/profile',
    body: {
      'name': ?name,
      'email': ?email,
      'phone': ?phone,
      'current_password': ?currentPassword,
      'password': ?password,
    },
  );

  /// GET /bank-accounts — needs `bank_accounts.read`.
  Future<Paginated<BankAccount>> bankAccounts({
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _api.get<dynamic>(
      '/bank-accounts',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, BankAccount.fromJson);
  }

  /// POST /bank-accounts — needs `bank_accounts.create`.
  Future<BankAccount> createBankAccount({
    required String bankName,
    required String accountNumber,
    double? openingBalance,
    bool isActive = true,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/bank-accounts',
      body: {
        'bank_name': bankName,
        'account_number': accountNumber,
        'opening_balance': ?openingBalance,
        'is_active': isActive,
      },
    );
    return BankAccount.fromJson(_data(body));
  }

  /// PUT /bank-accounts/{id} — needs `bank_accounts.update`.
  Future<BankAccount> updateBankAccount(
    String id, {
    required String bankName,
    required String accountNumber,
    double? openingBalance,
    bool isActive = true,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/bank-accounts/$id',
      body: {
        'bank_name': bankName,
        'account_number': accountNumber,
        'opening_balance': ?openingBalance,
        'is_active': isActive,
      },
    );
    return BankAccount.fromJson(_data(body));
  }

  /// DELETE /bank-accounts/{id} — needs `bank_accounts.delete`.
  Future<void> deleteBankAccount(String id) =>
      _api.delete<dynamic>('/bank-accounts/$id');

  // ---------------------------------------------------------------------
  // Settings: reminders, templates, payment methods, late fee
  // ---------------------------------------------------------------------

  /// GET/PUT /settings/reminders — needs `settings.reminders`.
  Future<ReminderSettings> reminderSettings() async {
    final body = await _api.get<Map<String, dynamic>>('/settings/reminders');
    return ReminderSettings.fromJson(body);
  }

  Future<ReminderSettings> updateReminderSettings({
    required bool emailEnabled,
    required bool smsEnabled,
    required bool reminderSmsEnabled,
    required bool reminderEmailEnabled,
    required bool whatsappEnabled,
    required bool reminderWhatsappEnabled,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/settings/reminders',
      body: {
        'email_enabled': emailEnabled,
        'sms_enabled': smsEnabled,
        'reminder_sms_enabled': reminderSmsEnabled,
        'reminder_email_enabled': reminderEmailEnabled,
        'whatsapp_enabled': whatsappEnabled,
        'reminder_whatsapp_enabled': reminderWhatsappEnabled,
      },
    );
    return ReminderSettings.fromJson(body);
  }

  /// GET/PUT /settings/templates — needs `settings.templates`.
  Future<MessageTemplates> templates() async {
    final body = await _api.get<Map<String, dynamic>>('/settings/templates');
    return MessageTemplates.fromJson(body);
  }

  Future<MessageTemplates> updateTemplates(MessageTemplates templates) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/settings/templates',
      body: {
        'reminder_email_subject': templates.reminderEmailSubject,
        'reminder_email_body': templates.reminderEmailBody,
        'overdue_email_subject': templates.overdueEmailSubject,
        'overdue_email_body': templates.overdueEmailBody,
        'reminder_sms_body': templates.reminderSmsBody,
        'overdue_sms_body': templates.overdueSmsBody,
        'invoice_email_subject': templates.invoiceEmailSubject,
        'invoice_email_body': templates.invoiceEmailBody,
        'email_footer_text': templates.emailFooterText,
      },
    );
    return MessageTemplates.fromJson(body);
  }

  /// GET/PUT /settings/payment-methods — needs `settings.payment_methods`.
  /// The whole list replaces what's on file; at least one method required.
  Future<PaymentMethodsSettings> paymentMethods() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/settings/payment-methods',
    );
    return PaymentMethodsSettings.fromJson(body);
  }

  Future<PaymentMethodsSettings> updatePaymentMethods(
    List<PaymentMethodEntry> methods,
  ) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/settings/payment-methods',
      body: {'payment_methods': [for (final m in methods) m.toJson()]},
    );
    return PaymentMethodsSettings.fromJson(body);
  }

  /// GET/PUT /settings/late-fee — needs `settings.reminders` (not its own
  /// permission — a real quirk of the backend, confirmed).
  Future<LateFeeSettings> lateFeeSettings() async {
    final body = await _api.get<Map<String, dynamic>>('/settings/late-fee');
    return LateFeeSettings.fromJson(body);
  }

  Future<LateFeeSettings> updateLateFeeSettings({
    required bool enabled,
    required double percent,
    required int days,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/settings/late-fee',
      body: {
        'late_fee_enabled': enabled,
        'late_fee_percent': percent,
        'late_fee_days': days,
      },
    );
    return LateFeeSettings.fromJson(body);
  }

  /// GET /settings/late-fee/count — how many invoices a revert would touch,
  /// shown before the irreversible bulk action below.
  Future<int> lateFeeAffectedCount() async {
    final body = await _api.get<Map<String, dynamic>>(
      '/settings/late-fee/count',
    );
    final data = body['data'];
    return (data is Map ? data['count'] : body['count']) is num
        ? ((data is Map ? data['count'] : body['count']) as num).toInt()
        : 0;
  }

  /// POST /settings/late-fee/revert — strips already-applied late fees.
  /// [updateTotals] also recalculates each invoice's stored total, not just
  /// the fee line.
  Future<String?> revertLateFee({required bool updateTotals}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/settings/late-fee/revert',
      body: {'update_totals': updateTotals},
    );
    return body['message']?.toString();
  }

  // ---------------------------------------------------------------------
  // Employee HR profiles — EmployeeProfileController
  // ---------------------------------------------------------------------

  /// GET /employees — HR-admin roster: every active staff member and their
  /// profile, if any. Needs `employees.read`. Not currently wired to a list
  /// screen of its own — `TeamScreen` already lists staff via `/users` and
  /// links each row into [employeeProfile] instead.
  Future<Paginated<StaffUser>> employees({
    String? search,
    int page = 1,
    int perPage = 20,
  }) async {
    final body = await _api.get<dynamic>(
      '/employees',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, StaffUser.fromJson);
  }

  /// GET /employees/{user} — one staff member's HR record. Needs
  /// `employees.read`.
  Future<EmployeeProfilePage> employeeProfile(String userId) async {
    final body = await _api.get<Map<String, dynamic>>('/employees/$userId');
    return EmployeeProfilePage.fromJson(body);
  }

  /// GET /employees/mine — the signed-in user's own HR record, read-only
  /// (no permission required; everyone may see their own details).
  Future<EmployeeProfilePage> myEmployeeProfile() async {
    final body = await _api.get<Map<String, dynamic>>('/employees/mine');
    return EmployeeProfilePage.fromJson(body);
  }

  /// PUT /employees/{user} — create or update the one HR-profile row for a
  /// user. Needs `employees.update`. Every field is optional; omitted ones
  /// are left unvalidated (unlike `updateUser`, this does not require the
  /// whole record back).
  Future<EmployeeProfile> updateEmployeeProfile(
    String userId, {
    String? employeeNumber,
    DateTime? hireDate,
    String? department,
    String? position,
    String? employmentType,
    String? nationalId,
    String? nssfNumber,
    String? tinNumber,
    String? nextOfKinName,
    String? nextOfKinPhone,
    String? bankName,
    String? bankBranch,
    String? bankAccountName,
    String? bankAccountNumber,
    String? mobileMoneyProvider,
    String? mobileMoneyNumber,
    String? notes,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/employees/$userId',
      body: {
        'employee_number': ?employeeNumber,
        'hire_date': hireDate == null ? null : _ymd(hireDate),
        'department': ?department,
        'position': ?position,
        'employment_type': ?employmentType,
        'national_id': ?nationalId,
        'nssf_number': ?nssfNumber,
        'tin_number': ?tinNumber,
        'next_of_kin_name': ?nextOfKinName,
        'next_of_kin_phone': ?nextOfKinPhone,
        'bank_name': ?bankName,
        'bank_branch': ?bankBranch,
        'bank_account_name': ?bankAccountName,
        'bank_account_number': ?bankAccountNumber,
        'mobile_money_provider': ?mobileMoneyProvider,
        'mobile_money_number': ?mobileMoneyNumber,
        'notes': ?notes,
      },
    );
    final data = body['data'];
    return EmployeeProfile.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : body,
    );
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Unwrap `{data: {...}}`, tolerating the endpoints that return the
  /// object at the top level instead.
  static Map<String, dynamic> _data(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
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
  static const bankAccountsCreate = 'bank_accounts.create';
  static const bankAccountsUpdate = 'bank_accounts.update';
  static const bankAccountsDelete = 'bank_accounts.delete';

  /// `EmployeeProfileController::show`/`index` — viewing HR details.
  static const employeesRead = 'employees.read';

  /// `EmployeeProfileController::update` — editing them.
  static const employeesUpdate = 'employees.update';

  static const settingsReminders = 'settings.reminders';
  static const settingsTemplates = 'settings.templates';
  static const settingsPaymentMethods = 'settings.payment_methods';
}
