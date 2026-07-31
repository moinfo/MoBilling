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
        unitPrice:
            json['unit_price'] == null ? null : json.money('unit_price'),
      );
}

class ConfigChoice {
  const ConfigChoice({required this.id, required this.label, required this.price});

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
