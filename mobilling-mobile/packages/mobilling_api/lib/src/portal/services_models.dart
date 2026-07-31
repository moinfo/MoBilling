/// Services-area models: subscriptions, hosting accounts, domains.
/// Shapes match `PortalSubscriptionController`, `PortalHostingController`
/// and `PortalDomainController`.
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Subscriptions — GET /portal/subscriptions (raw models + computed fields)
// ---------------------------------------------------------------------------

class ClientSubscription {
  const ClientSubscription({
    required this.id,
    required this.status,
    required this.quantity,
    required this.price,
    this.label,
    this.productName,
    this.productType,
    this.billingCycle,
    this.startDate,
    this.expireDate,
    this.nextInvoiceDate,
    this.hostingAccountId,
  });

  final String id;
  final String status;
  final int quantity;
  final double price;
  final String? label;
  final String? productName;
  final String? productType;
  final String? billingCycle;
  final DateTime? startDate;
  final DateTime? expireDate;
  final DateTime? nextInvoiceDate;

  /// Present (and active) when this subscription is a hosting product —
  /// enables the jump to the hosting detail screen.
  final String? hostingAccountId;

  factory ClientSubscription.fromJson(Map<String, dynamic> json) {
    final product = json.object('product_service');
    final hosting = json.object('hosting_account');
    return ClientSubscription(
      id: json.id(),
      status: json.strOr('status', 'active'),
      quantity: json.count('quantity', fallback: 1),
      price: readDouble(product?['price']),
      label: json.str('label'),
      productName: product?.str('name'),
      productType: product?.str('type'),
      billingCycle: json.str('billing_cycle') ?? product?.str('billing_cycle'),
      startDate: json.date('start_date'),
      expireDate: json.date('expire_date'),
      nextInvoiceDate: json.date('next_invoice_date'),
      hostingAccountId:
          hosting?.strOr('status', '') == 'active' ? hosting?.str('id') : null,
    );
  }
}

/// Result of "generate invoice now" on a subscription or of a domain renewal /
/// hosting upgrade — all three return a freshly created invoice reference.
class CreatedInvoiceRef {
  const CreatedInvoiceRef({
    required this.documentId,
    required this.documentNumber,
    this.total,
    this.message,
  });

  final String documentId;
  final String documentNumber;
  final double? total;
  final String? message;

  factory CreatedInvoiceRef.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return CreatedInvoiceRef(
      documentId: data.id('document_id'),
      documentNumber: data.strOr('document_number', '—'),
      total: data['total'] == null ? null : data.money('total'),
      message: json.str('message'),
    );
  }
}

// ---------------------------------------------------------------------------
// Hosting — GET /portal/hosting
// ---------------------------------------------------------------------------

class HostingAccount {
  const HostingAccount({
    required this.id,
    required this.status,
    this.domain,
    this.cpanelUsername,
    this.package,
    this.diskUsed,
    this.diskLimit,
    this.serverHostname,
    this.expiresAt,
  });

  final String id;
  final String status;
  final String? domain;
  final String? cpanelUsername;
  final String? package;

  /// Usage strings straight from cPanel (e.g. "512M", "10240M") — displayed,
  /// not parsed.
  final String? diskUsed;
  final String? diskLimit;
  final String? serverHostname;
  final DateTime? expiresAt;

  factory HostingAccount.fromJson(Map<String, dynamic> json) => HostingAccount(
        id: json.id(),
        status: json.strOr('status', 'active'),
        domain: json.str('domain'),
        cpanelUsername: json.str('cpanel_username'),
        package: json.str('package'),
        diskUsed: json.str('disk_used'),
        diskLimit: json.str('disk_limit'),
        serverHostname: json.str('server_hostname'),
        expiresAt: json.date('expires_at'),
      );
}

class HostingDetail {
  const HostingDetail({
    required this.id,
    required this.status,
    required this.shortcuts,
    this.domain,
    this.cpanelUsername,
    this.package,
    this.productName,
    this.price,
    this.billingCycle,
    this.registeredAt,
    this.nextDue,
    this.diskUsed,
    this.diskLimit,
    this.lastSyncedAt,
  });

  final String id;
  final String status;

  /// Deep-link targets the SSO endpoint accepts as `goto` (email, files…).
  final List<String> shortcuts;
  final String? domain;
  final String? cpanelUsername;
  final String? package;
  final String? productName;
  final double? price;
  final String? billingCycle;
  final DateTime? registeredAt;
  final DateTime? nextDue;
  final String? diskUsed;
  final String? diskLimit;
  final DateTime? lastSyncedAt;

  factory HostingDetail.fromJson(Map<String, dynamic> json) => HostingDetail(
        id: json.id(),
        status: json.strOr('status', 'active'),
        shortcuts: json.strings('shortcuts'),
        domain: json.str('domain'),
        cpanelUsername: json.str('cpanel_username'),
        package: json.str('package'),
        productName: json.str('product_name'),
        price: json['price'] == null ? null : json.money('price'),
        billingCycle: json.str('billing_cycle'),
        registeredAt: json.date('registered_at'),
        nextDue: json.date('next_due'),
        diskUsed: json.str('disk_used'),
        diskLimit: json.str('disk_limit'),
        lastSyncedAt: json.date('last_synced_at'),
      );
}

class HostingUpgradeOptions {
  const HostingUpgradeOptions({
    required this.currentPlan,
    required this.plans,
    this.nextDue,
  });

  final String currentPlan;
  final List<HostingPlanOption> plans;
  final DateTime? nextDue;

  factory HostingUpgradeOptions.fromJson(Map<String, dynamic> json) =>
      HostingUpgradeOptions(
        currentPlan: json.strOr('current_plan', '—'),
        plans: json.list('plans', HostingPlanOption.fromJson),
        nextDue: json.date('next_due'),
      );
}

class HostingPlanOption {
  const HostingPlanOption({
    required this.id,
    required this.name,
    required this.price,
    required this.isCurrent,
    required this.dueNow,
    required this.credit,
    this.billingCycle,
  });

  final String id;
  final String name;
  final double price;
  final bool isCurrent;

  /// Prorated charge to switch now; 0 means the change applies immediately
  /// (downgrades), > 0 means an invoice is created and applies once paid.
  final double dueNow;
  final double credit;
  final String? billingCycle;

  factory HostingPlanOption.fromJson(Map<String, dynamic> json) =>
      HostingPlanOption(
        id: json.id(),
        name: json.strOr('name', '—'),
        price: json.money('price'),
        isCurrent: json.flag('is_current'),
        dueNow: json.money('due_now'),
        credit: json.money('credit'),
        billingCycle: json.str('billing_cycle'),
      );
}

// ---------------------------------------------------------------------------
// Domains — GET /portal/domains
// ---------------------------------------------------------------------------

class PortalDomain {
  const PortalDomain({
    required this.id,
    required this.name,
    required this.status,
    required this.autoRenew,
    required this.expiringSoon,
    required this.unmanaged,
    this.registeredAt,
    this.expiresAt,
    this.sslValid,
    this.sslExpiresAt,
  });

  final String id;
  final String name;
  final String status;
  final bool autoRenew;

  /// Active and expiring within 45 days (server-computed).
  final bool expiringSoon;

  /// Imported/manually-renewed domains: renew/EPP/nameservers are disabled.
  final bool unmanaged;
  final DateTime? registeredAt;
  final DateTime? expiresAt;
  final bool? sslValid;
  final DateTime? sslExpiresAt;

  factory PortalDomain.fromJson(Map<String, dynamic> json) => PortalDomain(
        id: json.id(),
        name: json.strOr('name', '—'),
        status: json.strOr('status', 'active'),
        autoRenew: json.flag('auto_renew'),
        expiringSoon: json.flag('expiring_soon'),
        unmanaged: json.flag('unmanaged'),
        registeredAt: json.date('registered_at'),
        expiresAt: json.date('expires_at'),
        sslValid: json['ssl_valid'] == null ? null : json.flag('ssl_valid'),
        sslExpiresAt: json.date('ssl_expires_at'),
      );
}

class DomainStats {
  const DomainStats({
    required this.active,
    required this.expired,
    required this.expiringSoon,
    required this.pending,
  });

  final int active;
  final int expired;
  final int expiringSoon;
  final int pending;

  factory DomainStats.fromJson(Map<String, dynamic> json) => DomainStats(
        active: json.count('active'),
        expired: json.count('expired'),
        expiringSoon: json.count('expiring_soon'),
        pending: json.count('pending'),
      );
}

class DomainList {
  const DomainList({required this.domains, required this.stats});

  final List<PortalDomain> domains;
  final DomainStats stats;

  factory DomainList.fromJson(Map<String, dynamic> json) => DomainList(
        domains: json.list('data', PortalDomain.fromJson),
        stats: DomainStats.fromJson(json.object('stats') ?? const {}),
      );
}

class DomainBilling {
  const DomainBilling({
    this.firstPayment,
    this.recurring,
    this.cycle,
    this.paymentMethod,
  });

  final double? firstPayment;
  final double? recurring;
  final String? cycle;
  final String? paymentMethod;

  factory DomainBilling.fromJson(Map<String, dynamic> json) => DomainBilling(
        firstPayment:
            json['first_payment'] == null ? null : json.money('first_payment'),
        recurring: json['recurring'] == null ? null : json.money('recurring'),
        cycle: json.str('cycle'),
        paymentMethod: json.str('payment_method'),
      );
}

class DomainDetail {
  const DomainDetail({
    required this.id,
    required this.name,
    required this.status,
    required this.autoRenew,
    required this.unmanaged,
    this.registeredAt,
    this.expiresAt,
    this.billing,
    this.sslValid,
    this.sslIssuer,
    this.sslExpiresAt,
  });

  final String id;
  final String name;
  final String status;
  final bool autoRenew;
  final bool unmanaged;
  final DateTime? registeredAt;
  final DateTime? expiresAt;
  final DomainBilling? billing;
  final bool? sslValid;
  final String? sslIssuer;
  final DateTime? sslExpiresAt;

  factory DomainDetail.fromJson(Map<String, dynamic> json) {
    final ssl = json.object('ssl');
    return DomainDetail(
      id: json.id(),
      name: json.strOr('name', '—'),
      status: json.strOr('status', 'active'),
      autoRenew: json.flag('auto_renew'),
      unmanaged: json.flag('unmanaged'),
      registeredAt: json.date('registered_at'),
      expiresAt: json.date('expires_at'),
      billing: json.object('billing') == null
          ? null
          : DomainBilling.fromJson(json.object('billing')!),
      sslValid: ssl?['valid'] == null ? null : ssl!.flag('valid'),
      sslIssuer: ssl?.str('issuer'),
      sslExpiresAt: readDate(ssl?['expires_at']),
    );
  }
}

class DomainNameservers {
  const DomainNameservers({required this.nameservers, required this.editable});

  final List<String> nameservers;

  /// False for non-.tz, unmanaged, or registry-locked domains.
  final bool editable;

  factory DomainNameservers.fromJson(Map<String, dynamic> json) =>
      DomainNameservers(
        nameservers: json.strings('nameservers'),
        editable: json.flag('editable'),
      );
}
