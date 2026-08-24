/// Tenant administration: the tenant's own MoBilling subscription, the
/// automation digest, staff users, roles and settings.
///
/// Note the two different "subscription" concepts in this codebase:
///   * `ClientSubscription` — a *client* subscribing to one of the tenant's
///     products (see billing_catalog).
///   * [TenantSubscription] here — the *tenant* paying MoBilling. Different
///     table, different endpoints, opposite direction of money.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// The tenant's own plan — SubscriptionController
// ---------------------------------------------------------------------------

class TenantSubscription {
  const TenantSubscription({
    required this.status,
    required this.daysRemaining,
    this.planName,
    this.planPrice,
    this.billingCycle,
    this.startsAt,
    this.endsAt,
    this.trialEndsAt,
    this.subscriptionId,
  });

  /// subscribed | trial | expired | none (and transitional values) — computed
  /// by `Tenant::subscriptionStatus()`. `chipStatus` maps them for display.
  final String status;

  /// Negative once lapsed.
  final int daysRemaining;
  final String? planName;
  final double? planPrice;
  final String? billingCycle;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? trialEndsAt;
  final String? subscriptionId;

  bool get isTrial => status == 'trial';
  bool get isExpired => status == 'expired' || daysRemaining < 0;
  bool get expiringSoon => !isExpired && daysRemaining <= 7;

  /// Status word the shared chip understands.
  String get chipStatus {
    if (isExpired) return 'overdue';
    if (isTrial) return 'pending';
    if (expiringSoon) return 'partial';
    return 'active';
  }

  factory TenantSubscription.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final active = data.object('active_subscription');
    final plan = active?.object('plan');
    return TenantSubscription(
      status: data.strOr('subscription_status', 'none'),
      daysRemaining: data.count('days_remaining'),
      planName: plan?.str('name'),
      planPrice: plan?['price'] == null ? null : plan!.money('price'),
      // Plans carry `billing_cycle_days` (30, 365 …), not a cycle name.
      billingCycle:
          plan?.str('billing_cycle') ??
          (plan?['billing_cycle_days'] == null
              ? null
              : 'every ${plan!.count('billing_cycle_days')} days'),
      startsAt: active?.date('starts_at'),
      endsAt: active?.date('ends_at'),
      trialEndsAt: data.date('trial_ends_at'),
      subscriptionId: active?.str('id'),
    );
  }
}

/// A plan the tenant could move to.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    this.billingCycle,
    this.description,
    this.features = const [],
  });

  final String id;
  final String name;
  final double price;
  final String? billingCycle;
  final String? description;
  final List<String> features;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) =>
      SubscriptionPlan(
        id: json.id(),
        name: json.strOr('name', '—'),
        price: json.money('price'),
        billingCycle: json.str('billing_cycle'),
        description: json.str('description'),
        features: json.strings('features'),
      );
}

/// One past subscription payment.
class SubscriptionHistoryEntry {
  const SubscriptionHistoryEntry({
    required this.id,
    required this.amount,
    required this.status,
    this.planName,
    this.startsAt,
    this.endsAt,
    this.paidAt,
  });

  final String id;
  final double amount;
  final String status;
  final String? planName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? paidAt;

  factory SubscriptionHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SubscriptionHistoryEntry(
        id: json.id(),
        amount: json.money('amount'),
        status: json.strOr('status', 'pending'),
        planName: json.object('plan')?.str('name'),
        startsAt: json.date('starts_at'),
        endsAt: json.date('ends_at'),
        paidAt: json.date('paid_at'),
      );
}

// ---------------------------------------------------------------------------
// Automation — AutomationController
// ---------------------------------------------------------------------------

/// What the nightly jobs did on a given day.
class AutomationSummary {
  const AutomationSummary({
    required this.date,
    required this.invoicesCreated,
    required this.remindersSent,
    required this.billsGenerated,
    required this.subscriptionsExpired,
    required this.emailsSent,
    required this.smsSent,
    required this.failedCommunications,
  });

  final String date;
  final int invoicesCreated;
  final int remindersSent;
  final int billsGenerated;
  final int subscriptionsExpired;
  final int emailsSent;
  final int smsSent;

  /// The number worth alerting on — everything else is routine throughput.
  final int failedCommunications;

  factory AutomationSummary.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return AutomationSummary(
      date: data.strOr('date', ''),
      invoicesCreated: data.count('invoices_created'),
      remindersSent: data.count('reminders_sent'),
      billsGenerated: data.count('bills_generated'),
      subscriptionsExpired: data.count('subscriptions_expired'),
      emailsSent: data.count('emails_sent'),
      smsSent: data.count('sms_sent'),
      failedCommunications: data.count('failed_communications'),
    );
  }
}

/// One scheduled-job run.
class CronLogEntry {
  const CronLogEntry({
    required this.id,
    required this.job,
    required this.status,
    this.message,
    this.ranAt,
    this.durationMs,
  });

  final String id;
  final String job;

  /// success | failed | running.
  final String status;
  final String? message;
  final DateTime? ranAt;
  final int? durationMs;

  bool get failed => status == 'failed';

  /// `/automation/cron-logs` names the job `command` and its outcome
  /// `description`; `job`/`name`/`message` are not keys it sends, which left
  /// every run showing "—" with the command sitting unread in the payload.
  factory CronLogEntry.fromJson(Map<String, dynamic> json) => CronLogEntry(
    id: json.id(),
    job:
        json.str('command') ??
        json.str('job') ??
        json.strOr('name', 'Scheduled job'),
    status: json.strOr('status', 'success'),
    message:
        json.str('description') ??
        json.str('error') ??
        json.str('message') ??
        json.str('output'),
    // started_at is when the job ran; created_at is when the row was
    // written, which for a long job is a different time.
    ranAt:
        json.date('started_at') ??
        json.date('ran_at') ??
        json.date('created_at'),
    durationMs: json['duration_ms'] == null ? null : json.count('duration_ms'),
  );
}

// ---------------------------------------------------------------------------
// Team & roles
// ---------------------------------------------------------------------------

class StaffUser {
  const StaffUser({
    required this.id,
    required this.name,
    required this.isActive,
    this.email,
    this.phone,
    this.roleName,
    this.roleId,
    this.lastLoginAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final String? email;
  final String? phone;
  final String? roleName;
  final String? roleId;
  final DateTime? lastLoginAt;

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    final role = json.object('role');
    return StaffUser(
      id: json.id(),
      name: json.strOr('name', '—'),
      isActive: json.flag('is_active', fallback: true),
      email: json.str('email'),
      phone: json.str('phone'),
      // UserResource emits `role` as the slug string and the human label as
      // `role_name`; a nested object only appears on older shapes.
      roleName:
          json.str('role_name') ?? role?.str('label') ?? role?.str('name'),
      roleId: json.str('role_id') ?? role?.str('id'),
      lastLoginAt: json.date('last_login_at'),
    );
  }
}

class StaffRole {
  const StaffRole({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.usersCount,
    required this.permissionNames,
    this.label,
    this.permissionIds = const [],
    this.description,
  });

  final String id;

  /// The slug (`accountant`), which is what `RoleController::store` validates
  /// as `^[a-z0-9_]+$` and what the legacy `users.role` column mirrors.
  final String name;

  /// The human name (`Accountant`). Separate column from [name]; the web
  /// lists roles by this and only shows the slug underneath.
  final String? label;

  /// System roles ship with the platform and cannot be deleted.
  final bool isSystem;
  final int usersCount;
  final List<String> permissionNames;

  /// The permission UUIDs the role grants — what `PUT /roles/{id}` syncs
  /// against, so an editor needs these rather than the names.
  final List<String> permissionIds;
  final String? description;

  /// What to put on screen: the label when the API sends one, else the slug.
  String get displayName => label ?? name;

  factory StaffRole.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    final rows = permissions is List
        ? permissions.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];
    return StaffRole(
      id: json.id(),
      name: json.strOr('name', '—'),
      label: json.str('label'),
      isSystem: json.flag('is_system'),
      usersCount: json.count('users_count'),
      permissionNames: rows
          .map((p) => p.strOr('name', ''))
          .where((n) => n.isNotEmpty)
          .toList(growable: false),
      permissionIds: rows
          .map((p) => p.id())
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      description: json.str('description'),
    );
  }
}

/// A permission, as returned by `/permissions` and `/available-permissions`.
class PermissionInfo {
  const PermissionInfo({
    required this.name,
    this.id = '',
    this.label,
    this.group,
  });

  /// Empty on the platform `/permissions` listing, which reports names only;
  /// `/available-permissions` sends the UUID that role editing syncs.
  final String id;
  final String name;
  final String? label;

  /// Derived from the name's prefix when the API doesn't group them.
  final String? group;

  String get displayGroup =>
      group ?? (name.contains('.') ? name.split('.').first : 'general');

  String get displayLabel => label ?? name.split('.').last.replaceAll('_', ' ');

  factory PermissionInfo.fromJson(Map<String, dynamic> json) => PermissionInfo(
    id: json.id(),
    name: json.strOr('name', ''),
    label: json.str('label') ?? json.str('description'),
    group: json.str('group') ?? json.str('category'),
  );
}

/// One `group_name` bucket of the permission catalogue, inside a category.
class PermissionGroup {
  const PermissionGroup({
    required this.category,
    required this.name,
    required this.permissions,
  });

  /// menu | crud | settings | reports (the `permissions.category` column).
  final String category;

  /// The `group_name` column: 'Navigation', 'Billing', 'Hosting' …
  final String name;
  final List<PermissionInfo> permissions;

  List<String> get ids => permissions.map((p) => p.id).toList(growable: false);
}

/// `GET /available-permissions` — everything this tenant is allowed to grant,
/// which is the set a role may be built from.
///
/// The endpoint nests two levels (`{category: {group_name: [...]}}`); the
/// groups are flattened into one ordered list here because a phone renders
/// them as one scrolling checklist rather than the web's grid of cards.
class PermissionCatalogue {
  const PermissionCatalogue({required this.groups});

  static const empty = PermissionCatalogue(groups: []);

  final List<PermissionGroup> groups;

  int get total =>
      groups.fold(0, (sum, group) => sum + group.permissions.length);

  bool get isEmpty => groups.isEmpty;

  /// Every permission in catalogue order.
  List<PermissionInfo> get all => [
    for (final group in groups) ...group.permissions,
  ];

  /// The order the web's Roles page uses, so the two read the same way.
  static const _categoryOrder = ['menu', 'crud', 'settings', 'reports'];

  static String categoryLabel(String category) => switch (category) {
    'menu' => 'Menu access',
    'crud' => 'Data operations',
    'settings' => 'Settings',
    'reports' => 'Reports',
    _ => category.replaceAll('_', ' '),
  };

  factory PermissionCatalogue.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final categories = data.keys.toList()
      ..sort((a, b) {
        final ai = _categoryOrder.indexOf(a);
        final bi = _categoryOrder.indexOf(b);
        return (ai == -1 ? 999 : ai).compareTo(bi == -1 ? 999 : bi);
      });

    final groups = <PermissionGroup>[];
    for (final category in categories) {
      final byGroup = data.object(category);
      if (byGroup == null) continue;
      for (final entry in byGroup.entries) {
        final rows = entry.value;
        if (rows is! List) continue;
        final permissions = rows
            .whereType<Map>()
            .map((p) => PermissionInfo.fromJson(Map<String, dynamic>.from(p)))
            .where((p) => p.id.isNotEmpty)
            .toList(growable: false);
        if (permissions.isEmpty) continue;
        groups.add(
          PermissionGroup(
            category: category,
            name: entry.key.isEmpty ? 'Other' : entry.key,
            permissions: permissions,
          ),
        );
      }
    }
    return PermissionCatalogue(groups: groups);
  }
}

// ---------------------------------------------------------------------------
// Two-factor authentication — TwoFactorAuthController
// ---------------------------------------------------------------------------

/// Whether the signed-in account has an authenticator app attached.
class TwoFactorStatus {
  const TwoFactorStatus({required this.enabled, this.recoveryCodesRemaining});

  final bool enabled;

  /// Null while 2FA is off. Each code is single-use, so this counts down.
  final int? recoveryCodesRemaining;

  /// Below this the codes are worth replacing before they run out — with none
  /// left, a lost phone locks the account out entirely.
  bool get recoveryCodesLow => enabled && (recoveryCodesRemaining ?? 0) <= 2;

  factory TwoFactorStatus.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return TwoFactorStatus(
      enabled: data.flag('enabled'),
      recoveryCodesRemaining: data['recovery_codes_remaining'] == null
          ? null
          : data.count('recovery_codes_remaining'),
    );
  }
}

/// `POST /auth/2fa/enable` — a fresh, not-yet-confirmed secret.
///
/// Nothing changes for sign-in until `POST /auth/2fa/confirm` accepts a code
/// generated from it, so abandoning this screen is safe.
class TwoFactorSetup {
  const TwoFactorSetup({required this.secret, required this.otpauthUrl});

  /// The base-32 key, for typing into an authenticator by hand.
  final String secret;

  /// `otpauth://totp/Issuer:label?secret=…&issuer=…` — the string a QR code
  /// would encode.
  final String otpauthUrl;

  /// The account name inside the otpauth URI's label, which an authenticator
  /// would have read from the QR code — needed for manual entry.
  String? get account {
    final path = Uri.tryParse(otpauthUrl)?.pathSegments.lastOrNull;
    if (path == null || path.isEmpty) return null;
    final colon = path.indexOf(':');
    return colon == -1 ? path : path.substring(colon + 1);
  }

  /// The issuer the authenticator will file the account under.
  String? get issuer {
    final uri = Uri.tryParse(otpauthUrl);
    final fromQuery = uri?.queryParameters['issuer'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final path = uri?.pathSegments.lastOrNull ?? '';
    final colon = path.indexOf(':');
    return colon <= 0 ? null : path.substring(0, colon);
  }

  factory TwoFactorSetup.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return TwoFactorSetup(
      secret: data.strOr('secret', ''),
      otpauthUrl: data.str('otpauth_url') ?? data.strOr('otpauth_uri', ''),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// The tenant's company profile — what appears on invoices.
class CompanySettings {
  const CompanySettings({
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.website,
    this.currency,
    this.logoUrl,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? taxId;
  final String? website;
  final String? currency;
  final String? logoUrl;

  factory CompanySettings.fromJson(Map<String, dynamic> json) {
    // The endpoint returns the tenant, sometimes wrapped.
    final data = json.object('data') ?? json.object('tenant') ?? json;
    return CompanySettings(
      name: data.strOr('name', '—'),
      email: data.str('email'),
      phone: data.str('phone'),
      address: data.str('address'),
      taxId: data.str('tax_id'),
      website: data.str('website'),
      currency: data.str('currency'),
      logoUrl: data.str('logo_url'),
    );
  }
}

class BankAccount {
  const BankAccount({
    required this.id,
    required this.bankName,
    required this.isActive,
    this.accountName,
    this.accountNumber,
    this.branch,
  });

  final String id;
  final String bankName;
  final bool isActive;
  final String? accountName;
  final String? accountNumber;
  final String? branch;

  factory BankAccount.fromJson(Map<String, dynamic> json) => BankAccount(
    id: json.id(),
    bankName: json.strOr('bank_name', '—'),
    isActive: json.flag('is_active', fallback: true),
    accountName: json.str('account_name'),
    accountNumber: json.str('account_number'),
    branch: json.str('branch'),
  );
}

// ---------------------------------------------------------------------------
// Employee HR profiles — EmployeeProfileController
//
// Separate from [StaffUser]/`UserController` (name, email, role — the sign-in
// account) and from the payroll exemption "Assign" screens
// (`EmployeeProfileController::payeSubscriptions` etc, which flip these same
// database columns from Payroll > Settings for many staff at once). This is
// the HR-admin record for one person: hire details, statutory numbers, next
// of kin, pay-out details.
// ---------------------------------------------------------------------------

/// The signed-in-account side of `GET /employees/{user}` and
/// `/employees/mine` — `$user->load('role', 'supervisor')`, not the fuller
/// [StaffUser] shape `UserResource` builds.
class EmployeeUserSummary {
  const EmployeeUserSummary({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.roleLabel,
    this.supervisorName,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? roleLabel;
  final String? supervisorName;

  factory EmployeeUserSummary.fromJson(Map<String, dynamic> json) {
    final role = json.object('role');
    final supervisor = json.object('supervisor');
    return EmployeeUserSummary(
      id: json.id(),
      name: json.strOr('name', '—'),
      email: json.str('email'),
      phone: json.str('phone'),
      roleLabel: role?.str('label') ?? role?.str('name'),
      supervisorName: supervisor?.str('name'),
    );
  }
}

/// One staff member's HR record. `null` fields simply mean nothing has been
/// entered yet — `EmployeeProfileController::update` upserts the single row
/// per user on first save.
class EmployeeProfile {
  const EmployeeProfile({
    this.employeeNumber,
    this.hireDate,
    this.department,
    this.position,
    this.employmentType,
    this.nationalId,
    this.nssfNumber,
    this.tinNumber,
    this.dateOfBirth,
    this.gender,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.bankName,
    this.bankBranch,
    this.bankAccountName,
    this.bankAccountNumber,
    this.mobileMoneyProvider,
    this.mobileMoneyNumber,
    this.terminationDate,
    this.notes,
    this.subjectToPaye = true,
  });

  final String? employeeNumber;
  final DateTime? hireDate;
  final String? department;
  final String? position;

  /// full_time | part_time | contract | intern.
  final String? employmentType;
  final String? nationalId;
  final String? nssfNumber;
  final String? tinNumber;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? bankName;
  final String? bankBranch;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? mobileMoneyProvider;
  final String? mobileMoneyNumber;
  final DateTime? terminationDate;
  final String? notes;

  /// The only exemption flag this record's own edit form touches — the rest
  /// (attendance/report-penalty exemptions) live under Payroll > Settings >
  /// Statutory Rates > Assign, same as the web's `UserProfile.tsx`.
  final bool subjectToPaye;

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) =>
      EmployeeProfile(
        employeeNumber: json.str('employee_number'),
        hireDate: json.date('hire_date'),
        department: json.str('department'),
        position: json.str('position'),
        employmentType: json.str('employment_type'),
        nationalId: json.str('national_id'),
        nssfNumber: json.str('nssf_number'),
        tinNumber: json.str('tin_number'),
        dateOfBirth: json.date('date_of_birth'),
        gender: json.str('gender'),
        nextOfKinName: json.str('next_of_kin_name'),
        nextOfKinPhone: json.str('next_of_kin_phone'),
        bankName: json.str('bank_name'),
        bankBranch: json.str('bank_branch'),
        bankAccountName: json.str('bank_account_name'),
        bankAccountNumber: json.str('bank_account_number'),
        mobileMoneyProvider: json.str('mobile_money_provider'),
        mobileMoneyNumber: json.str('mobile_money_number'),
        terminationDate: json.date('termination_date'),
        notes: json.str('notes'),
        subjectToPaye: json.flag('subject_to_paye', fallback: true),
      );
}

/// `{user, profile}` — what `show`, `update` and `mine` all answer with.
/// [profile] is null until someone has saved HR details for this person.
class EmployeeProfilePage {
  const EmployeeProfilePage({required this.user, this.profile});

  final EmployeeUserSummary user;
  final EmployeeProfile? profile;

  factory EmployeeProfilePage.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final userJson = data.object('user');
    return EmployeeProfilePage(
      user: userJson == null
          ? const EmployeeUserSummary(id: '', name: '—')
          : EmployeeUserSummary.fromJson(userJson),
      profile: data.object('profile') == null
          ? null
          : EmployeeProfile.fromJson(data.object('profile')!),
    );
  }
}

/// The employment-type choices `EmployeeProfileController::update` validates
/// against (`nullable|in:full_time,part_time,contract,intern`).
abstract final class EmploymentTypes {
  static const values = <(String, String)>[
    ('full_time', 'Full time'),
    ('part_time', 'Part time'),
    ('contract', 'Contract'),
    ('intern', 'Intern'),
  ];

  static String label(String? value) {
    for (final (v, l) in values) {
      if (v == value) return l;
    }
    return value ?? '—';
  }
}
