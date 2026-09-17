import '../json.dart';

/// A MikroTik router registered for hotspot voucher sales. The API password
/// is write-only — never returned, matching `MikrotikRouter::$hidden`.
class MikrotikRouter {
  const MikrotikRouter({
    required this.id,
    required this.name,
    required this.host,
    required this.apiPort,
    required this.username,
    required this.useTls,
    required this.paymentMode,
    required this.isActive,
    this.localLoginHost,
    this.lastTestedAt,
    this.lastTestStatus,
    this.lastTestMessage,
  });

  final String id;
  final String name;
  final String host;
  final int apiPort;
  final String username;
  final bool useTls;

  /// self_managed | platform_collected — who collects online voucher
  /// payments: the tenant's own Pesapal account, or MoBilling's (settled
  /// back to them later via [WifiEarningRow]).
  final String paymentMode;
  final bool isActive;

  /// The address customer devices see on the WiFi itself — lets the
  /// checkout page auto-connect them after payment instead of making them
  /// type the voucher code by hand. Optional.
  final String? localLoginHost;

  final DateTime? lastTestedAt;

  /// success | failed | null (never tested).
  final String? lastTestStatus;
  final String? lastTestMessage;

  bool get isPlatformCollected => paymentMode == 'platform_collected';

  factory MikrotikRouter.fromJson(Map<String, dynamic> json) => MikrotikRouter(
    id: json.id(),
    name: json.strOr('name', '—'),
    host: json.strOr('host', ''),
    apiPort: json.count('api_port', fallback: 8728),
    username: json.strOr('username', ''),
    useTls: json.flag('use_tls'),
    paymentMode: json.strOr('payment_mode', 'self_managed'),
    isActive: json.flag('is_active', fallback: true),
    localLoginHost: json.str('local_login_host'),
    lastTestedAt: json.date('last_tested_at'),
    lastTestStatus: json.str('last_test_status'),
    lastTestMessage: json.str('last_test_message'),
  );
}

abstract final class WifiPaymentModes {
  static const selfManaged = 'self_managed';
  static const platformCollected = 'platform_collected';

  static const values = <(String, String)>[
    (selfManaged, 'Self-managed'),
    (platformCollected, 'Platform-collected'),
  ];
}

/// A duration/data/speed bundle sold against one router's hotspot.
class WifiPlan {
  const WifiPlan({
    required this.id,
    required this.mikrotikRouterId,
    required this.name,
    required this.price,
    required this.isActive,
    this.routerName,
    this.durationValue,
    this.durationUnit,
    this.dataCapMb,
    this.speedLimitMbps,
    this.hotspotProfile,
  });

  final String id;
  final String mikrotikRouterId;
  final String? routerName;
  final String name;

  /// Null when the plan has no time limit (a pure data-cap plan) — a plan
  /// always carries at least one of {duration, data cap}, per
  /// `StoreWifiPlanRequest::rules`.
  final int? durationValue;

  /// hours | days | weeks.
  final String? durationUnit;

  /// Null = unlimited data.
  final int? dataCapMb;

  /// Symmetric up/down cap in Mbps; null = unlimited.
  final double? speedLimitMbps;
  final double price;
  final String? hotspotProfile;
  final bool isActive;

  String get durationLabel {
    if (durationValue == null || durationUnit == null) return 'No time limit';
    final unit = durationValue == 1
        ? durationUnit!.substring(0, durationUnit!.length - 1)
        : durationUnit!;
    return '$durationValue $unit';
  }

  String get dataCapLabel => dataCapMb == null
      ? 'Unlimited data'
      : dataCapMb! >= 1024
      ? '${(dataCapMb! / 1024).toStringAsFixed(dataCapMb! % 1024 == 0 ? 0 : 1)} GB'
      : '$dataCapMb MB';

  factory WifiPlan.fromJson(Map<String, dynamic> json) => WifiPlan(
    id: json.id(),
    mikrotikRouterId: json.strOr('mikrotik_router_id', ''),
    routerName: json.object('router')?.str('name'),
    name: json.strOr('name', '—'),
    durationValue: json['duration_value'] == null
        ? null
        : json.count('duration_value'),
    durationUnit: json.str('duration_unit'),
    dataCapMb: json['data_cap_mb'] == null ? null : json.count('data_cap_mb'),
    speedLimitMbps: json['speed_limit_mbps'] == null
        ? null
        : json.money('speed_limit_mbps'),
    price: json.money('price'),
    hotspotProfile: json.str('hotspot_profile'),
    isActive: json.flag('is_active', fallback: true),
  );
}

abstract final class WifiDurationUnits {
  static const values = <(String, String)>[
    ('hours', 'Hours'),
    ('days', 'Days'),
    ('weeks', 'Weeks'),
  ];
}

/// One voucher sold — online (Pesapal) or staff-recorded cash/manual
/// (`WifiVoucherPurchaseController::store`), both provisioned through the
/// same job so this model doesn't distinguish how the sale happened beyond
/// [paymentMethodUsed] being null for the online path.
class WifiVoucherPurchase {
  const WifiVoucherPurchase({
    required this.id,
    required this.customerPhone,
    required this.amount,
    required this.status,
    this.routerId,
    this.routerName,
    this.planId,
    this.planName,
    this.customerName,
    this.paymentMethodUsed,
    this.hotspotUsername,
    this.hotspotPassword,
    this.voucherExpiresAt,
    this.completedAt,
    this.blockedAt,
    this.blockedReason,
    this.createdAt,
  });

  final String id;
  final String? routerId;
  final String? routerName;
  final String? planId;
  final String? planName;
  final String customerPhone;
  final String? customerName;
  final double amount;

  /// pending | completed | failed.
  final String status;

  /// null when bought through the online checkout — only staff-recorded
  /// sales carry a method.
  final String? paymentMethodUsed;
  final String? hotspotUsername;
  final String? hotspotPassword;
  final DateTime? voucherExpiresAt;
  final DateTime? completedAt;
  final DateTime? blockedAt;
  final String? blockedReason;
  final DateTime? createdAt;

  bool get isBlocked => blockedAt != null;
  bool get isProvisioned => hotspotUsername != null;

  factory WifiVoucherPurchase.fromJson(Map<String, dynamic> json) {
    final router = json.object('router');
    final plan = json.object('plan');
    return WifiVoucherPurchase(
      id: json.id(),
      routerId: json.str('mikrotik_router_id') ?? router?.str('id'),
      routerName: router?.str('name'),
      planId: json.str('wifi_plan_id') ?? plan?.str('id'),
      planName: plan?.str('name'),
      customerPhone: json.strOr('customer_phone', ''),
      customerName: json.str('customer_name'),
      amount: json.money('amount'),
      status: json.strOr('status', 'pending'),
      paymentMethodUsed: json.str('payment_method_used'),
      hotspotUsername: json.str('hotspot_username'),
      hotspotPassword: json.str('hotspot_password'),
      voucherExpiresAt: json.date('voucher_expires_at'),
      completedAt: json.date('completed_at'),
      blockedAt: json.date('blocked_at'),
      blockedReason: json.str('blocked_reason'),
      createdAt: json.date('created_at'),
    );
  }
}

abstract final class WifiPaymentMethods {
  static const values = <(String, String)>[
    ('cash', 'Cash'),
    ('mpesa', 'M-Pesa / Mobile Money'),
    ('bank', 'Bank Transfer'),
    ('other', 'Other'),
  ];
}

/// `GET /wifi-voucher-purchases/{id}/usage` — live, queried straight from
/// the router on demand; MoBilling stores no running total of its own.
class WifiVoucherUsage {
  const WifiVoucherUsage({
    required this.routerReachable,
    this.dataCapMb,
    this.dataUsedMb,
    this.dataRemainingMb,
    this.durationSeconds,
    this.timeUsedSeconds,
    this.timeRemainingSeconds,
  });

  final int? dataCapMb;
  final double? dataUsedMb;
  final double? dataRemainingMb;
  final int? durationSeconds;
  final int? timeUsedSeconds;
  final int? timeRemainingSeconds;

  /// False means the figures below (if any) are stale — the router
  /// couldn't be reached just now.
  final bool routerReachable;

  factory WifiVoucherUsage.fromJson(Map<String, dynamic> json) =>
      WifiVoucherUsage(
        dataCapMb: json['data_cap_mb'] == null
            ? null
            : json.count('data_cap_mb'),
        dataUsedMb: json['data_used_mb'] == null
            ? null
            : json.money('data_used_mb'),
        dataRemainingMb: json['data_remaining_mb'] == null
            ? null
            : json.money('data_remaining_mb'),
        durationSeconds: json['duration_seconds'] == null
            ? null
            : json.count('duration_seconds'),
        timeUsedSeconds: json['time_used_seconds'] == null
            ? null
            : json.count('time_used_seconds'),
        timeRemainingSeconds: json['time_remaining_seconds'] == null
            ? null
            : json.count('time_remaining_seconds'),
        routerReachable: json.flag('router_reachable'),
      );
}

/// One row of `GET /wifi-earnings` — a platform-collected sale MoBilling
/// owes back to the tenant. Deliberately a separate flat shape from
/// [WifiVoucherPurchase] (the backend's own dedicated transform), not a
/// reuse of it.
class WifiEarningRow {
  const WifiEarningRow({
    required this.id,
    required this.customerPhone,
    required this.amount,
    this.routerName,
    this.planName,
    this.commissionAmount,
    this.netAmount,
    this.completedAt,
    this.settledAt,
    this.settlementMethod,
    this.settlementReference,
  });

  final String id;
  final String? routerName;
  final String? planName;
  final String customerPhone;
  final double amount;
  final double? commissionAmount;
  final double? netAmount;
  final DateTime? completedAt;
  final DateTime? settledAt;
  final String? settlementMethod;
  final String? settlementReference;

  bool get isSettled => settledAt != null;

  factory WifiEarningRow.fromJson(Map<String, dynamic> json) =>
      WifiEarningRow(
        id: json.id(),
        routerName: json.object('router')?.str('name'),
        planName: json.object('plan')?.str('name'),
        customerPhone: json.strOr('customer_phone', ''),
        amount: json.money('amount'),
        commissionAmount: json['commission_amount'] == null
            ? null
            : json.money('commission_amount'),
        netAmount: json['net_amount'] == null
            ? null
            : json.money('net_amount'),
        completedAt: json.date('completed_at'),
        settledAt: json.date('settled_at'),
        settlementMethod: json.str('settlement_method'),
        settlementReference: json.str('settlement_reference'),
      );
}

/// `GET /wifi-earnings/summary`.
class WifiEarningsSummary {
  const WifiEarningsSummary({
    required this.owed,
    required this.unsettledCount,
    required this.totalSettled,
  });

  final double owed;
  final int unsettledCount;
  final double totalSettled;

  factory WifiEarningsSummary.fromJson(Map<String, dynamic> json) =>
      WifiEarningsSummary(
        owed: json.money('owed'),
        unsettledCount: json.count('unsettled_count'),
        totalSettled: json.money('total_settled'),
      );
}
