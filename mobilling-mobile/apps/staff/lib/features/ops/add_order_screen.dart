import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
import '../portal/store/configure_order_screen.dart';
import '../portal/store/order_flow.dart';
import 'ops_providers.dart';

/// WHMCS-style "Add New Order": staff pick a client, then either a product
/// (configured exactly as a client would in the portal) or a standalone
/// domain registration/transfer. Either way an invoice is created and the
/// service activates when it is paid.
class AddOrderScreen extends ConsumerStatefulWidget {
  const AddOrderScreen({super.key});

  @override
  ConsumerState<AddOrderScreen> createState() => _AddOrderScreenState();
}

class _AddOrderScreenState extends ConsumerState<AddOrderScreen> {
  StaffClient? _client;
  String _kind = 'product';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDomains = ref.watch(sessionControllerProvider).session?.can(
            OpsPermissions.domainsCreate) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Add order')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(_client?.name ?? 'Choose client'),
                  onPressed: () async {
                    final picked = await ClientPickerSheet.show(context);
                    if (picked != null) setState(() => _client = picked);
                  },
                ),
                if (canDomains) ...[
                  const SizedBox(height: Spacing.sm),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'product',
                          icon: Icon(Icons.inventory_2_outlined),
                          label: Text('Product')),
                      ButtonSegment(
                          value: 'domain',
                          icon: Icon(Icons.public_outlined),
                          label: Text('Domain only')),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                    showSelectedIcon: false,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _client == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'Pick the client this order is for.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : _kind == 'domain'
                    ? _DomainOrderForm(client: _client!)
                    : _ProductCatalog(client: _client!),
          ),
        ],
      ),
    );
  }
}

/// The grouped catalog — tap a product to configure it for the client.
class _ProductCatalog extends ConsumerWidget {
  const _ProductCatalog({required this.client});

  final StaffClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(orderCatalogProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: catalog,
      errorTitle: 'Could not load the catalog',
      onRetry: () => ref.invalidate(orderCatalogProvider),
      builder: (groups) => groups.isEmpty
          ? const StateMessage(
              icon: Icons.storefront_outlined,
              title: 'No orderable products',
              message: 'Products must be active and portal-visible.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.xl),
              children: [
                for (final group in groups) ...[
                  Text(group.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: Spacing.sm),
                  for (final product in group.products) ...[
                    Card(
                      child: ListTile(
                        title: Text(product.name),
                        subtitle: product.features.isEmpty
                            ? null
                            : Text(product.features.take(2).join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                        trailing: Text(
                          '${Formatting.currency(product.price)}'
                          '${product.billingCycle == null || product.billingCycle == 'once' ? '' : '\n/ ${product.billingCycle!.replaceAll('_', ' ')}'}',
                          textAlign: TextAlign.end,
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: theme.colorScheme.primary),
                        ),
                        onTap: () => context.push(
                          '/orders/configure',
                          extra: StaffOrderArgs(product: product, client: client),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                  ],
                  const SizedBox(height: Spacing.sm),
                ],
              ],
            ),
    );
  }
}

/// Route payload for `/orders/configure`.
class StaffOrderArgs {
  const StaffOrderArgs({required this.product, required this.client});

  final CatalogProduct product;
  final StaffClient client;
}

/// Builds the configure screen for a staff order.
class StaffConfigureOrderScreen extends ConsumerWidget {
  const StaffConfigureOrderScreen({super.key, required this.args});

  final StaffOrderArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ConfigureOrderScreen(
        product: args.product,
        flow: OrderFlow.staff(
          ref.read(opsServiceProvider),
          clientId: args.client.id,
          clientName: args.client.name,
        ),
      );
}

/// Standalone domain register/transfer for the client. No live availability
/// check here — the server does a read-only EPP check when the order is
/// placed and rejects taken names.
class _DomainOrderForm extends ConsumerStatefulWidget {
  const _DomainOrderForm({required this.client});

  final StaffClient client;

  @override
  ConsumerState<_DomainOrderForm> createState() => _DomainOrderFormState();
}

class _DomainOrderFormState extends ConsumerState<_DomainOrderForm> {
  final _name = TextEditingController();
  final _authInfo = TextEditingController();
  String _action = 'register';
  int _years = 1;
  bool _placing = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _authInfo.dispose();
    super.dispose();
  }

  String get _domain => _name.text.trim().toLowerCase();

  TldPricing? _pricingFor(List<TldPricing> tlds) {
    if (!_domain.contains('.')) return null;
    final tld = _domain.split('.').skip(1).join('.');
    for (final t in tlds) {
      if (t.tld == tld) return t;
    }
    return null;
  }

  Future<void> _place() async {
    if (!_domain.contains('.')) {
      setState(() => _error = 'Enter a full domain, e.g. example.co.tz');
      return;
    }
    if (_action == 'transfer' && _authInfo.text.trim().isEmpty) {
      setState(() => _error = 'The transfer (EPP) code is required.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      final order = await ref.read(opsServiceProvider).orderDomain(
            clientId: widget.client.id,
            name: _domain,
            years: _years,
            action: _action,
            authInfo: _action == 'transfer' ? _authInfo.text.trim() : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(order.message ??
              'Order placed — invoice ${order.documentNumber}.')));
      if (order.documentId.isNotEmpty) {
        context.pushReplacement('/documents/${order.documentId}');
      } else {
        context.pushReplacement('/domains');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tlds = ref.watch(orderTldsProvider);
    final pricing = _pricingFor(tlds.valueOrNull ?? const []);
    final unit = pricing == null
        ? 0.0
        : (_action == 'register'
            ? pricing.registerPrice
            : pricing.transferPrice);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.xl),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        TextField(
          controller: _name,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Domain name',
            hintText: 'example.co.tz',
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'register', label: Text('Register')),
            ButtonSegment(value: 'transfer', label: Text('Transfer in')),
          ],
          selected: {_action},
          onSelectionChanged: (s) => setState(() => _action = s.first),
          showSelectedIcon: false,
        ),
        if (_action == 'transfer') ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _authInfo,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'EPP / auth code',
              helperText: 'From the current registrar',
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<int>(
          initialValue: _years,
          decoration: const InputDecoration(labelText: 'Years'),
          items: [
            for (var y = pricing?.yearsMin ?? 1;
                y <= (pricing?.yearsMax ?? 10);
                y++)
              DropdownMenuItem(
                  value: y, child: Text('$y year${y > 1 ? 's' : ''}')),
          ],
          onChanged: (v) => setState(() => _years = v!),
        ),
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Summary', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.xs),
                if (pricing != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_domain × $_years yr @ ${Formatting.currency(unit)}/yr',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Money(unit * _years, scale: MoneyScale.headline),
                    ],
                  )
                else if (_domain.contains('.') && tlds.hasValue)
                  Text(
                    'This TLD is not offered — add pricing under Settings → Domains on the web.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  )
                else
                  Text('Enter a domain to see pricing.',
                      style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        FilledButton.icon(
          icon: const Icon(Icons.shopping_cart_outlined, size: 18),
          label: Text(_placing ? 'Placing…' : 'Place order'),
          onPressed: _placing || pricing == null ? null : _place,
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'Creates a pending domain and an invoice for ${widget.client.name}; '
          'payment triggers the ${_action == 'register' ? 'registration' : 'transfer'} at the registry.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
