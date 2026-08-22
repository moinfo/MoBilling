import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../portal_providers.dart';
import '../portal_routes.dart';

/// Where an order's data comes from and where it goes once placed.
///
/// The configure-order screen is identical for a client ordering for
/// themselves and for staff ordering on a client's behalf — same add-ons,
/// config options, promo code and "pay the invoice to activate" outcome. The
/// API even reuses `PortalOrderController` for both; only the paths differ
/// (`/portal/...` vs `/orders/...`) and staff must name the client. This
/// object carries exactly those differences, so the screen has none.
class OrderFlow {
  const OrderFlow({
    required this.productAddons,
    required this.configOptions,
    required this.domainAddons,
    required this.validateCoupon,
    required this.placeOrder,
    required this.onPlaced,
    required this.footnote,
    this.subtitle,
  });

  final Future<List<ProductAddon>> Function(String productId) productAddons;
  final Future<List<ConfigOptionGroup>> Function(String productId)
      configOptions;
  final Future<List<DomainAddon>> Function() domainAddons;
  final Future<CouponResult> Function({
    required String code,
    required String productId,
  }) validateCoupon;
  final Future<PlacedOrder> Function({
    required String productId,
    String? label,
    String? domainMode,
    String? authInfo,
    int? years,
    List<String> domainAddonIds,
    List<String> productAddonIds,
    List<ConfigSelection> configOptions,
    String? couponCode,
  }) placeOrder;

  /// Invalidate what changed and navigate to the invoice.
  final void Function(BuildContext context, WidgetRef ref, PlacedOrder order)
      onPlaced;

  /// The line under the Place order button.
  final String footnote;

  /// Shown under the app-bar title — for staff, the client's name, so the
  /// order is never placed for the wrong company.
  final String? subtitle;

  /// The client portal: the signed-in client orders for themselves.
  static OrderFlow portal(Ref ref) {
    final service = ref.read(portalServiceProvider);
    return OrderFlow(
      productAddons: service.productAddons,
      configOptions: service.configOptions,
      domainAddons: service.domainAddons,
      validateCoupon: service.validateCoupon,
      placeOrder: service.placeOrder,
      onPlaced: (context, ref, order) {
        ref.invalidate(portalSubscriptionsProvider);
        ref.invalidate(portalDashboardProvider);
        // Straight to the invoice: paying it is what activates the service.
        context.pushReplacement(PortalRoutes.invoicePath(order.documentId));
      },
      footnote: 'An invoice is created for your order — the service '
          'activates automatically once it is paid.',
    );
  }

  /// Staff placing an order for [clientId] (WHMCS-style "Add New Order").
  static OrderFlow staff(
    OpsService service, {
    required String clientId,
    required String clientName,
  }) {
    return OrderFlow(
      productAddons: service.orderProductAddons,
      configOptions: service.orderConfigOptions,
      domainAddons: service.orderDomainAddons,
      validateCoupon: ({required code, required productId}) =>
          service.validateOrderCoupon(
        clientId: clientId,
        code: code,
        productId: productId,
      ),
      placeOrder: ({
        required productId,
        label,
        domainMode,
        authInfo,
        years,
        domainAddonIds = const [],
        productAddonIds = const [],
        configOptions = const [],
        couponCode,
      }) =>
          service.placeOrder(
        clientId: clientId,
        productId: productId,
        label: label,
        domainMode: domainMode,
        authInfo: authInfo,
        years: years,
        domainAddonIds: domainAddonIds,
        productAddonIds: productAddonIds,
        configOptions: configOptions,
        couponCode: couponCode,
      ),
      onPlaced: (context, ref, order) =>
          context.pushReplacement('/documents/${order.documentId}'),
      footnote: 'An invoice is created for $clientName — the service '
          'activates once they pay it.',
      subtitle: clientName,
    );
  }
}
