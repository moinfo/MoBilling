/// Admin "Products / Services" management — `HostingServiceController`.
///
/// This is the WHMCS Client Profile → service tab: one client's subscriptions,
/// and per subscription the editable billing record plus the cPanel account it
/// provisioned. It is deliberately separate from [StaffHostingAccount] in
/// `support_admin_models.dart`: that one is the tenant-wide server view, this
/// one is the *billing* record and only mentions the account as context.
///
/// Parsing notes, all learned from `show()`:
///   * amounts are `(float)` cast on the happy path but fall through to the
///     subscription's `decimal:2` cast — i.e. a JSON string — whenever the
///     value comes off the model rather than the derived branch, so every
///     money field goes through [JsonMap.money];
///   * dates are bare `Y-m-d` strings from `toDateString()`, except
///     `last_synced_at` / `ssl.expires_at`, which are ISO-8601;
///   * `ssl.valid` is a genuine tri-state — true, false, or "never checked" —
///     and must not collapse to false, so it is read by hand rather than with
///     [JsonMap.flag].
library;

import '../json.dart';

// ---------------------------------------------------------------------------
// Selector list — GET /hosting-services?client_id=
// ---------------------------------------------------------------------------

/// One of a client's services, as the picker list shows it.
///
/// `domain` is the hosting account's domain when there is one and the
/// subscription's own label otherwise, so it is the right thing to title a row
/// with for non-hosting services too.
class ClientServiceRow {
  const ClientServiceRow({
    required this.id,
    required this.productName,
    required this.status,
    required this.hasAccount,
    this.domain,
  });

  /// The client_subscription id — every other route here keys off it.
  final String id;
  final String productName;
  final String status;

  /// False when nothing was ever provisioned on a server: the module commands
  /// have nothing to act on.
  final bool hasAccount;
  final String? domain;

  factory ClientServiceRow.fromJson(Map<String, dynamic> json) =>
      ClientServiceRow(
        id: json.id(),
        productName: json.strOr('product_name', 'Service'),
        status: json.strOr('status', 'pending'),
        hasAccount: json.flag('has_account'),
        domain: json.str('domain'),
      );
}

// ---------------------------------------------------------------------------
// Detail — GET/PUT /hosting-services/{clientSubscription}
// ---------------------------------------------------------------------------

/// The linked cPanel account, as much of it as the service view needs.
class HostingServiceAccount {
  const HostingServiceAccount({
    required this.id,
    required this.status,
    required this.notOnWhm,
    this.serverId,
    this.serverHost,
    this.lastSyncedAt,
  });

  final String id;
  final String status;

  /// Imported billing-only rows: the account exists here but not on any WHM,
  /// so SSO and the module commands would fail.
  final bool notOnWhm;
  final String? serverId;
  final String? serverHost;
  final DateTime? lastSyncedAt;

  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';

  /// The server can actually be commanded for this account.
  bool get isOnServer => !notOnWhm;

  factory HostingServiceAccount.fromJson(Map<String, dynamic> json) =>
      HostingServiceAccount(
        id: json.id(),
        status: json.strOr('status', 'active'),
        notOnWhm: json.flag('not_on_whm'),
        serverId: json.str('server_id'),
        serverHost: json.str('server_host'),
        lastSyncedAt: json.date('last_synced_at'),
      );
}

/// The cached certificate check. [valid] is null when nothing has looked yet.
class HostingServiceSsl {
  const HostingServiceSsl({this.valid, this.issuer, this.expiresAt});

  final bool? valid;
  final String? issuer;
  final DateTime? expiresAt;

  /// Nothing to report — don't draw a padlock either way.
  bool get unknown => valid == null;

  factory HostingServiceSsl.fromJson(Map<String, dynamic> json) =>
      HostingServiceSsl(
        // Tri-state: absent/null means "never checked", not "no SSL".
        valid: switch (json['valid']) {
          bool v => v,
          num v => v != 0,
          'true' || '1' => true,
          'false' || '0' => false,
          _ => null,
        },
        issuer: json.str('issuer'),
        expiresAt: json.date('expires_at'),
      );
}

/// One row of the metric-statistics table. `usage` is whatever cPanel said —
/// "1240M / 5120M", a plain count, or null when it was never synced — so it is
/// displayed, never parsed.
class HostingServiceMetric {
  const HostingServiceMetric({
    required this.metric,
    required this.enabled,
    this.usage,
    this.lastUpdate,
  });

  final String metric;
  final bool enabled;
  final String? usage;
  final DateTime? lastUpdate;

  factory HostingServiceMetric.fromJson(Map<String, dynamic> json) =>
      HostingServiceMetric(
        metric: json.strOr('metric', '—'),
        enabled: json.flag('enabled', fallback: true),
        usage: json.str('usage'),
        lastUpdate: json.date('last_update'),
      );
}

/// A server the service may be assigned to.
class HostingServerOption {
  const HostingServerOption({
    required this.id,
    required this.label,
    this.hostname,
  });

  final String id;

  /// Already formatted server-side as "host (n accounts)".
  final String label;
  final String? hostname;

  factory HostingServerOption.fromJson(Map<String, dynamic> json) =>
      HostingServerOption(
        id: json.id(),
        label: json.strOr('label', '—'),
        hostname: json.str('hostname'),
      );
}

/// A catalog product the service may be re-assigned to.
class HostingProductOption {
  const HostingProductOption({
    required this.id,
    required this.name,
    required this.price,
    this.billingCycle,
    this.cpanelPackage,
  });

  final String id;
  final String name;
  final double price;
  final String? billingCycle;

  /// The WHM package this plan provisions — the sensible default for the
  /// package field when the plan changes.
  final String? cpanelPackage;

  factory HostingProductOption.fromJson(Map<String, dynamic> json) =>
      HostingProductOption(
        id: json.id(),
        name: json.strOr('name', '—'),
        price: json.money('price'),
        billingCycle: json.str('billing_cycle'),
        cpanelPackage: json.str('cpanel_package'),
      );
}

/// The option lists the edit form's selects are built from. They ship with the
/// detail rather than from separate endpoints, so the form never has to guess
/// which statuses or payment methods the API will accept.
class HostingServiceOptions {
  const HostingServiceOptions({
    required this.servers,
    required this.products,
    required this.statuses,
    required this.billingCycles,
    required this.paymentMethods,
  });

  final List<HostingServerOption> servers;
  final List<HostingProductOption> products;
  final List<String> statuses;
  final List<String> billingCycles;
  final List<String> paymentMethods;

  factory HostingServiceOptions.fromJson(Map<String, dynamic> json) =>
      HostingServiceOptions(
        servers: json.list('servers', HostingServerOption.fromJson),
        products: json.list('products', HostingProductOption.fromJson),
        statuses: json.strings('statuses'),
        billingCycles: json.strings('billing_cycles'),
        paymentMethods: json.strings('payment_methods'),
      );
}

/// The full service record behind the edit form.
class HostingServiceDetail {
  const HostingServiceDetail({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.status,
    required this.quantity,
    required this.ssl,
    required this.metrics,
    required this.options,
    this.orderDocumentId,
    this.productServiceId,
    this.serverId,
    this.domain,
    this.dedicatedIp,
    this.username,
    this.package,
    this.startDate,
    this.firstPaymentAmount,
    this.recurringAmount,
    this.nextDueDate,
    this.terminationDate,
    this.billingCycle,
    this.paymentMethod,
    this.promoCode,
    this.hostingAccount,
  });

  /// The client_subscription id.
  final String id;
  final String clientId;
  final String clientName;

  /// The invoice the original order raised, when there was one.
  final String? orderDocumentId;

  // ── editable ──
  final String? productServiceId;
  final String? serverId;
  final String? domain;
  final String? dedicatedIp;
  final String? username;

  /// The WHM package name. Comes off the account when provisioned, off the
  /// product when not.
  final String? package;
  final String status;
  final DateTime? startDate;
  final int quantity;
  final double? firstPaymentAmount;
  final double? recurringAmount;
  final DateTime? nextDueDate;
  final DateTime? terminationDate;
  final String? paymentMethod;
  final String? promoCode;

  // ── read-only context ──

  /// From the product; the form shows it but cannot change it here.
  final String? billingCycle;
  final HostingServiceAccount? hostingAccount;
  final HostingServiceSsl ssl;
  final List<HostingServiceMetric> metrics;
  final HostingServiceOptions options;

  /// A title for the record: the domain if there is one, else the client.
  String get title => domain ?? clientName;

  /// The product row matching [productServiceId], when it is still in the
  /// catalog — the form's select needs the name, not the id.
  HostingProductOption? get product {
    for (final p in options.products) {
      if (p.id == productServiceId) return p;
    }
    return null;
  }

  factory HostingServiceDetail.fromJson(Map<String, dynamic> json) {
    final client = json.object('client');
    final account = json.object('hosting_account');
    return HostingServiceDetail(
      id: json.id(),
      clientId: client?.id() ?? '',
      clientName: client?.strOr('name', '—') ?? '—',
      orderDocumentId: json.str('order_document_id'),
      productServiceId: json.str('product_service_id'),
      serverId: json.str('server_id'),
      domain: json.str('domain'),
      dedicatedIp: json.str('dedicated_ip'),
      username: json.str('username'),
      package: json.str('package'),
      status: json.strOr('status', 'pending'),
      startDate: json.date('start_date'),
      quantity: json.count('quantity', fallback: 1),
      firstPaymentAmount: json['first_payment_amount'] == null
          ? null
          : json.money('first_payment_amount'),
      recurringAmount: json['recurring_amount'] == null
          ? null
          : json.money('recurring_amount'),
      nextDueDate: json.date('next_due_date'),
      terminationDate: json.date('termination_date'),
      billingCycle: json.str('billing_cycle'),
      paymentMethod: json.str('payment_method'),
      promoCode: json.str('promo_code'),
      hostingAccount: account == null
          ? null
          : HostingServiceAccount.fromJson(account),
      ssl: HostingServiceSsl.fromJson(json.object('ssl') ?? const {}),
      metrics: json.list('metrics', HostingServiceMetric.fromJson),
      options: HostingServiceOptions.fromJson(
        json.object('options') ?? const {},
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upgrade / downgrade — GET .../upgrade-options, POST .../upgrade
// ---------------------------------------------------------------------------

/// One plan the service can move to, with what the move costs today.
class ServiceUpgradePlan {
  const ServiceUpgradePlan({
    required this.id,
    required this.name,
    required this.price,
    required this.isCurrent,
    required this.direction,
    required this.proratedDue,
    required this.proratedCredit,
    this.billingCycle,
  });

  final String id;
  final String name;
  final double price;
  final bool isCurrent;

  /// `upgrade`, `downgrade` or `same`.
  final String direction;

  /// What the client owes now for the rest of the term. Zero means the change
  /// can simply be applied.
  final double proratedDue;

  /// What a downgrade refunds to the wallet, when credit-on-downgrade is on.
  final double proratedCredit;
  final String? billingCycle;

  factory ServiceUpgradePlan.fromJson(Map<String, dynamic> json) =>
      ServiceUpgradePlan(
        id: json.id(),
        name: json.strOr('name', '—'),
        price: json.money('price'),
        isCurrent: json.flag('is_current'),
        direction: json.strOr('direction', 'same'),
        proratedDue: json.money('prorated_due'),
        proratedCredit: json.money('prorated_credit'),
        billingCycle: json.str('billing_cycle'),
      );
}

/// The plan-change offer for one service.
class ServiceUpgradeOptions {
  const ServiceUpgradeOptions({
    required this.currentPlanId,
    required this.currentPlanName,
    required this.currentPlanPrice,
    required this.quantity,
    required this.plans,
    this.billingCycle,
    this.nextDueDate,
  });

  final String currentPlanId;
  final String currentPlanName;
  final double currentPlanPrice;
  final int quantity;

  /// Every plan in the group, the current one included — filter on
  /// [ServiceUpgradePlan.isCurrent] before offering them.
  final List<ServiceUpgradePlan> plans;
  final String? billingCycle;
  final DateTime? nextDueDate;

  factory ServiceUpgradeOptions.fromJson(Map<String, dynamic> json) {
    final current = json.object('current_plan');
    return ServiceUpgradeOptions(
      currentPlanId: current?.id() ?? '',
      currentPlanName: current?.strOr('name', '—') ?? '—',
      currentPlanPrice: current?.money('price') ?? 0,
      quantity: json.count('quantity', fallback: 1),
      plans: json.list('plans', ServiceUpgradePlan.fromJson),
      billingCycle: json.str('billing_cycle'),
      nextDueDate: json.date('next_due_date'),
    );
  }
}

/// What came back from applying a plan change: either the change is live, or
/// an invoice was raised and the change waits on payment.
class ServiceUpgradeResult {
  const ServiceUpgradeResult({
    required this.applied,
    required this.message,
    this.documentId,
    this.documentNumber,
    this.documentTotal,
  });

  /// True when the plan switched immediately; false when [documentId] names
  /// the prorated invoice that has to be paid first.
  final bool applied;
  final String message;
  final String? documentId;
  final String? documentNumber;
  final double? documentTotal;

  factory ServiceUpgradeResult.fromJson(Map<String, dynamic> json) {
    final document = json.object('document');
    return ServiceUpgradeResult(
      applied: json.flag('applied'),
      message: json.strOr('message', 'Plan change submitted.'),
      documentId: document?.id(),
      documentNumber: document?.str('number'),
      documentTotal: document?.money('total'),
    );
  }
}
