/// Ordering models. Shapes match `PortalOrderController` and
/// `PortalDomainController::check` / `::order`.
library;

import '../json.dart';

class CatalogGroup {
  const CatalogGroup({required this.name, required this.products});

  final String name;
  final List<CatalogProduct> products;

  factory CatalogGroup.fromJson(Map<String, dynamic> json) => CatalogGroup(
    name: json.strOr('name', '—'),
    products: json.list('products', CatalogProduct.fromJson),
  );
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.features,
    required this.needsDomain,
    this.billingCycle,
  });

  final String id;
  final String name;
  final double price;

  /// Description split into feature lines server-side.
  final List<String> features;

  /// WHM/cPanel products must be ordered with a domain.
  final bool needsDomain;
  final String? billingCycle;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    features: json.strings('features'),
    needsDomain: json.flag('needs_domain'),
    billingCycle: json.str('billing_cycle'),
  );
}

class TldPricing {
  const TldPricing({
    required this.tld,
    required this.registerPrice,
    required this.transferPrice,
    required this.yearsMin,
    required this.yearsMax,
  });

  final String tld;
  final double registerPrice;
  final double transferPrice;
  final int yearsMin;
  final int yearsMax;

  factory TldPricing.fromJson(Map<String, dynamic> json) => TldPricing(
    tld: json.strOr('tld', ''),
    registerPrice: json.money('register_price'),
    transferPrice: json.money('transfer_price'),
    yearsMin: json.count('years_min', fallback: 1),
    yearsMax: json.count('years_max', fallback: 10),
  );
}

class DomainAddon {
  const DomainAddon({
    required this.id,
    required this.name,
    required this.price,
    required this.isFree,
    this.description,
  });

  final String id;
  final String name;
  final double price;
  final bool isFree;
  final String? description;

  factory DomainAddon.fromJson(Map<String, dynamic> json) => DomainAddon(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    isFree: json.flag('is_free'),
    description: json.str('description'),
  );
}

class ProductAddon {
  const ProductAddon({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.billingCycle,
  });

  final String id;
  final String name;
  final double price;
  final String? description;
  final String? billingCycle;

  factory ProductAddon.fromJson(Map<String, dynamic> json) => ProductAddon(
    id: json.id(),
    name: json.strOr('name', '—'),
    price: json.money('price'),
    description: json.str('description'),
    billingCycle: json.str('billing_cycle'),
  );
}

class ConfigOptionGroup {
  const ConfigOptionGroup({
    required this.id,
    required this.name,
    required this.options,
    this.description,
  });

  final String id;
  final String name;
  final List<ConfigOption> options;
  final String? description;

  factory ConfigOptionGroup.fromJson(Map<String, dynamic> json) =>
      ConfigOptionGroup(
        id: json.id(),
        name: json.strOr('name', '—'),
        options: json.list('options', ConfigOption.fromJson),
        description: json.str('description'),
      );
}

class ConfigOption {
  const ConfigOption({
    required this.id,
    required this.name,
    required this.optionType,
    required this.choices,
    this.unitPrice,
  });

  final String id;
  final String name;

  /// dropdown | radio | quantity | yesno.
  final String optionType;
  final List<ConfigChoice> choices;
  final double? unitPrice;

  factory ConfigOption.fromJson(Map<String, dynamic> json) => ConfigOption(
    id: json.id(),
    name: json.strOr('name', '—'),
    optionType: json.strOr('option_type', 'dropdown'),
    choices: json.list('choices', ConfigChoice.fromJson),
    unitPrice: json['unit_price'] == null ? null : json.money('unit_price'),
  );
}

class ConfigChoice {
  const ConfigChoice({
    required this.id,
    required this.label,
    required this.price,
  });

  final String id;
  final String label;
  final double price;

  factory ConfigChoice.fromJson(Map<String, dynamic> json) => ConfigChoice(
    id: json.id(),
    label: json.strOr('label', '—'),
    price: json.money('price'),
  );
}

/// A config selection to submit with an order.
class ConfigSelection {
  const ConfigSelection({required this.optionId, this.choiceId, this.quantity});

  final String optionId;
  final String? choiceId;
  final int? quantity;

  Map<String, dynamic> toJson() => {
    'option_id': optionId,
    if (choiceId != null) 'choice_id': choiceId,
    if (quantity != null) 'quantity': quantity,
  };
}

class CouponResult {
  const CouponResult({
    required this.valid,
    required this.discount,
    this.message,
    this.description,
  });

  final bool valid;
  final double discount;
  final String? message;
  final String? description;

  factory CouponResult.fromJson(Map<String, dynamic> json) => CouponResult(
    valid: json.flag('valid'),
    discount: json.money('discount'),
    message: json.str('message'),
    description: json.str('description'),
  );
}

class DomainCheckResult {
  const DomainCheckResult({
    required this.name,
    required this.available,
    this.pricing,
  });

  final String name;
  final bool available;

  /// Null when the TLD isn't offered by this tenant.
  final TldPricing? pricing;

  factory DomainCheckResult.fromJson(Map<String, dynamic> json) =>
      DomainCheckResult(
        name: json.strOr('name', ''),
        available: json.flag('available'),
        pricing: json.object('pricing') == null
            ? null
            : TldPricing.fromJson(json.object('pricing')!),
      );
}

/// A placed order: the pending subscription and the invoice to pay.
class PlacedOrder {
  const PlacedOrder({
    required this.documentId,
    required this.documentNumber,
    required this.total,
    this.subscriptionId,
    this.message,
  });

  final String documentId;
  final String documentNumber;
  final double total;
  final String? subscriptionId;
  final String? message;

  factory PlacedOrder.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return PlacedOrder(
      documentId: data.id('document_id'),
      documentNumber: data.strOr('document_number', '—'),
      total: data.money('total'),
      subscriptionId: data.str('subscription_id'),
      message: json.str('message'),
    );
  }
}

// ---------------------------------------------------------------------------
// Reseller — GET /portal/reseller/status, GET /portal/reseller/domains/check
// ---------------------------------------------------------------------------

/// Membership state plus the wholesale price list — GET /portal/reseller/status.
///
/// Every portal client can read this: a non-member gets [isReseller] false and
/// [membershipPrice] set, which is the pitch. [membershipPrice] is null when
/// the tenant never created the "Reseller Membership" product, in which case
/// there is nothing to sell and the screen says so.
class ResellerStatus {
  const ResellerStatus({
    required this.isReseller,
    required this.walletBalance,
    required this.tlds,
    this.expireDate,
    this.membershipPrice,
  });

  final bool isReseller;

  /// Wallet credit — reseller orders are paid from it and nothing else.
  final double walletBalance;

  final List<ResellerTld> tlds;
  final DateTime? expireDate;
  final double? membershipPrice;

  factory ResellerStatus.fromJson(Map<String, dynamic> json) {
    final data = json.object('data') ?? json;
    return ResellerStatus(
      isReseller: data.flag('is_reseller'),
      walletBalance: data.money('wallet_balance'),
      tlds: data.list('tlds', ResellerTld.fromJson),
      expireDate: data.date('expire_date'),
      membershipPrice: data['membership_price'] == null
          ? null
          : data.money('membership_price'),
    );
  }

  /// The wholesale price row for `example.co.tz` → the `.co.tz` entry, or null
  /// when this tenant offers no reseller price for that extension.
  ResellerTld? pricingFor(String domainName) {
    final parts = domainName.split('.');
    if (parts.length < 2) return null;
    final tld = parts.sublist(1).join('.').toLowerCase();
    for (final row in tlds) {
      if (row.tld.toLowerCase() == tld) return row;
    }
    return null;
  }
}

/// One TLD at wholesale cost.
class ResellerTld {
  const ResellerTld({
    required this.tld,
    required this.resellerPrice,
    required this.yearsMin,
    required this.yearsMax,
  });

  final String tld;
  final double resellerPrice;
  final int yearsMin;
  final int yearsMax;

  factory ResellerTld.fromJson(Map<String, dynamic> json) => ResellerTld(
    tld: json.strOr('tld', ''),
    resellerPrice: json.money('reseller_price'),
    yearsMin: json.count('years_min', fallback: 1),
    yearsMax: json.count('years_max', fallback: 10),
  );
}

/// Availability at wholesale pricing — GET /portal/reseller/domains/check.
///
/// [pricing] is null when the extension carries no reseller price; the backend
/// then sends an explanatory [message] instead, which is safe to show verbatim.
class ResellerCheckResult {
  const ResellerCheckResult({
    required this.name,
    required this.available,
    this.pricing,
    this.message,
  });

  final String name;
  final bool available;
  final ResellerTld? pricing;
  final String? message;

  factory ResellerCheckResult.fromJson(Map<String, dynamic> json) {
    final pricing = json.object('pricing');
    return ResellerCheckResult(
      name: json.strOr('name', ''),
      available: json.flag('available'),
      // The check response omits `tld`; carry the name's own extension so the
      // row is self-describing if it is ever rendered on its own.
      pricing: pricing == null
          ? null
          : ResellerTld.fromJson({
              'tld': json.strOr('name', '').split('.').skip(1).join('.'),
              ...pricing,
            }),
      message: json.str('message'),
    );
  }
}
