import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'order_flow.dart';

/// Configure and place an order for one product: domain (for hosting),
/// add-ons, configurable options and a promo code.
///
/// Every price shown here is an estimate assembled from catalog data; the
/// backend recomputes the authoritative total from the database when the
/// order is placed (it never trusts client-sent prices), so the invoice can
/// legitimately differ if pricing changed mid-order.
///
/// Serves both the client portal and staff ordering on a client's behalf —
/// [flow] supplies the endpoints and the post-order navigation.
class ConfigureOrderScreen extends ConsumerStatefulWidget {
  const ConfigureOrderScreen({
    super.key,
    required this.product,
    required this.flow,
  });

  final CatalogProduct product;
  final OrderFlow flow;

  @override
  ConsumerState<ConfigureOrderScreen> createState() =>
      _ConfigureOrderScreenState();
}

class _ConfigureOrderScreenState extends ConsumerState<ConfigureOrderScreen> {
  final _label = TextEditingController();
  final _authInfo = TextEditingController();
  final _coupon = TextEditingController();

  String _domainMode = 'register';
  int _years = 1;
  final Set<String> _productAddons = {};
  final Set<String> _domainAddons = {};

  /// option id -> selection (choice / quantity / on).
  final Map<String, ConfigSelection> _selections = {};

  // Loaded once per screen rather than through providers, because the
  // endpoints depend on which flow we are in.
  AsyncValue<List<ProductAddon>> _addons = const AsyncValue.loading();
  AsyncValue<List<ConfigOptionGroup>> _configGroups =
      const AsyncValue.loading();
  AsyncValue<List<DomainAddon>> _domainAddonOptions =
      const AsyncValue.loading();

  CouponResult? _couponResult;
  bool _validatingCoupon = false;
  bool _placing = false;
  String? _error;

  CatalogProduct get product => widget.product;
  OrderFlow get flow => widget.flow;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final addons = AsyncValue.guard(() => flow.productAddons(product.id));
    final groups = AsyncValue.guard(() => flow.configOptions(product.id));
    final domainAddons = product.needsDomain
        ? AsyncValue.guard(flow.domainAddons)
        : Future.value(const AsyncValue<List<DomainAddon>>.data([]));

    final results = await Future.wait([addons, groups, domainAddons]);
    if (!mounted) return;
    setState(() {
      _addons = results[0] as AsyncValue<List<ProductAddon>>;
      _configGroups = results[1] as AsyncValue<List<ConfigOptionGroup>>;
      _domainAddonOptions = results[2] as AsyncValue<List<DomainAddon>>;
    });
  }

  @override
  void dispose() {
    _label.dispose();
    _authInfo.dispose();
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim();
    if (code.isEmpty) return;
    setState(() => _validatingCoupon = true);
    try {
      final result =
          await flow.validateCoupon(code: code, productId: product.id);
      if (!mounted) return;
      setState(() => _couponResult = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _couponResult =
          CouponResult(valid: false, discount: 0, message: e.message));
    } finally {
      if (mounted) setState(() => _validatingCoupon = false);
    }
  }

  Future<void> _placeOrder() async {
    if (product.needsDomain && _label.text.trim().isEmpty) {
      setState(() => _error = 'Enter the domain for this hosting service.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _placing = true;
      _error = null;
    });

    try {
      final order = await flow.placeOrder(
            productId: product.id,
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            domainMode: product.needsDomain ? _domainMode : null,
            authInfo: _domainMode == 'transfer' && product.needsDomain
                ? _authInfo.text.trim()
                : null,
            years: product.needsDomain && _domainMode != 'existing'
                ? _years
                : null,
            domainAddonIds: _domainAddons.toList(),
            productAddonIds: _productAddons.toList(),
            configOptions: _selections.values.toList(),
            couponCode: (_couponResult?.valid ?? false)
                ? _coupon.text.trim()
                : null,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(order.message ??
              'Order placed — pay ${order.documentNumber} to activate.')));
      flow.onPlaced(context, ref, order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productAddons = _addons;
    final configGroups = _configGroups;
    final domainAddons = product.needsDomain ? _domainAddonOptions : null;

    return Scaffold(
      appBar: AppBar(
        title: flow.subtitle == null
            ? Text(product.name)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleMedium),
                  Text(flow.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          // What's being ordered.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleMedium),
                  Text(
                    '${Formatting.currency(product.price)}'
                    '${product.billingCycle == null || product.billingCycle == 'once' ? '' : ' / ${product.billingCycle!.replaceAll('_', ' ')}'}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  if (product.features.isNotEmpty) ...[
                    const Divider(height: Spacing.lg),
                    for (final feature in product.features)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check,
                                size: 14,
                                color: context.statusColors.settled),
                            const SizedBox(width: Spacing.xs),
                            Expanded(
                                child: Text(feature,
                                    style: theme.textTheme.bodySmall)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // Domain step for hosting products.
          if (product.needsDomain) ...[
            Text('Domain', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'register', label: Text('Register')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ButtonSegment(value: 'existing', label: Text('I have one')),
              ],
              selected: {_domainMode},
              onSelectionChanged: (s) =>
                  setState(() => _domainMode = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _label,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Domain (e.g. mycompany.co.tz)',
              ),
            ),
            if (_domainMode == 'transfer') ...[
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _authInfo,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Transfer (EPP) code',
                  helperText: 'From your current registrar',
                ),
              ),
            ],
            if (_domainMode != 'existing') ...[
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<int>(
                initialValue: _years,
                decoration:
                    const InputDecoration(labelText: 'Registration period'),
                items: [
                  for (var y = 1; y <= 10; y++)
                    DropdownMenuItem(
                        value: y, child: Text('$y year${y > 1 ? 's' : ''}')),
                ],
                onChanged: (v) => setState(() => _years = v!),
              ),
              if (domainAddons?.valueOrNull?.isNotEmpty ?? false) ...[
                const SizedBox(height: Spacing.sm),
                for (final addon in domainAddons!.value!)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(addon.name),
                    subtitle: Text(addon.isFree
                        ? 'Free'
                        : Formatting.currency(addon.price)),
                    value: _domainAddons.contains(addon.id),
                    onChanged: (checked) => setState(() => checked!
                        ? _domainAddons.add(addon.id)
                        : _domainAddons.remove(addon.id)),
                  ),
              ],
            ],
            const SizedBox(height: Spacing.md),
          ],

          // Product add-ons.
          ...productAddons.maybeWhen(
            data: (addons) => addons.isEmpty
                ? const []
                : [
                    Text('Add-ons', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Spacing.xs),
                    for (final addon in addons)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(addon.name),
                        subtitle: Text([
                          Formatting.currency(addon.price),
                          if (addon.billingCycle != null &&
                              addon.billingCycle != 'once')
                            addon.billingCycle!.replaceAll('_', ' '),
                        ].join(' / ')),
                        value: _productAddons.contains(addon.id),
                        onChanged: (checked) => setState(() => checked!
                            ? _productAddons.add(addon.id)
                            : _productAddons.remove(addon.id)),
                      ),
                    const SizedBox(height: Spacing.md),
                  ],
            orElse: () => const [],
          ),

          // Configurable options.
          ...configGroups.maybeWhen(
            data: (groups) => [
              for (final group in groups) ...[
                Text(group.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                for (final option in group.options)
                  _buildOption(context, option),
                const SizedBox(height: Spacing.md),
              ],
            ],
            orElse: () => const [],
          ),

          // Promo code.
          Text('Promo code', style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coupon,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      hintText: 'Enter code', isDense: true),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              OutlinedButton(
                onPressed: _validatingCoupon ? null : _applyCoupon,
                child: Text(_validatingCoupon ? '…' : 'Apply'),
              ),
            ],
          ),
          if (_couponResult != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              _couponResult!.message ??
                  (_couponResult!.valid ? 'Code applied.' : 'Invalid code.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _couponResult!.valid
                    ? context.statusColors.settled
                    : theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),

          FilledButton(
            onPressed: _placing ? null : _placeOrder,
            child: _placing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Place order'),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            flow.footnote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, ConfigOption option) {
    switch (option.optionType) {
      case 'dropdown' || 'radio':
        final current = _selections[option.id]?.choiceId;
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: DropdownButtonFormField<String>(
            initialValue: current,
            decoration: InputDecoration(labelText: option.name),
            items: [
              for (final choice in option.choices)
                DropdownMenuItem(
                  value: choice.id,
                  child: Text(
                    choice.price > 0
                        ? '${choice.label} (+${Formatting.currency(choice.price)})'
                        : choice.label,
                  ),
                ),
            ],
            onChanged: (choiceId) => setState(() {
              if (choiceId == null) return;
              _selections[option.id] =
                  ConfigSelection(optionId: option.id, choiceId: choiceId);
            }),
          ),
        );

      case 'quantity':
        final qty = _selections[option.id]?.quantity ?? 0;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(option.name),
          subtitle: option.unitPrice == null
              ? null
              : Text('${Formatting.currency(option.unitPrice)} each'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: qty <= 0
                    ? null
                    : () => setState(() {
                          if (qty <= 1) {
                            _selections.remove(option.id);
                          } else {
                            _selections[option.id] = ConfigSelection(
                                optionId: option.id, quantity: qty - 1);
                          }
                        }),
              ),
              Text('$qty'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _selections[option.id] =
                    ConfigSelection(optionId: option.id, quantity: qty + 1)),
              ),
            ],
          ),
        );

      default: // yesno — presence in the payload means "on".
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(option.name),
          subtitle: option.unitPrice == null || option.unitPrice == 0
              ? null
              : Money(option.unitPrice),
          value: _selections.containsKey(option.id),
          onChanged: (on) => setState(() {
            if (on) {
              _selections[option.id] = ConfigSelection(optionId: option.id);
            } else {
              _selections.remove(option.id);
            }
          }),
        );
    }
  }
}
