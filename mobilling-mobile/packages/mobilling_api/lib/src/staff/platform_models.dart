/// Platform super-admin models — the `/admin/*` area.
///
/// This is MoBilling operating its own product: tenants, the plans they buy,
/// the SMS credit they consume, and platform-wide configuration. Everything
/// here sits behind `EnsureSuperAdmin`, and a super admin has **no tenant**,
/// so nothing in this file assumes tenant scoping.
library;

import '../json.dart';
import 'admin_models.dart' show PermissionCatalogue;

class PlatformDashboard {
  const PlatformDashboard({
    required this.totalTenants,
    required this.activeTenants,
    required this.smsEnabledTenants,
    required this.totalUsers,
    required this.totalSmsRevenue,
    required this.totalSmsSold,
    required this.pendingPurchases,
    required this.recentPurchases,
    this.masterSmsBalance,
  });

  final int totalTenants;
  final int activeTenants;
  final int smsEnabledTenants;
  final int totalUsers;
  final double totalSmsRevenue;
  final int totalSmsSold;
  final int pendingPurchases;
  final List<PlatformSmsPurchase> recentPurchases;

  /// Live balance from the SMS reseller. Null when the upstream call failed —
  /// the controller logs and continues rather than failing the dashboard.
  final int? masterSmsBalance;

  factory PlatformDashboard.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return PlatformDashboard(
      totalTenants: data.count('total_tenants'),
      activeTenants: data.count('active_tenants'),
      smsEnabledTenants: data.count('sms_enabled_tenants'),
      totalUsers: data.count('total_users'),
      totalSmsRevenue: data.money('total_sms_revenue'),
      totalSmsSold: data.count('total_sms_sold'),
      pendingPurchases: data.count('pending_purchases'),
      recentPurchases: data.list(
        'recent_purchases',
        PlatformSmsPurchase.fromJson,
      ),
      masterSmsBalance: data['master_sms_balance'] == null
          ? null
          : data.count('master_sms_balance'),
    );
  }
}

class PlatformTenant {
  const PlatformTenant({
    required this.id,
    required this.name,
    required this.isActive,
    required this.smsEnabled,
    this.email,
    this.phone,
    this.address,
    this.taxId,
    this.customDomain,
    this.currency,
    this.subscriptionStatus,
    this.daysRemaining,
    this.smsBalance,
    this.usersCount,
    this.createdAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final bool smsEnabled;
  final String? email;
  final String? phone;

  /// Only used by the create/edit tenant form — the list and detail views
  /// have never needed them.
  final String? address;
  final String? taxId;

  /// White-label host; branding resolves from it.
  final String? customDomain;
  final String? currency;
  final String? subscriptionStatus;
  final int? daysRemaining;
  final int? smsBalance;
  final int? usersCount;
  final DateTime? createdAt;

  /// Status word for the shared chip — a deactivated tenant matters more than
  /// its subscription state, so it wins.
  String get chipStatus {
    if (!isActive) return 'cancelled';
    return switch (subscriptionStatus) {
      'active' => 'active',
      'trial' => 'pending',
      'expired' => 'overdue',
      _ => 'draft',
    };
  }

  factory PlatformTenant.fromJson(Map<String, dynamic> json) => PlatformTenant(
    id: json.id(),
    name: json.strOr('name', '—'),
    isActive: json.flag('is_active', fallback: true),
    smsEnabled: json.flag('sms_enabled'),
    email: json.str('email'),
    phone: json.str('phone'),
    address: json.str('address'),
    taxId: json.str('tax_id'),
    customDomain: json.str('custom_domain'),
    currency: json.str('currency'),
    subscriptionStatus: json.str('subscription_status'),
    daysRemaining: json['days_remaining'] == null
        ? null
        : json.count('days_remaining'),
    smsBalance: json['sms_balance'] == null ? null : json.count('sms_balance'),
    usersCount: json['users_count'] == null ? null : json.count('users_count'),
    createdAt: json.date('created_at'),
  );
}

// ---------------------------------------------------------------------------
// Tenant management: create/edit/promote and the client search that feeds
// "Promote from Client" — web parity for `mobilling-ui/src/pages/admin/Tenants.tsx`.
// ---------------------------------------------------------------------------

/// One `GET /admin/clients/search` hit — a cross-tenant client lookup, used
/// only to pick who "Promote from Client" spins out into an independent
/// tenant. Distinct from the tenant-scoped `StaffClient` in `admin_models.dart`,
/// which a super admin (no tenant of their own) cannot use here.
class ClientSearchResult {
  const ClientSearchResult({
    required this.id,
    required this.tenantId,
    required this.name,
    this.email,
    this.phone,
    this.taxId,
    this.address,
    this.tenantName,
    this.tenantCurrency,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? email;
  final String? phone;
  final String? taxId;
  final String? address;

  /// The tenant this client currently belongs to — shown so staff can see
  /// what they are about to spin out into its own independent business.
  /// Nothing about it moves; promoting only reads these identity fields.
  final String? tenantName;
  final String? tenantCurrency;

  factory ClientSearchResult.fromJson(Map<String, dynamic> json) {
    final tenant = json.object('tenant');
    return ClientSearchResult(
      id: json.id(),
      tenantId: json.strOr('tenant_id', ''),
      name: json.strOr('name', '—'),
      email: json.str('email'),
      phone: json.str('phone'),
      taxId: json.str('tax_id'),
      address: json.str('address'),
      tenantName: tenant?.str('name'),
      tenantCurrency: tenant?.str('currency'),
    );
  }
}

class PlatformPlan {
  const PlatformPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
    this.billingCycle,
    this.description,
    this.durationDays,
    this.features = const [],
  });

  final String id;
  final String name;
  final double price;
  final bool isActive;
  final String? billingCycle;
  final String? description;
  final int? durationDays;
  final List<String> features;

  factory PlatformPlan.fromJson(Map<String, dynamic> json) => PlatformPlan(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    isActive: json.flag('is_active', fallback: true),
    billingCycle: json.str('billing_cycle'),
    description: json.str('description'),
    durationDays: json['duration_days'] == null
        ? null
        : json.count('duration_days'),
    features: json.strings('features'),
  );
}

class PlatformCurrency {
  const PlatformCurrency({
    required this.id,
    required this.code,
    required this.isActive,
    this.name,
    this.symbol,
    this.rate,
  });

  final String id;
  final String code;
  final bool isActive;
  final String? name;
  final String? symbol;
  final double? rate;

  factory PlatformCurrency.fromJson(Map<String, dynamic> json) =>
      PlatformCurrency(
        id: json.id(),
        code: json.strOr('code', '—'),
        isActive: json.flag('is_active', fallback: true),
        name: json.str('name'),
        symbol: json.str('symbol'),
        rate: json['rate'] == null ? null : json.money('rate'),
      );
}

class SmsPackage {
  const SmsPackage({
    required this.id,
    required this.name,
    required this.smsCount,
    required this.price,
    required this.isActive,
  });

  final String id;
  final String name;
  final int smsCount;
  final double price;
  final bool isActive;

  /// Price per message — the number that actually decides value.
  double get unitPrice => smsCount <= 0 ? 0 : price / smsCount;

  factory SmsPackage.fromJson(Map<String, dynamic> json) => SmsPackage(
    id: json.id(),
    name: json.strOr('name', '—'),
    smsCount: json.count('sms_count', fallback: json.count('sms_quantity')),
    price: json.money('price'),
    isActive: json.flag('is_active', fallback: true),
  );
}

class PlatformSmsPurchase {
  const PlatformSmsPurchase({
    required this.id,
    required this.smsQuantity,
    required this.totalAmount,
    required this.status,
    this.tenantName,
    this.userName,
    this.createdAt,
  });

  final String id;
  final int smsQuantity;
  final double totalAmount;

  /// pending | completed | failed.
  final String status;
  final String? tenantName;
  final String? userName;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory PlatformSmsPurchase.fromJson(Map<String, dynamic> json) =>
      PlatformSmsPurchase(
        id: json.id(),
        smsQuantity: json.count('sms_quantity'),
        totalAmount: json.money('total_amount'),
        status: json.strOr('status', 'pending'),
        tenantName:
            json.str('tenant_name') ?? json.object('tenant')?.str('name'),
        userName: json.str('user_name') ?? json.object('user')?.str('name'),
        createdAt: json.date('created_at'),
      );
}

/// Per-tenant email (SMTP) configuration.
class TenantEmailSettings {
  const TenantEmailSettings({
    required this.emailEnabled,
    this.fromName,
    this.fromAddress,
    this.host,
    this.port,
    this.username,
    this.encryption,
  });

  final bool emailEnabled;
  final String? fromName;
  final String? fromAddress;
  final String? host;
  final int? port;
  final String? username;
  final String? encryption;

  factory TenantEmailSettings.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return TenantEmailSettings(
      emailEnabled: data.flag('email_enabled'),
      fromName: data.str('smtp_from_name') ?? data.str('from_name'),
      fromAddress: data.str('smtp_from_address') ?? data.str('from_address'),
      host: data.str('smtp_host'),
      port: data['smtp_port'] == null ? null : data.count('smtp_port'),
      username: data.str('smtp_username'),
      encryption: data.str('smtp_encryption'),
    );
  }
}

/// Per-tenant SMS configuration and credit.
class TenantSmsSettings {
  const TenantSmsSettings({
    required this.smsEnabled,
    required this.smsBalance,
    this.senderId,
    this.reminderSmsEnabled = false,
  });

  final bool smsEnabled;
  final int smsBalance;
  final String? senderId;
  final bool reminderSmsEnabled;

  factory TenantSmsSettings.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return TenantSmsSettings(
      smsEnabled: data.flag('sms_enabled'),
      smsBalance: data.count('sms_balance'),
      senderId: data.str('sms_sender_id') ?? data.str('sender_id'),
      reminderSmsEnabled: data.flag('reminder_sms_enabled'),
    );
  }
}

/// One notification template a tenant can override.
class TenantTemplate {
  const TenantTemplate({
    required this.key,
    required this.body,
    this.subject,
    this.label,
  });

  final String key;
  final String body;
  final String? subject;
  final String? label;

  factory TenantTemplate.fromJson(Map<String, dynamic> json) => TenantTemplate(
    key: json.strOr('key', json.strOr('name', '')),
    body: json.strOr('body', json.strOr('content', '')),
    subject: json.str('subject'),
    label: json.str('label') ?? json.str('title'),
  );
}

/// A tenant's subscription record, seen from the platform side.
class TenantSubscriptionRecord {
  const TenantSubscriptionRecord({
    required this.id,
    required this.amount,
    required this.status,
    this.planName,
    this.startsAt,
    this.endsAt,
    this.paidAt,
    this.proofUrl,
  });

  final String id;
  final double amount;
  final String status;
  final String? planName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? paidAt;

  /// Payment proof a tenant uploaded — what a super admin confirms against.
  final String? proofUrl;

  bool get awaitingConfirmation => status == 'pending' || status == 'awaiting';

  factory TenantSubscriptionRecord.fromJson(Map<String, dynamic> json) =>
      TenantSubscriptionRecord(
        id: json.id(),
        amount: json.money('amount'),
        status: json.strOr('status', 'pending'),
        planName: json.object('plan')?.str('name') ?? json.str('plan_name'),
        startsAt: json.date('starts_at'),
        endsAt: json.date('ends_at'),
        paidAt: json.date('paid_at'),
        proofUrl: json.str('proof_url') ?? json.str('payment_proof_url'),
      );
}

/// Platform-wide settings (branding, defaults, gateway keys).
class PlatformSettings {
  const PlatformSettings({required this.values});

  /// Free-form key/value bag — the endpoint returns whatever is configured,
  /// so this stays a map rather than inventing fields that may not exist.
  final Map<String, String> values;

  String? operator [](String key) => values[key];

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return PlatformSettings(
      values: {
        for (final entry in data.entries)
          if (entry.value != null &&
              entry.value is! Map &&
              entry.value is! List)
            entry.key: entry.value.toString(),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Self-hosted licensing: licenses, their pricing catalog, and the "check for
// updates" release feed. A licensed on-prem install checks in against these.
// ---------------------------------------------------------------------------

/// Same three packages offered at tenant signup (`TenantProvisioningService`'s
/// `product_tier`), reused here as the self-hosted product a license covers.
abstract final class LicensePackages {
  static const lite = 'lite';
  static const reseller = 'reseller';
  static const general = 'general';

  static const values = [lite, reseller, general];

  static const _labels = {
    lite: 'MoBilling Lite',
    reseller: 'MoBilling Reseller',
    general: 'MoBilling Complete',
  };

  static String label(String product) => _labels[product] ?? product;
}

abstract final class LicenseBillingPeriods {
  static const perpetual = 'perpetual';
  static const monthly = 'monthly';
  static const quarterly = 'quarterly';
  static const semiAnnual = 'semi_annual';
  static const annual = 'annual';

  static const values = [perpetual, monthly, quarterly, semiAnnual, annual];

  static const _labels = {
    perpetual: 'Perpetual (no expiry)',
    monthly: 'Monthly',
    quarterly: 'Quarterly (3 months)',
    semiAnnual: 'Semi-Annual (6 months)',
    annual: 'Annual (12 months)',
  };

  static String label(String period) => _labels[period] ?? period;

  /// Months to add for `License::calculateExpiry` — null for `perpetual`,
  /// which never expires.
  static const _months = {monthly: 1, quarterly: 3, semiAnnual: 6, annual: 12};

  static int? months(String period) => _months[period];
}

/// A self-hosted install license (WHMCS-style): a key locked to the domain
/// that first activates it, priced by [LicensePlan].
class License {
  const License({
    required this.id,
    required this.licenseKey,
    required this.customerName,
    required this.customerEmail,
    required this.product,
    required this.billingPeriod,
    required this.status,
    this.domain,
    this.startsAt,
    this.amountPaid,
    this.expiresAt,
    this.lastValidatedAt,
    this.notes,
    this.activationsCount = 0,
    this.createdAt,
  });

  final String id;
  final String licenseKey;
  final String customerName;
  final String customerEmail;

  /// One of [LicensePackages.values].
  final String product;

  /// One of [LicenseBillingPeriods.values].
  final String billingPeriod;

  /// active | suspended | expired.
  final String status;

  /// The domain this key first activated on; null before first check-in.
  final String? domain;
  final DateTime? startsAt;
  final double? amountPaid;

  /// Null when [billingPeriod] is `perpetual` — no expiry.
  final DateTime? expiresAt;

  /// Last time the self-hosted install checked in; null if it never has.
  final DateTime? lastValidatedAt;
  final String? notes;
  final int activationsCount;
  final DateTime? createdAt;

  factory License.fromJson(Map<String, dynamic> json) => License(
    id: json.id(),
    licenseKey: json.strOr('license_key', ''),
    customerName: json.strOr('customer_name', '—'),
    customerEmail: json.strOr('customer_email', ''),
    product: json.strOr('product', LicensePackages.general),
    billingPeriod: json.strOr('billing_period', LicenseBillingPeriods.annual),
    status: json.strOr('status', 'active'),
    domain: json.str('domain'),
    startsAt: json.date('starts_at'),
    amountPaid: json['amount_paid'] == null ? null : json.money('amount_paid'),
    expiresAt: json.date('expires_at'),
    lastValidatedAt: json.date('last_validated_at'),
    notes: json.str('notes'),
    activationsCount: json.count('activations_count'),
    createdAt: json.date('created_at'),
  );
}

/// Pricing for self-hosted licenses, one row per [LicensePackages] value —
/// separate from [PlatformPlan], which prices MoBilling SaaS itself. Rows are
/// seeded; only their prices/description are ever edited.
class LicensePlan {
  const LicensePlan({
    required this.id,
    required this.product,
    required this.name,
    required this.isActive,
    this.description,
    this.monthlyPrice,
    this.quarterlyPrice,
    this.semiAnnualPrice,
    this.annualPrice,
    this.perpetualPrice,
  });

  final String id;
  final String product;
  final String name;
  final bool isActive;
  final String? description;
  final double? monthlyPrice;
  final double? quarterlyPrice;
  final double? semiAnnualPrice;
  final double? annualPrice;
  final double? perpetualPrice;

  /// The list price for one billing period, or null if that period isn't
  /// offered for this package.
  double? priceFor(String billingPeriod) => switch (billingPeriod) {
    LicenseBillingPeriods.monthly => monthlyPrice,
    LicenseBillingPeriods.quarterly => quarterlyPrice,
    LicenseBillingPeriods.semiAnnual => semiAnnualPrice,
    LicenseBillingPeriods.annual => annualPrice,
    LicenseBillingPeriods.perpetual => perpetualPrice,
    _ => null,
  };

  factory LicensePlan.fromJson(Map<String, dynamic> json) => LicensePlan(
    id: json.id(),
    product: json.strOr('product', LicensePackages.general),
    name: json.strOr('name', '—'),
    isActive: json.flag('is_active', fallback: true),
    description: json.str('description'),
    monthlyPrice: json['monthly_price'] == null
        ? null
        : json.money('monthly_price'),
    quarterlyPrice: json['quarterly_price'] == null
        ? null
        : json.money('quarterly_price'),
    semiAnnualPrice: json['semi_annual_price'] == null
        ? null
        : json.money('semi_annual_price'),
    annualPrice: json['annual_price'] == null
        ? null
        : json.money('annual_price'),
    perpetualPrice: json['perpetual_price'] == null
        ? null
        : json.money('perpetual_price'),
  );
}

/// One row in the "Check for Updates" catalog self-hosted installs compare
/// their version against — the newest active row is the latest.
class Release {
  const Release({
    required this.id,
    required this.version,
    required this.isActive,
    required this.releasedAt,
    this.changelog,
    this.downloadUrl,
  });

  final String id;
  final String version;
  final bool isActive;
  final DateTime? releasedAt;
  final String? changelog;
  final String? downloadUrl;

  factory Release.fromJson(Map<String, dynamic> json) => Release(
    id: json.id(),
    version: json.strOr('version', '—'),
    isActive: json.flag('is_active', fallback: true),
    releasedAt: json.date('released_at'),
    changelog: json.str('changelog'),
    downloadUrl: json.str('download_url'),
  );
}

// ---------------------------------------------------------------------------
// Role templates — RoleTemplateController (edit support)
//
// The three global role types (super_admin, admin, user) every new tenant is
// seeded with. Distinct from a tenant's own custom roles (`StaffRole` /
// `/roles`) and from per-tenant permission grants — this is the
// platform-wide *default*, editable only for `admin` and `user` (the
// `super_admin` type bypasses all permission checks, so it isn't a template
// to edit).
// ---------------------------------------------------------------------------

/// One row of `GET /admin/role-templates` — summary counts only. Replaces an
/// earlier, incorrect reuse of [StaffRole] for this list: that shape has no
/// `name`/`permissions` keys matching what `RoleTemplateController::index`
/// actually sends (`type`, `label`, `permissions_count`, `tenants_count`,
/// `editable`), which silently rendered "0 permissions" on every row and, more
/// importantly, had nowhere to carry [type] — the slug the edit endpoint
/// needs. See [RoleTemplateDetail] for the full permission checklist.
class RoleTemplate {
  const RoleTemplate({
    required this.type,
    required this.label,
    required this.permissionsCount,
    required this.totalPermissions,
    required this.editable,
    this.description,
    this.tenantsCount,
  });

  /// super_admin | admin | user — the slug `PUT /admin/role-templates/{type}`
  /// takes.
  final String type;
  final String label;
  final String? description;

  /// The intersection across every tenant's system role of this [type] —
  /// less than [totalPermissions] once tenants have drifted apart on it.
  final int permissionsCount;
  final int totalPermissions;

  /// Null for `super_admin`, which isn't backed by per-tenant role rows.
  final int? tenantsCount;

  /// False only for `super_admin` — `RoleTemplateController::update` 422s on
  /// any other value, so the edit action is hidden rather than offered and
  /// refused.
  final bool editable;

  factory RoleTemplate.fromJson(Map<String, dynamic> json) => RoleTemplate(
    type: json.strOr('type', ''),
    label: json.strOr('label', '—'),
    description: json.str('description'),
    permissionsCount: json.count('permissions_count'),
    totalPermissions: json.count('total_permissions'),
    tenantsCount: json['tenants_count'] == null
        ? null
        : json.count('tenants_count'),
    editable: json.flag('editable'),
  );
}

/// `GET /admin/role-templates/{type}` — the full permission catalogue plus
/// which ids this template currently grants, for the edit checklist. Reuses
/// [PermissionCatalogue]'s `{category: {group: [...]}}` parsing: the
/// controller's `grouped_permissions` key nests exactly the same way.
class RoleTemplateDetail {
  const RoleTemplateDetail({
    required this.type,
    required this.catalogue,
    required this.enabledIds,
  });

  final String type;
  final PermissionCatalogue catalogue;
  final Set<String> enabledIds;

  factory RoleTemplateDetail.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    final grouped = data.object('grouped_permissions') ?? const {};
    final ids = data['enabled_ids'];
    return RoleTemplateDetail(
      type: data.strOr('type', ''),
      catalogue: PermissionCatalogue.fromJson({'data': grouped}),
      enabledIds: ids is List ? ids.map((e) => e.toString()).toSet() : const {},
    );
  }
}
