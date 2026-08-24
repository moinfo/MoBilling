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

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked != null) setState(() => _client = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDomains =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(OpsPermissions.domainsCreate) ??
        false;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'Add order'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Client', style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: Text(
                    _client?.name ?? 'Choose client',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickClient,
                ),
                if (canDomains) ...[
                  const SizedBox(height: Spacing.md),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'product',
                        icon: Icon(Icons.inventory_2_outlined),
                        label: Text('Product'),
                      ),
                      ButtonSegment(
                        value: 'domain',
                        icon: Icon(Icons.public_outlined),
                        label: Text('Domain only'),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                    showSelectedIcon: false,
                  ),
                ],
                const SizedBox(height: Spacing.md),
              ],
            ),
          ),
          Expanded(
            child: _client == null
                ? StateMessage(
                    icon: Icons.person_search_outlined,
                    title: 'Choose a client to start',
                    message:
                        'The order is invoiced to them, and the service '
                        'activates when the invoice is paid.',
                    actionLabel: 'Choose client',
                    onAction: _pickClient,
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
                Spacing.md,
                0,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
                for (final (i, group) in groups.indexed) ...[
                  if (i > 0) const SizedBox(height: Spacing.lg),
                  SectionHeader(group.name),
                  const SizedBox(height: Spacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final (j, product) in group.products.indexed) ...[
                          if (j > 0) const Divider(height: 1),
                          ListTile(
                            title: Text(
                              product.name,
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: product.features.isEmpty
                                ? null
                                : Text(
                                    product.features.take(2).join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: _PriceColumn(product: product),
                            onTap: () => context.push(
                              '/orders/configure',
                              extra: StaffOrderArgs(
                                product: product,
                                client: client,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The row's price, with the billing cycle as a mono caption beneath so the
/// right edge of the list stays one column of money.
class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.product});

  final CatalogProduct product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cycle = product.billingCycle;
    final recurring = cycle != null && cycle != 'once';

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Money(product.price),
        if (recurring) ...[
          const SizedBox(height: 2),
          Text(
            '/ ${cycle.replaceAll('_', ' ')}'.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
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
      final order = await ref
          .read(opsServiceProvider)
          .orderDomain(
            clientId: widget.client.id,
            name: _domain,
            years: _years,
            action: _action,
            authInfo: _action == 'transfer' ? _authInfo.text.trim() : null,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order.message ?? 'Order placed — invoice ${order.documentNumber}.',
          ),
        ),
      );
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
    final scheme = theme.colorScheme;
    final tlds = ref.watch(orderTldsProvider);
    final pricing = _pricingFor(tlds.valueOrNull ?? const []);
    final unit = pricing == null
        ? 0.0
        : (_action == 'register'
              ? pricing.registerPrice
              : pricing.transferPrice);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.xl),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text('Domain name', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _name,
          autocorrect: false,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'example.co.tz',
            prefixIcon: Icon(Icons.public_outlined, size: 20),
          ),
        ),
        const SizedBox(height: Spacing.md),
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
          const SizedBox(height: Spacing.md),
          Text('Transfer (EPP) code', style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _authInfo,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: 'From the current registrar',
              prefixIcon: Icon(Icons.key_outlined, size: 20),
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        Text('Years', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<int>(
          initialValue: _years,
          isExpanded: true,
          items: [
            for (
              var y = pricing?.yearsMin ?? 1;
              y <= (pricing?.yearsMax ?? 10);
              y++
            )
              DropdownMenuItem(
                value: y,
                child: Text('$y year${y > 1 ? 's' : ''}'),
              ),
          ],
          onChanged: (v) => setState(() => _years = v!),
        ),
        const SizedBox(height: Spacing.lg),
        // The one figure this form is about.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORDER TOTAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (pricing != null) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Money(unit * _years, scale: MoneyScale.display),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$_domain · $_years ${_years == 1 ? 'year' : 'years'} · ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Money(unit, scale: MoneyScale.dense, showCode: false),
                      Text(
                        ' / year',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ] else if (_domain.contains('.') && tlds.hasValue)
                  Text(
                    'This TLD is not offered — add pricing under Settings → Domains on the web.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  )
                else
                  Text(
                    'Enter a domain to see pricing.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _placing ? 'Placing order…' : 'Place order',
          busy: _placing,
          onPressed: _placing || pricing == null ? null : _place,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Creates a pending domain and an invoice for ${widget.client.name}; '
          'payment triggers the ${_action == 'register' ? 'registration' : 'transfer'} at the registry.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
