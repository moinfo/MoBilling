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

  /// active | trial | expired | none — computed by `Tenant::subscriptionStatus()`.
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
      billingCycle: plan?.str('billing_cycle'),
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

  factory CronLogEntry.fromJson(Map<String, dynamic> json) => CronLogEntry(
        id: json.id(),
        job: json.strOr('job', json.strOr('name', '—')),
        status: json.strOr('status', 'success'),
        message: json.str('message') ?? json.str('output'),
        ranAt: json.date('ran_at') ?? json.date('created_at'),
        durationMs:
            json['duration_ms'] == null ? null : json.count('duration_ms'),
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
      roleName: role?.str('name'),
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
    this.description,
  });

  final String id;
  final String name;

  /// System roles ship with the platform and cannot be deleted.
  final bool isSystem;
  final int usersCount;
  final List<String> permissionNames;
  final String? description;

  factory StaffRole.fromJson(Map<String, dynamic> json) => StaffRole(
        id: json.id(),
        name: json.strOr('name', '—'),
        isSystem: json.flag('is_system'),
        usersCount: json.count('users_count'),
        permissionNames: json
            .list('permissions', (p) => p.strOr('name', ''))
            .where((n) => n.isNotEmpty)
            .toList(growable: false),
        description: json.str('description'),
      );
}

/// A permission, as returned by `/permissions`.
class PermissionInfo {
  const PermissionInfo({required this.name, this.label, this.group});

  final String name;
  final String? label;

  /// Derived from the name's prefix when the API doesn't group them.
  final String? group;

  String get displayGroup =>
      group ?? (name.contains('.') ? name.split('.').first : 'general');

  String get displayLabel =>
      label ?? name.split('.').last.replaceAll('_', ' ');

  factory PermissionInfo.fromJson(Map<String, dynamic> json) => PermissionInfo(
        name: json.strOr('name', ''),
        label: json.str('label') ?? json.str('description'),
        group: json.str('group') ?? json.str('category'),
      );
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
