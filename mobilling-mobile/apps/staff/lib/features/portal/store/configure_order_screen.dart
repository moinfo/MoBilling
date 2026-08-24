import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'order_flow.dart';

/// Configure and place an order for one product: domain (for hosting),
/// add-ons, configurable options and a promo code.
///
/// One long form, sectioned: what you are buying, then each decision under
/// its own rule, then the single action the screen exists for.
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
      final result = await flow.validateCoupon(
        code: code,
        productId: product.id,
      );
      if (!mounted) return;
      setState(() => _couponResult = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _couponResult = CouponResult(
          valid: false,
          discount: 0,
          message: e.message,
        ),
      );
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
        years: product.needsDomain && _domainMode != 'existing' ? _years : null,
        domainAddonIds: _domainAddons.toList(),
        productAddonIds: _productAddons.toList(),
        configOptions: _selections.values.toList(),
        couponCode: (_couponResult?.valid ?? false)
            ? _coupon.text.trim()
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order.message ??
                'Order placed — pay ${order.documentNumber} to activate.',
          ),
        ),
      );
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
    final scheme = theme.colorScheme;
    final productAddons = _addons;
    final configGroups = _configGroups;
    final domainAddons = product.needsDomain ? _domainAddonOptions : null;

    return Scaffold(
      appBar: ShellTopBar(
        // For staff the eyebrow is the client's name, so an order is never
        // placed for the wrong company.
        eyebrow: flow.subtitle ?? 'Store',
        title: product.name,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          // What's being ordered.
          Reveal(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOU ARE ORDERING',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      product.name,
                      style: Type.display(22, color: scheme.onSurface),
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Money(
                              product.price,
                              scale: MoneyScale.headline,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        _Cadence(_cadence(product.billingCycle)),
                      ],
                    ),
                    if (product.features.isNotEmpty) ...[
                      const Divider(height: Spacing.lg),
                      for (final feature in product.features)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.check,
                                  size: 14,
                                  color: context.statusColors.settled,
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                              Expanded(
                                child: Text(
                                  feature,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Domain step for hosting products.
          if (product.needsDomain) ...[
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Domain'),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'register', label: Text('Register')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ButtonSegment(value: 'existing', label: Text('I have one')),
              ],
              selected: {_domainMode},
              onSelectionChanged: (s) => setState(() => _domainMode = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: Spacing.md),
            FieldLabel('Domain'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _label,
              autocorrect: false,
              keyboardType: TextInputType.url,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                hintText: 'mycompany.co.tz',
                prefixIcon: Icon(Icons.language_outlined, size: 20),
              ),
            ),
            if (_domainMode == 'transfer') ...[
              const SizedBox(height: Spacing.md),
              FieldLabel('Transfer (EPP) code'),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _authInfo,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'The code from your current registrar',
                ),
              ),
            ],
            if (_domainMode != 'existing') ...[
              const SizedBox(height: Spacing.md),
              FieldLabel('Registration period'),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<int>(
                initialValue: _years,
                items: [
                  for (var y = 1; y <= 10; y++)
                    DropdownMenuItem(
                      value: y,
                      child: Text('$y year${y > 1 ? 's' : ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => _years = v!),
              ),
              if (domainAddons?.valueOrNull?.isNotEmpty ?? false) ...[
                const SizedBox(height: Spacing.md),
                Card(
                  child: Column(
                    children: [
                      for (final (i, addon)
                          in domainAddons!.value!.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _AddonTile(
                          name: addon.name,
                          note: addon.isFree ? 'Included' : null,
                          amount: addon.isFree ? null : addon.price,
                          selected: _domainAddons.contains(addon.id),
                          onChanged: (checked) => setState(
                            () => checked
                                ? _domainAddons.add(addon.id)
                                : _domainAddons.remove(addon.id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],

          // Product add-ons.
          ...productAddons.maybeWhen(
            data: (addons) => addons.isEmpty
                ? const []
                : [
                    const SizedBox(height: Spacing.lg),
                    const SectionHeader('Add-ons'),
                    const SizedBox(height: Spacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, addon) in addons.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _AddonTile(
                              name: addon.name,
                              note: _cadence(addon.billingCycle),
                              amount: addon.price,
                              selected: _productAddons.contains(addon.id),
                              onChanged: (checked) => setState(
                                () => checked
                                    ? _productAddons.add(addon.id)
                                    : _productAddons.remove(addon.id),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
            orElse: () => const [],
          ),

          // Configurable options.
          ...configGroups.maybeWhen(
            data: (groups) => [
              for (final group in groups) ...[
                const SizedBox(height: Spacing.lg),
                SectionHeader(group.name),
                const SizedBox(height: Spacing.sm),
                for (final option in group.options)
                  _buildOption(context, option),
              ],
            ],
            orElse: () => const [],
          ),

          // Promo code.
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Promo code'),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _coupon,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Enter code'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              OutlinedButton(
                onPressed: _validatingCoupon ? null : _applyCoupon,
                child: _validatingCoupon
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          if (_couponResult != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              _couponResult!.message ??
                  (_couponResult!.valid
                      ? 'Code applied.'
                      : 'That code is not valid for this product.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _couponResult!.valid
                    ? context.statusColors.settled
                    : scheme.error,
              ),
            ),
          ],

          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Place order',
            busy: _placing,
            onPressed: _placing ? null : _placeOrder,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            flow.footnote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }

  Widget _buildOption(BuildContext context, ConfigOption option) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    switch (option.optionType) {
      case 'dropdown' || 'radio':
        final current = _selections[option.id]?.choiceId;
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FieldLabel(option.name),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<String>(
                initialValue: current,
                hint: const Text('Choose one'),
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
                  _selections[option.id] = ConfigSelection(
                    optionId: option.id,
                    choiceId: choiceId,
                  );
                }),
              ),
            ],
          ),
        );

      case 'quantity':
        final qty = _selections[option.id]?.quantity ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Card(
            child: ListTile(
              title: Text(option.name, style: theme.textTheme.titleSmall),
              subtitle: option.unitPrice == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Row(
                        children: [
                          Money(
                            option.unitPrice,
                            scale: MoneyScale.dense,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Spacing.xs),
                          Text(
                            'EACH',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Fewer',
                    onPressed: qty <= 0
                        ? null
                        : () => setState(() {
                            if (qty <= 1) {
                              _selections.remove(option.id);
                            } else {
                              _selections[option.id] = ConfigSelection(
                                optionId: option.id,
                                quantity: qty - 1,
                              );
                            }
                          }),
                  ),
                  Text(
                    Formatting.integer(qty),
                    style: TextStyle(
                      fontFamily: Type.family,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFeatures: Type.figures,
                      color: scheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'More',
                    onPressed: () => setState(
                      () => _selections[option.id] = ConfigSelection(
                        optionId: option.id,
                        quantity: qty + 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      default: // yesno — presence in the payload means "on".
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Card(
            child: SwitchListTile(
              title: Text(option.name, style: theme.textTheme.titleSmall),
              subtitle: option.unitPrice == null || option.unitPrice == 0
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Money(
                        option.unitPrice,
                        scale: MoneyScale.dense,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              value: _selections.containsKey(option.id),
              onChanged: (on) => setState(() {
                if (on) {
                  _selections[option.id] = ConfigSelection(optionId: option.id);
                } else {
                  _selections.remove(option.id);
                }
              }),
            ),
          ),
        );
    }
  }
}

/// One optional extra in a card of them: a checkbox on the left, the name,
/// a mono note, and the price as the trailing figure so the right edge is one
/// aligned column.
class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.name,
    required this.note,
    required this.amount,
    required this.selected,
    required this.onChanged,
  });

  final String name;
  final String? note;
  final Object? amount;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListTile(
      leading: Checkbox(
        value: selected,
        onChanged: (v) => onChanged(v ?? false),
      ),
      horizontalTitleGap: Spacing.sm,
      title: Text(name, style: theme.textTheme.titleSmall),
      subtitle: note == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
      trailing: amount == null ? null : Money(amount),
      onTap: () => onChanged(!selected),
    );
  }
}


/// The mono cadence beside a price — `PER MONTH`.
class _Cadence extends StatelessWidget {
  const _Cadence(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// `monthly` → `per month`, as the handoff's price-card cadence.
String _cadence(String? cycle) => switch (cycle) {
  null || 'once' => 'one-time',
  'monthly' => 'per month',
  'quarterly' => 'per quarter',
  'semi_annually' || 'semiannually' => 'per 6 months',
  'annually' || 'yearly' => 'per year',
  'biennially' => 'per 2 years',
  'triennially' => 'per 3 years',
  final c => c.replaceAll('_', ' '),
};
