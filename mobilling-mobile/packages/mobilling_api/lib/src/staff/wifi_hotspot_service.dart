import '../api_client.dart';
import '../json.dart';
import '../paginated.dart';
import 'wifi_hotspot_models.dart';

/// The WiFi hotspot voucher business: MikroTik routers, the plans sold
/// against them, the vouchers customers buy, and (for `platform_collected`
/// routers) what MoBilling owes the tenant back.
class WifiHotspotService {
  const WifiHotspotService(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------------
  // Routers
  // ---------------------------------------------------------------------

  /// GET /mikrotik-routers — needs `wifi_routers.read`.
  Future<Paginated<MikrotikRouter>> routers({
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _api.get<dynamic>(
      '/mikrotik-routers',
      query: {'search': search, 'page': page, 'per_page': perPage},
    );
    return Paginated.fromJson(body, MikrotikRouter.fromJson);
  }

  /// POST /mikrotik-routers — needs `wifi_routers.create`.
  Future<MikrotikRouter> createRouter({
    required String name,
    required String host,
    required String username,
    required String password,
    String? localLoginHost,
    int apiPort = 8728,
    bool useTls = false,
    String paymentMode = WifiPaymentModes.selfManaged,
    bool isActive = true,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/mikrotik-routers',
      body: {
        'name': name,
        'host': host,
        'local_login_host': ?localLoginHost,
        'api_port': apiPort,
        'username': username,
        'password': password,
        'use_tls': useTls,
        'payment_mode': paymentMode,
        'is_active': isActive,
      },
    );
    return MikrotikRouter.fromJson(_unwrap(body));
  }

  /// PUT /mikrotik-routers/{id} — needs `wifi_routers.update`. A blank
  /// [password] keeps the one already on file.
  Future<MikrotikRouter> updateRouter(
    String id, {
    required String name,
    required String host,
    required String username,
    String? password,
    String? localLoginHost,
    int apiPort = 8728,
    bool useTls = false,
    String paymentMode = WifiPaymentModes.selfManaged,
    bool isActive = true,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/mikrotik-routers/$id',
      body: {
        'name': name,
        'host': host,
        'local_login_host': ?localLoginHost,
        'api_port': apiPort,
        'username': username,
        'password': ?password,
        'use_tls': useTls,
        'payment_mode': paymentMode,
        'is_active': isActive,
      },
    );
    return MikrotikRouter.fromJson(_unwrap(body));
  }

  /// DELETE /mikrotik-routers/{id} — needs `wifi_routers.delete`. Any plans
  /// on this router stop working too.
  Future<void> deleteRouter(String id) =>
      _api.delete<dynamic>('/mikrotik-routers/$id');

  /// POST /mikrotik-routers/{id}/test — needs `wifi_routers.update`. Live
  /// connection check; the result is also persisted as
  /// `last_test_status`/`last_test_message` on the router itself. Throws
  /// [ApiException] on a 422 (connection failed) same as any other error —
  /// callers read `e.message` for the reason.
  Future<String> testRouter(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/mikrotik-routers/$id/test',
    );
    return _unwrap(body).strOr('message', 'Connected.');
  }

  // ---------------------------------------------------------------------
  // Plans
  // ---------------------------------------------------------------------

  /// GET /wifi-plans — needs `wifi_plans.read`.
  Future<Paginated<WifiPlan>> plans({
    String? mikrotikRouterId,
    int page = 1,
    int perPage = 50,
  }) async {
    final body = await _api.get<dynamic>(
      '/wifi-plans',
      query: {
        'mikrotik_router_id': mikrotikRouterId,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, WifiPlan.fromJson);
  }

  /// POST /wifi-plans — needs `wifi_plans.create`. Needs at least one of
  /// [durationValue]+[durationUnit] or [dataCapMb].
  Future<WifiPlan> createPlan({
    required String mikrotikRouterId,
    required String name,
    required double price,
    int? durationValue,
    String? durationUnit,
    int? dataCapMb,
    double? speedLimitMbps,
    String? hotspotProfile,
    bool isActive = true,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/wifi-plans',
      body: {
        'mikrotik_router_id': mikrotikRouterId,
        'name': name,
        'duration_value': ?durationValue,
        'duration_unit': ?durationUnit,
        'data_cap_mb': ?dataCapMb,
        'speed_limit_mbps': ?speedLimitMbps,
        'price': price,
        'hotspot_profile': ?hotspotProfile,
        'is_active': isActive,
      },
    );
    return WifiPlan.fromJson(_unwrap(body));
  }

  /// PUT /wifi-plans/{id} — needs `wifi_plans.update`.
  Future<WifiPlan> updatePlan(
    String id, {
    required String mikrotikRouterId,
    required String name,
    required double price,
    int? durationValue,
    String? durationUnit,
    int? dataCapMb,
    double? speedLimitMbps,
    String? hotspotProfile,
    bool isActive = true,
  }) async {
    final body = await _api.put<Map<String, dynamic>>(
      '/wifi-plans/$id',
      body: {
        'mikrotik_router_id': mikrotikRouterId,
        'name': name,
        'duration_value': ?durationValue,
        'duration_unit': ?durationUnit,
        'data_cap_mb': ?dataCapMb,
        'speed_limit_mbps': ?speedLimitMbps,
        'price': price,
        'hotspot_profile': ?hotspotProfile,
        'is_active': isActive,
      },
    );
    return WifiPlan.fromJson(_unwrap(body));
  }

  /// DELETE /wifi-plans/{id} — needs `wifi_plans.delete`.
  Future<void> deletePlan(String id) => _api.delete<dynamic>('/wifi-plans/$id');

  // ---------------------------------------------------------------------
  // Voucher sales
  // ---------------------------------------------------------------------

  /// GET /wifi-voucher-purchases — needs `wifi_purchases.read`.
  Future<Paginated<WifiVoucherPurchase>> voucherPurchases({
    String? mikrotikRouterId,
    String? status,
    String? search,
    int page = 1,
    int perPage = 25,
  }) async {
    final body = await _api.get<dynamic>(
      '/wifi-voucher-purchases',
      query: {
        'mikrotik_router_id': mikrotikRouterId,
        'status': status,
        'search': search,
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, WifiVoucherPurchase.fromJson);
  }

  /// POST /wifi-voucher-purchases — needs `wifi_purchases.create`. A
  /// staff-recorded cash (or other non-online) sale: marks the purchase
  /// completed immediately and provisions + sends the code the same way an
  /// online payment would.
  Future<WifiVoucherPurchase> sellVoucher({
    required String mikrotikRouterId,
    required String wifiPlanId,
    required String customerPhone,
    required String paymentMethod,
    String? customerName,
  }) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/wifi-voucher-purchases',
      body: {
        'mikrotik_router_id': mikrotikRouterId,
        'wifi_plan_id': wifiPlanId,
        'customer_phone': customerPhone,
        'customer_name': ?customerName,
        'payment_method': paymentMethod,
      },
    );
    return WifiVoucherPurchase.fromJson(_unwrap(body));
  }

  /// GET /wifi-voucher-purchases/{id}/usage — needs `wifi_purchases.read`.
  /// 422s with a plain message if the voucher was never provisioned.
  Future<WifiVoucherUsage> voucherUsage(String id) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/wifi-voucher-purchases/$id/usage',
    );
    return WifiVoucherUsage.fromJson(_unwrap(body));
  }

  /// POST /wifi-voucher-purchases/{id}/block — needs `wifi_purchases.update`.
  /// Immediately disables and kicks the customer's hotspot login; does not
  /// touch the payment record itself.
  Future<WifiVoucherPurchase> blockVoucher(String id, {String? reason}) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/wifi-voucher-purchases/$id/block',
      body: {'reason': ?reason},
    );
    return WifiVoucherPurchase.fromJson(_unwrap(body));
  }

  /// POST /wifi-voucher-purchases/{id}/unblock — needs
  /// `wifi_purchases.update`.
  Future<WifiVoucherPurchase> unblockVoucher(String id) async {
    final body = await _api.post<Map<String, dynamic>>(
      '/wifi-voucher-purchases/$id/unblock',
    );
    return WifiVoucherPurchase.fromJson(_unwrap(body));
  }

  // ---------------------------------------------------------------------
  // Earnings (platform_collected routers only)
  // ---------------------------------------------------------------------

  /// GET /wifi-earnings/summary — needs `wifi_purchases.read`.
  Future<WifiEarningsSummary> earningsSummary() async {
    final body = await _api.get<Map<String, dynamic>>('/wifi-earnings/summary');
    return WifiEarningsSummary.fromJson(_unwrap(body));
  }

  /// GET /wifi-earnings — needs `wifi_purchases.read`.
  Future<Paginated<WifiEarningRow>> earnings({
    bool? settled,
    int page = 1,
    int perPage = 25,
  }) async {
    final body = await _api.get<dynamic>(
      '/wifi-earnings',
      query: {
        'settled': settled?.toString(),
        'page': page,
        'per_page': perPage,
      },
    );
    return Paginated.fromJson(body, WifiEarningRow.fromJson);
  }

  /// POST /wifi-earnings/request-payout — needs `wifi_purchases.read`. Pings
  /// MoInfoTech's super admins; there is no automated disbursement, this
  /// just asks a human to process it. Returns the API's confirmation
  /// message.
  Future<String> requestPayout() async {
    final body = await _api.post<Map<String, dynamic>>(
      '/wifi-earnings/request-payout',
    );
    return body['message']?.toString() ?? 'Payout request sent.';
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    final data = body['data'];
    return data is Map ? Map<String, dynamic>.from(data) : body;
  }
}

/// Permission names these screens gate on, verbatim from routes/api.php.
abstract final class WifiHotspotPermissions {
  static const menu = 'menu.wifi_hotspot';
  static const routersRead = 'wifi_routers.read';
  static const routersCreate = 'wifi_routers.create';
  static const routersUpdate = 'wifi_routers.update';
  static const routersDelete = 'wifi_routers.delete';
  static const plansRead = 'wifi_plans.read';
  static const plansCreate = 'wifi_plans.create';
  static const plansUpdate = 'wifi_plans.update';
  static const plansDelete = 'wifi_plans.delete';
  static const purchasesRead = 'wifi_purchases.read';
  static const purchasesCreate = 'wifi_purchases.create';
  static const purchasesUpdate = 'wifi_purchases.update';
}
