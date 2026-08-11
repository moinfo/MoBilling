/// Platform super-admin models — the `/admin/*` area.
///
/// This is MoBilling operating its own product: tenants, the plans they buy,
/// the SMS credit they consume, and platform-wide configuration. Everything
/// here sits behind `EnsureSuperAdmin`, and a super admin has **no tenant**,
/// so nothing in this file assumes tenant scoping.
library;

import '../json.dart';

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
      recentPurchases: data.list('recent_purchases', PlatformSmsPurchase.fromJson),
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
        customDomain: json.str('custom_domain'),
        currency: json.str('currency'),
        subscriptionStatus: json.str('subscription_status'),
        daysRemaining:
            json['days_remaining'] == null ? null : json.count('days_remaining'),
        smsBalance:
            json['sms_balance'] == null ? null : json.count('sms_balance'),
        usersCount:
            json['users_count'] == null ? null : json.count('users_count'),
        createdAt: json.date('created_at'),
      );
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
        durationDays:
            json['duration_days'] == null ? null : json.count('duration_days'),
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

  factory PlatformSmsPurchase.fromJson(Map<String, dynamic> json) => PlatformSmsPurchase(
        id: json.id(),
        smsQuantity: json.count('sms_quantity'),
        totalAmount: json.money('total_amount'),
        status: json.strOr('status', 'pending'),
        tenantName: json.str('tenant_name') ??
            json.object('tenant')?.str('name'),
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
    return PlatformSettings(values: {
      for (final entry in data.entries)
        if (entry.value != null && entry.value is! Map && entry.value is! List)
          entry.key: entry.value.toString(),
    });
  }
}
