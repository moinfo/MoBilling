import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../billing_money/billing_money_providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart' show ClientPickerSheet, ProductPickerSheet;
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmDetailRow,
        CrmField,
        CrmMetaLine,
        CrmPickerField,
        CrmSheet,
        CrmStatusLine,
        FilterStrip,
        showCrmMessage,
        showCrmSheet;
import '../support_admin/support_admin_providers.dart'
    show hostingServersProvider, supportAdminServiceProvider;
import 'billing_catalog_providers.dart';

/// The billing catalog: products, add-ons, configurable options, coupons and
/// subscriptions. Full CRUD lives here now — an earlier version of this file
/// kept these screens read-only ("desk work, best left to the web"), but that
/// call has been overridden: staff raise and correct catalog rows from the
/// field as often as anyone does it from a desk.
///
/// Because they are reference data rather than money in motion, the read
/// views are still set quietly: the price is the only figure, in the money
/// readout; everything that names it — cycle, code, what it is attached to —
/// sits in the mono eyebrow register underneath. The forms are the loud part,
/// and every list row that can be changed opens the same shape: tap it, get a
/// sheet with Edit/Delete (and whatever else applies), same as `ServersScreen`.

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// A figure as it should sit in a field being typed into: `1`, not `1.00`,
/// and blank rather than `0.00`. [Formatting.amount] is for a figure being
/// *read*; here the trailing zeros are just noise.
String _plain(double? value) {
  if (value == null || value == 0) return '';
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Amounts are typed with the grouping separators the rest of the app
/// prints, so they are stripped before parsing rather than rejected.
double? _num(TextEditingController controller) {
  final text = controller.text.replaceAll(',', '').trim();
  return text.isEmpty ? null : double.tryParse(text);
}

int? _int(TextEditingController controller) {
  final text = controller.text.trim();
  return text.isEmpty ? null : int.tryParse(text);
}

/// One line, permission name in, whether the signed-in user holds it out —
/// every gate in this file reads as `ref.can(BillingCatalogPermissions...)`.
extension _Permissions on WidgetRef {
  bool can(String permission) =>
      watch(sessionControllerProvider).session?.can(permission) ?? false;
}

/// The header + a column of rows a tap on a catalogue item opens — the same
/// shape `ServersScreen` uses, so every list here behaves alike. [subtitle]
/// carries whatever status/meta line the caller wants under the title.
class _ActionsSheet extends StatelessWidget {
  const _ActionsSheet({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.actions,
  });

  final String eyebrow;
  final String title;
  final Widget? subtitle;
  final List<_SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: Spacing.md + sheetBottomInset(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.display(20, color: scheme.onSurface),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: Spacing.sm),
                    subtitle!,
                  ],
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            for (final action in actions)
              ListTile(
                leading: Icon(
                  action.icon,
                  color: action.destructive ? scheme.error : null,
                ),
                title: Text(
                  action.label,
                  style: action.destructive
                      ? TextStyle(color: scheme.error)
                      : null,
                ),
                enabled: action.onTap != null,
                onTap: action.onTap,
              ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction {
  const _SheetAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
}

/// A destructive confirmation, the shape every delete in this file asks:
/// what is being removed, and what that actually does.
Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A field a form fills in seconds but the API charges for per keystroke: the
/// picker that reads "N products" or their names, and opens a checkbox sheet
/// to change the set. Shared by add-ons, option groups and coupons — every
/// place in this catalogue that links to a subset of products.
class _ProductLinksField extends StatelessWidget {
  const _ProductLinksField({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// id -> name, so the field can show names without a second lookup.
  final Map<String, String> selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CrmField(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: InputDecorator(
          decoration: const InputDecoration(
            suffixIcon: Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            selected.isEmpty
                ? 'Every product'
                : selected.values.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: selected.isEmpty
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks a subset of the catalogue by checkbox. Loads once (a tenant's
/// product list is not the thousands-of-rows kind) and filters client-side —
/// simpler than a second search round-trip for a list this size.
class _ProductLinkPicker extends ConsumerStatefulWidget {
  const _ProductLinkPicker({required this.selected});

  final Map<String, String> selected;

  @override
  ConsumerState<_ProductLinkPicker> createState() =>
      _ProductLinkPickerState();
}

class _ProductLinkPickerState extends ConsumerState<_ProductLinkPicker> {
  late final Map<String, String> _chosen = Map.of(widget.selected);
  final _search = TextEditingController();
  List<ProductService> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(billingCatalogServiceProvider)
          .products(perPage: 200);
      if (mounted) setState(() => _all = page.items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _all
        : _all.where((p) => p.name.toLowerCase().contains(query)).toList();

    return CrmSheet(
      eyebrow: 'Catalog',
      title: 'Link products',
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Search products',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          ErrorBanner(message: _error!, onRetry: _load)
        else if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              'No products found.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, product) in filtered.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  CheckboxListTile(
                    dense: true,
                    value: _chosen.containsKey(product.id),
                    title: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _chosen[product.id] = product.name;
                      } else {
                        _chosen.remove(product.id);
                      }
                    }),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _chosen.isEmpty
              ? 'Use no products'
              : 'Use ${_chosen.length} product${_chosen.length == 1 ? '' : 's'}',
          onPressed: () => Navigator.of(context).pop(_chosen),
        ),
      ],
    );
  }
}

/// A tappable date field with an optional clear — the coupon window fields
/// and the renew dialog share it.
class _DatePickField extends StatelessWidget {
  const _DatePickField({
    required this.label,
    required this.date,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? date;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CrmField(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () => _pick(context),
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                ),
                child: Text(
                  date == null ? 'Not set' : Formatting.date(date),
                  style: TextStyle(
                    color: date == null
                        ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          if (date != null && onClear != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Products & services
// ---------------------------------------------------------------------------

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  void _reload() => _listKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.can(BillingCatalogPermissions.productsCreate);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Products & services',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add product',
                onPressed: () => _openProductForm(context, ref, null, _reload),
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name or code',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _reload();
          },
        ),
      ),
      body: PagedListView(
        key: _listKey,
        fetch: (page) => ref
            .read(billingCatalogServiceProvider)
            .products(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        itemBuilder: (context, product) =>
            _ProductRow(product: product, onChanged: _reload),
        emptyIcon: Icons.inventory_2_outlined,
        emptyTitle: 'No products found',
        emptyMessage: 'Try another name or product code.',
      ),
    );
  }
}

/// One catalogue line: what it is called, what it costs, and how it repeats.
///
/// Retired products keep their place in the list — they are still on old
/// invoices — so the draft chip, not absence, is what says "not on sale".
class _ProductRow extends ConsumerWidget {
  const _ProductRow({required this.product, required this.onChanged});

  final ProductService product;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUpdate = ref.can(BillingCatalogPermissions.productsUpdate);
    final canDelete = ref.can(BillingCatalogPermissions.productsDelete);
    final tappable = canUpdate || canDelete;

    // Cycle first: on a row this narrow the tail is what gets ellipsed, and
    // "does this bill again?" is the question a catalogue row is asked.
    final meta = [
      if (product.isRecurring) product.billingCycle!.replaceAll('_', ' '),
      if (product.unit != null) 'per ${product.unit}',
      if (product.code != null) product.code!,
      if (product.category != null) product.category!,
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: tappable
            ? () => _openProductActions(
                context,
                ref,
                product,
                canUpdate,
                canDelete,
                onChanged,
              )
            : null,
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: product.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ),
        trailing: Money(product.price),
      ),
    );
  }
}

Future<void> _openProductActions(
  BuildContext context,
  WidgetRef ref,
  ProductService product,
  bool canUpdate,
  bool canDelete,
  VoidCallback onChanged,
) async {
  final changed = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ActionsSheet(
      eyebrow: 'Products & services',
      title: product.name,
      subtitle: CrmStatusLine(
        status: product.isActive ? 'active' : 'draft',
        meta: product.type ?? '',
      ),
      actions: [
        _SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit product',
          onTap: canUpdate
              ? () async {
                  Navigator.of(context).pop();
                  await _openProductForm(context, ref, product, onChanged);
                }
              : null,
        ),
        _SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete product',
          destructive: true,
          onTap: canDelete
              ? () async {
                  final confirmed = await _confirmDelete(
                    context,
                    title: 'Delete ${product.name}?',
                    message:
                        'Past invoices keep their own copy of this line — '
                        'only new orders stop seeing it.',
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await ref
                        .read(billingCatalogServiceProvider)
                        .deleteProduct(product.id);
                    if (context.mounted) Navigator.of(context).pop(true);
                  } on ApiException catch (e) {
                    if (context.mounted) showCrmMessage(context, e.message);
                  }
                }
              : null,
        ),
      ],
    ),
  );
  if (changed == true) onChanged();
}

Future<void> _openProductForm(
  BuildContext context,
  WidgetRef ref,
  ProductService? existing,
  VoidCallback onChanged,
) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ProductForm(existing: existing),
  );
  if (saved == true) onChanged();
}

const _billingCycles = [
  ('once', 'One-time'),
  ('monthly', 'Monthly'),
  ('quarterly', 'Quarterly'),
  ('half_yearly', 'Half-yearly'),
  ('yearly', 'Yearly'),
];

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.existing});

  final ProductService? existing;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _price = TextEditingController(
    text: _plain(widget.existing?.price),
  );
  late final _tax = TextEditingController(
    text: _plain(widget.existing?.taxPercent),
  );
  late final _unit = TextEditingController(text: widget.existing?.unit ?? '');
  late final _category = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late final _package = TextEditingController();

  late String _type = widget.existing?.type ?? 'service';
  late String _cycle = widget.existing?.billingCycle ?? 'once';
  late bool _active = widget.existing?.isActive ?? true;

  // Write-only on the API: never echoed back by a GET, so an edit form has
  // nothing to prefill these from and re-asks every time — see
  // BillingCatalogService.updateProduct's doc comment.
  bool _portalVisible = true;
  bool _provision = false;
  String? _serverId;
  bool _autoProvision = false;
  bool _loadingPackages = false;

  bool _submitting = false;
  String? _error;

  ProductService? get existing => widget.existing;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    _price.dispose();
    _tax.dispose();
    _unit.dispose();
    _category.dispose();
    _package.dispose();
    super.dispose();
  }

  Future<void> _lookupPackages() async {
    final serverId = _serverId;
    if (serverId == null) return;
    setState(() => _loadingPackages = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final packages = await ref
          .read(supportAdminServiceProvider)
          .serverPackages(serverId);
      if (!mounted) return;
      if (packages.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('WHM answered, but offers no packages.')),
        );
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final name in packages)
                ListTile(
                  title: Text(name),
                  onTap: () => Navigator.of(context).pop(name),
                ),
            ],
          ),
        ),
      );
      if (picked != null) setState(() => _package.text = picked);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final price = _num(_price);
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }
    if (_provision && (_serverId == null || _package.text.trim().isEmpty)) {
      setState(
        () => _error = 'Choose a server and a cPanel package to provision.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final service = ref.read(billingCatalogServiceProvider);
    final code = _code.text.trim();
    final description = _description.text.trim();
    final unit = _unit.text.trim();
    final category = _category.text.trim();
    final provisioningType = _provision ? 'whm_cpanel' : 'none';

    try {
      if (existing == null) {
        await service.createProduct(
          type: _type,
          name: name,
          price: price,
          code: code.isEmpty ? null : code,
          description: description.isEmpty ? null : description,
          taxPercent: _num(_tax),
          unit: unit.isEmpty ? null : unit,
          category: category.isEmpty ? null : category,
          billingCycle: _cycle,
          isActive: _active,
          provisioningType: provisioningType,
          serverId: _provision ? _serverId : null,
          cpanelPackage: _provision ? _package.text.trim() : null,
          autoProvision: _provision && _autoProvision,
          portalVisible: _portalVisible,
        );
      } else {
        await service.updateProduct(
          existing!.id,
          type: _type,
          name: name,
          price: price,
          code: code.isEmpty ? null : code,
          description: description.isEmpty ? null : description,
          taxPercent: _num(_tax),
          unit: unit.isEmpty ? null : unit,
          category: category.isEmpty ? null : category,
          billingCycle: _cycle,
          isActive: _active,
          provisioningType: provisioningType,
          serverId: _provision ? _serverId : null,
          cpanelPackage: _provision ? _package.text.trim() : null,
          autoProvision: _provision && _autoProvision,
          portalVisible: _portalVisible,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error =
            e.errorFor('name') ??
            e.errorFor('price') ??
            e.errorFor('server_id') ??
            e.errorFor('cpanel_package') ??
            e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = existing == null;
    final canHosting = ref.can(SupportAdminPermissions.hostingSettings);
    final showHosting = _type == 'service' && canHosting;

    return CrmSheet(
      eyebrow: 'Products & services',
      title: adding ? 'Add product' : 'Edit product',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Kind',
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'product', label: Text('Product')),
              ButtonSegment(value: 'service', label: Text('Service')),
            ],
            selected: {_type},
            onSelectionChanged: _submitting
                ? null
                : (choice) => setState(() => _type = choice.first),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Name',
          child: TextField(controller: _name, enabled: !_submitting),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Code',
                child: TextField(
                  controller: _code,
                  enabled: !_submitting,
                  decoration: const InputDecoration(hintText: 'Optional'),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Category',
                child: TextField(
                  controller: _category,
                  enabled: !_submitting,
                  decoration: const InputDecoration(hintText: 'Optional'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Price',
                child: TextField(
                  controller: _price,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: '${Formatting.tenantCurrency} ',
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Tax',
                child: TextField(
                  controller: _tax,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'None',
                    suffixText: '%',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Unit',
                child: TextField(
                  controller: _unit,
                  enabled: !_submitting,
                  decoration: const InputDecoration(hintText: 'e.g. user'),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Billing cycle',
                child: DropdownButtonFormField<String>(
                  initialValue: _cycle,
                  items: [
                    for (final (value, label) in _billingCycles)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _cycle = v ?? _cycle),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Retired products stay on old invoices'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible in client portal'),
          value: _portalVisible,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _portalVisible = v),
        ),
        if (showHosting) ...[
          const Divider(height: Spacing.lg),
          Text('Hosting provisioning', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          Text(
            'Write-only: not shown by the API, so every save applies exactly '
            'what is set here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Provision on WHM/cPanel'),
            value: _provision,
            onChanged: _submitting
                ? null
                : (v) => setState(() => _provision = v),
          ),
          if (_provision) ...[
            const SizedBox(height: Spacing.sm),
            ref
                .watch(hostingServersProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    'Could not load servers.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  data: (items) => CrmField(
                    label: 'Server',
                    child: DropdownButtonFormField<String>(
                      initialValue: _serverId,
                      items: [
                        for (final server in items)
                          DropdownMenuItem(
                            value: server.id,
                            child: Text(
                              server.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      decoration: const InputDecoration(hintText: 'Choose a server'),
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _serverId = v),
                    ),
                  ),
                ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'cPanel package',
              child: TextField(
                controller: _package,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: 'Package name',
                  suffixIcon: _serverId == null
                      ? null
                      : IconButton(
                          tooltip: 'Look up from server',
                          icon: _loadingPackages
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search, size: 20),
                          onPressed: _loadingPackages ? null : _lookupPackages,
                        ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Provision automatically'),
              subtitle: const Text('On activation, without a manual step'),
              value: _autoProvision,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _autoProvision = v),
            ),
          ],
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : (adding ? 'Add product' : 'Save product'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Product add-ons
// ---------------------------------------------------------------------------

class ProductAddonsScreen extends ConsumerWidget {
  const ProductAddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonsProvider(null));
    final canCreate = ref.can(BillingCatalogPermissions.productsCreate);
    void reload() => ref.invalidate(addonsProvider(null));

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Product add-ons',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add add-on',
                onPressed: () => _openAddonForm(context, ref, null, reload),
              )
            : null,
      ),
      body: CrmAsyncView(
        value: addons,
        errorTitle: 'Could not load add-ons',
        onRetry: reload,
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.add_box_outlined,
                title: 'No add-ons configured',
                message: 'Extras sold alongside a product appear here.',
                actionLabel: canCreate ? 'Add add-on' : null,
                onAction: canCreate
                    ? () => _openAddonForm(context, ref, null, reload)
                    : null,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(addonsProvider(null).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  children: [
                    CrmCardList(
                      children: [
                        for (final addon in items)
                          _AddonTile(addon: addon, onChanged: reload),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// An add-on is only meaningful next to the products that offer it, so the
/// linking — or the absence of any — is the line under the name.
class _AddonTile extends ConsumerWidget {
  const _AddonTile({required this.addon, required this.onChanged});

  final StaffProductAddon addon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canUpdate = ref.can(BillingCatalogPermissions.productsUpdate);
    final canDelete = ref.can(BillingCatalogPermissions.productsDelete);
    final meta = [
      if (addon.billingCycle != null) addon.billingCycle!.replaceAll('_', ' '),
      addon.productNames.isEmpty
          ? 'not linked to a product'
          : 'on ${addon.productNames.join(', ')}',
    ].join(' · ');

    return ListTile(
      onTap: (canUpdate || canDelete)
          ? () => _openAddonActions(
              context,
              ref,
              addon,
              canUpdate,
              canDelete,
              onChanged,
            )
          : null,
      title: Text(addon.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (addon.description != null) ...[
            const SizedBox(height: 2),
            Text(
              addon.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          addon.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ],
      ),
      trailing: Money(addon.price),
    );
  }
}

Future<void> _openAddonActions(
  BuildContext context,
  WidgetRef ref,
  StaffProductAddon addon,
  bool canUpdate,
  bool canDelete,
  VoidCallback onChanged,
) async {
  final changed = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ActionsSheet(
      eyebrow: 'Product add-ons',
      title: addon.name,
      subtitle: CrmStatusLine(
        status: addon.isActive ? 'active' : 'draft',
        meta: addon.billingCycle?.replaceAll('_', ' ') ?? '',
      ),
      actions: [
        _SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit add-on',
          onTap: canUpdate
              ? () async {
                  Navigator.of(context).pop();
                  await _openAddonForm(context, ref, addon, onChanged);
                }
              : null,
        ),
        _SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete add-on',
          destructive: true,
          onTap: canDelete
              ? () async {
                  final confirmed = await _confirmDelete(
                    context,
                    title: 'Delete ${addon.name}?',
                    message:
                        'A service that already has this add-on keeps its '
                        'own attached copy — this only stops it being '
                        'offered on new orders.',
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await ref
                        .read(billingCatalogServiceProvider)
                        .deleteAddon(addon.id);
                    if (context.mounted) Navigator.of(context).pop(true);
                  } on ApiException catch (e) {
                    if (context.mounted) showCrmMessage(context, e.message);
                  }
                }
              : null,
        ),
      ],
    ),
  );
  if (changed == true) onChanged();
}

Future<void> _openAddonForm(
  BuildContext context,
  WidgetRef ref,
  StaffProductAddon? existing,
  VoidCallback onChanged,
) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _AddonForm(existing: existing),
  );
  if (saved == true) onChanged();
}

class _AddonForm extends ConsumerStatefulWidget {
  const _AddonForm({this.existing});

  final StaffProductAddon? existing;

  @override
  ConsumerState<_AddonForm> createState() => _AddonFormState();
}

class _AddonFormState extends ConsumerState<_AddonForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _price = TextEditingController(
    text: _plain(widget.existing?.price),
  );
  late final _tax = TextEditingController(
    text: _plain(widget.existing?.taxPercent),
  );
  late String _cycle = widget.existing?.billingCycle ?? 'monthly';
  late bool _active = widget.existing?.isActive ?? true;
  late Map<String, String> _products = {
    for (final (i, id) in (widget.existing?.productIds ?? const []).indexed)
      id: widget.existing!.productNames[i],
  };

  bool _submitting = false;
  String? _error;

  StaffProductAddon? get existing => widget.existing;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _tax.dispose();
    super.dispose();
  }

  Future<void> _pickProducts() async {
    final chosen = await showCrmSheet<Map<String, String>>(
      context: context,
      builder: (_) => _ProductLinkPicker(selected: _products),
    );
    if (chosen != null) setState(() => _products = chosen);
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final price = _num(_price);
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = 'Enter a valid price.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final service = ref.read(billingCatalogServiceProvider);
    final description = _description.text.trim();
    try {
      if (existing == null) {
        await service.createAddon(
          name: name,
          price: price,
          billingCycle: _cycle,
          description: description.isEmpty ? null : description,
          taxPercent: _num(_tax),
          isActive: _active,
          productServiceIds: _products.keys.toList(),
        );
      } else {
        await service.updateAddon(
          existing!.id,
          name: name,
          price: price,
          billingCycle: _cycle,
          description: description.isEmpty ? null : description,
          taxPercent: _num(_tax),
          isActive: _active,
          productServiceIds: _products.keys.toList(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.errorFor('name') ?? e.errorFor('price') ?? e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = existing == null;

    return CrmSheet(
      eyebrow: 'Product add-ons',
      title: adding ? 'Add an add-on' : 'Edit add-on',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(controller: _name, enabled: !_submitting),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Price',
                child: TextField(
                  controller: _price,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: '${Formatting.tenantCurrency} ',
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Tax',
                child: TextField(
                  controller: _tax,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'None',
                    suffixText: '%',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Billing cycle',
          child: DropdownButtonFormField<String>(
            initialValue: _cycle,
            items: [
              for (final (value, label) in _billingCycles)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _cycle = v ?? _cycle),
          ),
        ),
        const SizedBox(height: Spacing.md),
        _ProductLinksField(
          label: 'Linked products',
          selected: _products,
          onTap: _submitting ? null : _pickProducts,
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Offered to clients placing a new order'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : (adding ? 'Add add-on' : 'Save add-on'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Configurable options
// ---------------------------------------------------------------------------

class ConfigOptionsScreen extends ConsumerWidget {
  const ConfigOptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(configGroupsProvider(null));
    final canCreate = ref.can(BillingCatalogPermissions.productsCreate);
    void reload() => ref.invalidate(configGroupsProvider(null));

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Configurable options',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add option group',
                onPressed: () => _openConfigGroupForm(context, ref, null, reload),
              )
            : null,
      ),
      body: CrmAsyncView(
        value: groups,
        errorTitle: 'Could not load option groups',
        onRetry: reload,
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.settings_input_component_outlined,
                title: 'No option groups configured',
                message: 'Choices offered while ordering a product show here.',
                actionLabel: canCreate ? 'Add option group' : null,
                onAction: canCreate
                    ? () => _openConfigGroupForm(context, ref, null, reload)
                    : null,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(configGroupsProvider(null).future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _ConfigGroupCard(group: items[index], onChanged: reload),
                ),
              ),
      ),
    );
  }
}

/// A group collapsed to its name and shape; the choices and their prices are
/// one tap away, because a screen that expands every group at once is a wall
/// of prices nobody is reading yet.
///
/// Tapping the tile expands it — that gesture is already spoken for — so
/// edit/delete live in the popup beside the name instead of on the tile tap
/// the way the other catalogue rows do.
class _ConfigGroupCard extends ConsumerWidget {
  const _ConfigGroupCard({required this.group, required this.onChanged});

  final StaffConfigGroup group;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUpdate = ref.can(BillingCatalogPermissions.productsUpdate);
    final canDelete = ref.can(BillingCatalogPermissions.productsDelete);
    final count = group.options.length;
    final meta = [
      '$count option${count == 1 ? '' : 's'}',
      if (group.productNames.isNotEmpty) 'on ${group.productNames.join(', ')}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canUpdate || canDelete)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Option group actions',
                onSelected: (action) async {
                  if (action == 'edit') {
                    final saved = await showCrmSheet<bool>(
                      context: context,
                      builder: (_) => _ConfigGroupForm(existing: group),
                    );
                    if (saved == true) onChanged();
                  } else if (action == 'delete') {
                    final confirmed = await _confirmDelete(
                      context,
                      title: 'Delete ${group.name}?',
                      message:
                          'Every option and choice in this group goes with '
                          'it.',
                    );
                    if (!confirmed || !context.mounted) return;
                    try {
                      await ref
                          .read(billingCatalogServiceProvider)
                          .deleteConfigGroup(group.id);
                      onChanged();
                    } on ApiException catch (e) {
                      if (context.mounted) showCrmMessage(context, e.message);
                    }
                  }
                },
                itemBuilder: (context) => [
                  if (canUpdate)
                    const PopupMenuItem(value: 'edit', child: Text('Edit group')),
                  if (canDelete)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete group'),
                    ),
                ],
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: group.isActive
              ? CrmMetaLine(meta)
              : CrmStatusLine(status: 'draft', meta: meta),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, option) in group.options.indexed) ...[
            if (i > 0) const Divider(height: Spacing.lg),
            _OptionBlock(option: option),
          ],
        ],
      ),
    );
  }
}

class _OptionBlock extends StatelessWidget {
  const _OptionBlock({required this.option});

  final StaffConfigOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(option.name, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        CrmMetaLine(option.optionType),
        // A per-unit price and a choice's price are the same kind of figure,
        // so they are set as the same row rather than one of them hiding in
        // the caption above.
        if (option.unitPrice != null)
          _PriceRow(label: 'Per unit', price: option.unitPrice!),
        for (final choice in option.choices)
          _PriceRow(label: choice.label, price: choice.price),
      ],
    );
  }
}

/// A named price inside an option group: what the choice is called, what it
/// adds. The currency code is left off — the card is all one currency, and
/// repeating it down a column of small figures is noise.
class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.price});

  final String label;
  final double price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // "Included" is the news when a choice costs nothing; a 0.00 in the
          // money column would say it less clearly.
          if (price == 0)
            const CrmMetaLine('included')
          else
            Money(price, scale: MoneyScale.dense, showCode: false),
        ],
      ),
    );
  }
}

Future<void> _openConfigGroupForm(
  BuildContext context,
  WidgetRef ref,
  StaffConfigGroup? existing,
  VoidCallback onChanged,
) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ConfigGroupForm(existing: existing),
  );
  if (saved == true) onChanged();
}

const _optionTypes = [
  ('dropdown', 'Dropdown'),
  ('radio', 'Radio'),
  ('quantity', 'Quantity'),
  ('yesno', 'Yes / No'),
];

class _ConfigGroupForm extends ConsumerStatefulWidget {
  const _ConfigGroupForm({this.existing});

  final StaffConfigGroup? existing;

  @override
  ConsumerState<_ConfigGroupForm> createState() => _ConfigGroupFormState();
}

class _ConfigGroupFormState extends ConsumerState<_ConfigGroupForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late bool _active = widget.existing?.isActive ?? true;
  late Map<String, String> _products = {
    for (final (i, id) in (widget.existing?.productIds ?? const []).indexed)
      id: widget.existing!.productNames[i],
  };

  // The whole option tree, mutated in place by the option/choice editors
  // below — see ConfigOptionInput's doc comment: this list is sent whole on
  // save, replacing what the server has.
  late final List<ConfigOptionInput> _options = [
    for (final o in widget.existing?.options ?? const []) o.toInput(),
  ];

  bool _submitting = false;
  String? _error;

  StaffConfigGroup? get existing => widget.existing;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickProducts() async {
    final chosen = await showCrmSheet<Map<String, String>>(
      context: context,
      builder: (_) => _ProductLinkPicker(selected: _products),
    );
    if (chosen != null) setState(() => _products = chosen);
  }

  void _addOption() => setState(
    () => _options.add(
      ConfigOptionInput(name: '', optionType: 'dropdown', choices: []),
    ),
  );

  void _removeOption(int index) => setState(() => _options.removeAt(index));

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    for (final option in _options) {
      if (option.name.trim().isEmpty) {
        setState(() => _error = 'Every option needs a name.');
        return;
      }
      final hasChoices =
          option.optionType == 'dropdown' || option.optionType == 'radio';
      if (hasChoices && option.choices.isEmpty) {
        setState(() => _error = '"${option.name}" needs at least one choice.');
        return;
      }
      for (final choice in option.choices) {
        if (choice.label.trim().isEmpty) {
          setState(() => _error = 'Every choice needs a label.');
          return;
        }
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final service = ref.read(billingCatalogServiceProvider);
    final description = _description.text.trim();
    try {
      if (existing == null) {
        await service.createConfigGroup(
          name: name,
          description: description.isEmpty ? null : description,
          isActive: _active,
          productServiceIds: _products.keys.toList(),
          options: _options,
        );
      } else {
        await service.updateConfigGroup(
          existing!.id,
          name: name,
          description: description.isEmpty ? null : description,
          isActive: _active,
          productServiceIds: _products.keys.toList(),
          options: _options,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.errorFor('name') ?? e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adding = existing == null;

    return CrmSheet(
      eyebrow: 'Configurable options',
      title: adding ? 'Add option group' : 'Edit option group',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(controller: _name, enabled: !_submitting),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        _ProductLinksField(
          label: 'Linked products',
          selected: _products,
          onTap: _submitting ? null : _pickProducts,
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        const SizedBox(height: Spacing.lg),
        Row(
          children: [
            Expanded(
              child: Text('Options', style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: _submitting ? null : _addOption,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add option'),
            ),
          ],
        ),
        if (_options.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Text(
              'No options yet — add one so clients have something to choose.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (i, option) in _options.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _OptionEditor(
                key: ObjectKey(option),
                option: option,
                enabled: !_submitting,
                onRemove: () => _removeOption(i),
              ),
            ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : (adding ? 'Add group' : 'Save group'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// One option in the tree, edited in place: its own name/type/price, and —
/// for dropdown/radio — the nested list of priced choices. Mutates
/// [option] directly rather than reporting changes upward, since the parent
/// form only needs the finished tree at save time.
class _OptionEditor extends StatefulWidget {
  const _OptionEditor({
    super.key,
    required this.option,
    required this.enabled,
    required this.onRemove,
  });

  final ConfigOptionInput option;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  late final _name = TextEditingController(text: widget.option.name);
  late final _unitPrice = TextEditingController(
    text: _plain(widget.option.unitPrice),
  );

  bool get _hasChoices =>
      widget.option.optionType == 'dropdown' ||
      widget.option.optionType == 'radio';

  @override
  void dispose() {
    _name.dispose();
    _unitPrice.dispose();
    super.dispose();
  }

  void _addChoice() =>
      setState(() => widget.option.choices.add(ConfigChoiceInput(label: '')));

  void _removeChoice(int index) =>
      setState(() => widget.option.choices.removeAt(index));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  enabled: widget.enabled,
                  onChanged: (v) => widget.option.name = v,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Option name',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Remove option',
                onPressed: widget.enabled ? widget.onRemove : null,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String>(
            initialValue: widget.option.optionType,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final (value, label) in _optionTypes)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: widget.enabled
                ? (v) => setState(
                    () => widget.option.optionType = v ?? widget.option.optionType,
                  )
                : null,
          ),
          if (!_hasChoices) ...[
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _unitPrice,
              enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) =>
                  widget.option.unitPrice = double.tryParse(v.replaceAll(',', '')),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Unit price',
                prefixText: '${Formatting.tenantCurrency} ',
              ),
            ),
          ] else ...[
            const SizedBox(height: Spacing.sm),
            for (final (i, choice) in widget.option.choices.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: _ChoiceRow(
                  key: ObjectKey(choice),
                  choice: choice,
                  enabled: widget.enabled,
                  onRemove: () => _removeChoice(i),
                ),
              ),
            TextButton.icon(
              onPressed: widget.enabled ? _addChoice : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add choice'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatefulWidget {
  const _ChoiceRow({
    super.key,
    required this.choice,
    required this.enabled,
    required this.onRemove,
  });

  final ConfigChoiceInput choice;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  State<_ChoiceRow> createState() => _ChoiceRowState();
}

class _ChoiceRowState extends State<_ChoiceRow> {
  late final _label = TextEditingController(text: widget.choice.label);
  late final _price = TextEditingController(text: _plain(widget.choice.price));

  @override
  void dispose() {
    _label.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _label,
            enabled: widget.enabled,
            onChanged: (v) => widget.choice.label = v,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Choice label',
            ),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _price,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) =>
                widget.choice.price = double.tryParse(v.replaceAll(',', '')) ?? 0,
            decoration: const InputDecoration(isDense: true, hintText: '0.00'),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Remove choice',
          visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? widget.onRemove : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coupons
// ---------------------------------------------------------------------------

class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider(null));
    final canCreate = ref.can(BillingCatalogPermissions.productsCreate);
    void reload() => ref.invalidate(couponsProvider(null));

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Promotions & coupons',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add coupon',
                onPressed: () => _openCouponForm(context, ref, null, reload),
              )
            : null,
      ),
      body: CrmAsyncView(
        value: coupons,
        errorTitle: 'Could not load coupons',
        onRetry: reload,
        builder: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.local_offer_outlined,
                title: 'No coupons configured',
                message: 'Discount codes clients can redeem appear here.',
                actionLabel: canCreate ? 'Add coupon' : null,
                onAction: canCreate
                    ? () => _openCouponForm(context, ref, null, reload)
                    : null,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(couponsProvider(null).future),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) =>
                      _CouponCard(coupon: items[index], onChanged: reload),
                ),
              ),
      ),
    );
  }
}

/// A coupon reads as the code first — that is the thing a client quotes down
/// the phone — with the discount beside it and the conditions that make it
/// usable (or not) in the eyebrow line underneath.
class _CouponCard extends ConsumerWidget {
  const _CouponCard({required this.coupon, required this.onChanged});

  final StaffCoupon coupon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canUpdate = ref.can(BillingCatalogPermissions.productsUpdate);
    final canDelete = ref.can(BillingCatalogPermissions.productsDelete);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openCouponActions(
          context,
          ref,
          coupon,
          canUpdate,
          canDelete,
          onChanged,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      coupon.code.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The one place a code is set in the utility face at
                      // reading size: it is a string to be typed, not read.
                      style: Type.mono(
                        15,
                        weight: FontWeight.w600,
                        tracking: 0.06,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  // A percentage renders itself; a fixed amount is money, and
                  // is set as money.
                  if (coupon.percentLabel != null)
                    Text(
                      coupon.percentLabel!,
                      style: TextStyle(
                        fontSize: MoneyScale.row.size,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: scheme.onSurface,
                        fontFeatures: Type.figures,
                      ),
                    )
                  else
                    Money(coupon.value),
                ],
              ),
              if (coupon.description != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  coupon.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.sm),
              CrmStatusLine(
                status: coupon.status,
                meta: [
                  coupon.maxUses == null
                      ? '${coupon.uses} use${coupon.uses == 1 ? '' : 's'}'
                      : '${coupon.uses}/${coupon.maxUses} used',
                  if (coupon.recurring) 'recurring',
                  if (coupon.minOrder != null)
                    'min ${Formatting.amount(coupon.minOrder)}',
                  if (coupon.expiresAt != null)
                    'expires ${Formatting.date(coupon.expiresAt)}',
                ].join(' · '),
              ),
              if (coupon.productNames.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                CrmMetaLine('on ${coupon.productNames.join(', ')}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openCouponActions(
  BuildContext context,
  WidgetRef ref,
  StaffCoupon coupon,
  bool canUpdate,
  bool canDelete,
  VoidCallback onChanged,
) async {
  final changed = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ActionsSheet(
      eyebrow: 'Promotions & coupons',
      title: coupon.code.toUpperCase(),
      subtitle: CrmStatusLine(status: coupon.status, meta: coupon.description ?? ''),
      actions: [
        _SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit coupon',
          onTap: canUpdate
              ? () async {
                  Navigator.of(context).pop();
                  await _openCouponForm(context, ref, coupon, onChanged);
                }
              : null,
        ),
        _SheetAction(
          icon: Icons.history_outlined,
          label: 'Redemption history',
          onTap: () async {
            Navigator.of(context).pop();
            await showCrmSheet<void>(
              context: context,
              builder: (_) => _RedemptionsSheet(coupon: coupon),
            );
          },
        ),
        _SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete coupon',
          destructive: true,
          onTap: canDelete
              ? () async {
                  final confirmed = await _confirmDelete(
                    context,
                    title: 'Delete ${coupon.code.toUpperCase()}?',
                    message: 'Clients will no longer be able to redeem it.',
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await ref
                        .read(billingCatalogServiceProvider)
                        .deleteCoupon(coupon.id);
                    if (context.mounted) Navigator.of(context).pop(true);
                  } on ApiException catch (e) {
                    if (context.mounted) showCrmMessage(context, e.message);
                  }
                }
              : null,
        ),
      ],
    ),
  );
  if (changed == true) onChanged();
}

/// Who used this code and what it saved them — the audit trail a coupon
/// otherwise has no way to show from the row alone.
class _RedemptionsSheet extends ConsumerStatefulWidget {
  const _RedemptionsSheet({required this.coupon});

  final StaffCoupon coupon;

  @override
  ConsumerState<_RedemptionsSheet> createState() => _RedemptionsSheetState();
}

class _RedemptionsSheetState extends ConsumerState<_RedemptionsSheet> {
  List<CouponRedemption>? _redemptions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await ref
          .read(billingCatalogServiceProvider)
          .couponRedemptions(widget.coupon.id);
      if (mounted) setState(() => _redemptions = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _redemptions;

    return CrmSheet(
      eyebrow: widget.coupon.code.toUpperCase(),
      title: 'Redemption history',
      children: [
        if (_error != null)
          ErrorBanner(message: _error!, onRetry: _load)
        else if (rows == null)
          const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Text(
              'Nobody has redeemed this code yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(row.clientName ?? 'Unknown client'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CrmMetaLine(Formatting.date(row.createdAt)),
                    ),
                    trailing: Money(
                      row.discountAmount,
                      scale: MoneyScale.dense,
                      showCode: false,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> _openCouponForm(
  BuildContext context,
  WidgetRef ref,
  StaffCoupon? existing,
  VoidCallback onChanged,
) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _CouponForm(existing: existing),
  );
  if (saved == true) onChanged();
}

class _CouponForm extends ConsumerStatefulWidget {
  const _CouponForm({this.existing});

  final StaffCoupon? existing;

  @override
  ConsumerState<_CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends ConsumerState<_CouponForm> {
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _value = TextEditingController(
    text: _plain(widget.existing?.value),
  );
  late final _maxUses = TextEditingController(
    text: widget.existing?.maxUses?.toString() ?? '',
  );
  late final _minOrder = TextEditingController(
    text: _plain(widget.existing?.minOrder),
  );

  late String _type = widget.existing?.type ?? 'percent';
  late String _appliesTo = widget.existing?.appliesTo ?? 'all';
  late DateTime? _startsAt = widget.existing?.startsAt;
  late DateTime? _expiresAt = widget.existing?.expiresAt;
  late bool _recurring = widget.existing?.recurring ?? false;
  late bool _active = widget.existing?.isActive ?? true;
  late Map<String, String> _products = {
    for (final (i, id) in (widget.existing?.productIds ?? const []).indexed)
      id: widget.existing!.productNames[i],
  };

  bool _submitting = false;
  String? _error;

  StaffCoupon? get existing => widget.existing;

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _value.dispose();
    _maxUses.dispose();
    _minOrder.dispose();
    super.dispose();
  }

  Future<void> _pickProducts() async {
    final chosen = await showCrmSheet<Map<String, String>>(
      context: context,
      builder: (_) => _ProductLinkPicker(selected: _products),
    );
    if (chosen != null) setState(() => _products = chosen);
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final value = _num(_value);
    if (code.isEmpty) {
      setState(() => _error = 'A code is required.');
      return;
    }
    if (value == null || value < 0) {
      setState(() => _error = 'Enter a valid value.');
      return;
    }
    if (_expiresAt != null &&
        _startsAt != null &&
        _expiresAt!.isBefore(_startsAt!)) {
      setState(() => _error = 'The expiry date must be on or after the start.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final service = ref.read(billingCatalogServiceProvider);
    final description = _description.text.trim();
    final productIds = _appliesTo == 'product' ? _products.keys.toList() : <String>[];
    try {
      if (existing == null) {
        await service.createCoupon(
          code: code,
          type: _type,
          value: value,
          description: description.isEmpty ? null : description,
          appliesTo: _appliesTo,
          maxUses: _int(_maxUses),
          minOrder: _num(_minOrder),
          startsAt: _startsAt,
          expiresAt: _expiresAt,
          recurring: _recurring,
          isActive: _active,
          productServiceIds: productIds,
        );
      } else {
        await service.updateCoupon(
          existing!.id,
          code: code,
          type: _type,
          value: value,
          description: description.isEmpty ? null : description,
          appliesTo: _appliesTo,
          maxUses: _int(_maxUses),
          minOrder: _num(_minOrder),
          startsAt: _startsAt,
          expiresAt: _expiresAt,
          recurring: _recurring,
          isActive: _active,
          productServiceIds: productIds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.errorFor('code') ?? e.errorFor('value') ?? e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = existing == null;

    return CrmSheet(
      eyebrow: 'Promotions & coupons',
      title: adding ? 'Add coupon' : 'Edit coupon',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Code',
          child: TextField(
            controller: _code,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'SAVE10'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Description',
          child: TextField(
            controller: _description,
            enabled: !_submitting,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Type',
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'percent', label: Text('Percent')),
                    ButtonSegment(value: 'fixed', label: Text('Fixed')),
                  ],
                  selected: {_type},
                  onSelectionChanged: _submitting
                      ? null
                      : (choice) => setState(() => _type = choice.first),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Value',
          child: TextField(
            controller: _value,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: _type == 'percent' ? '%' : Formatting.tenantCurrency,
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Applies to',
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'all', label: Text('All products')),
              ButtonSegment(value: 'product', label: Text('Specific')),
            ],
            selected: {_appliesTo},
            onSelectionChanged: _submitting
                ? null
                : (choice) => setState(() => _appliesTo = choice.first),
          ),
        ),
        if (_appliesTo == 'product') ...[
          const SizedBox(height: Spacing.md),
          _ProductLinksField(
            label: 'Products',
            selected: _products,
            onTap: _submitting ? null : _pickProducts,
          ),
        ],
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Max uses',
                child: TextField(
                  controller: _maxUses,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Unlimited'),
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Min order',
                child: TextField(
                  controller: _minOrder,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(hintText: 'None'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DatePickField(
                label: 'Starts',
                date: _startsAt,
                onPick: (d) => setState(() => _startsAt = d),
                onClear: () => setState(() => _startsAt = null),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: _DatePickField(
                label: 'Expires',
                date: _expiresAt,
                onPick: (d) => setState(() => _expiresAt = d),
                onClear: () => setState(() => _expiresAt = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Recurring'),
          subtitle: const Text('Discount repeats on renewal, not just once'),
          value: _recurring,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _recurring = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : (adding ? 'Add coupon' : 'Save coupon'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Subscriptions (staff, tenant-wide)
// ---------------------------------------------------------------------------

class StaffSubscriptionsScreen extends ConsumerStatefulWidget {
  const StaffSubscriptionsScreen({super.key});

  @override
  ConsumerState<StaffSubscriptionsScreen> createState() =>
      _StaffSubscriptionsScreenState();
}

class _StaffSubscriptionsScreenState
    extends ConsumerState<StaffSubscriptionsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;
  final Set<String> _billing = {};

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('suspended', 'Suspended'),
    ('cancelled', 'Cancelled'),
    ('terminated', 'Terminated'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  void _reload() => _listKey.currentState?.reload();

  @override
  Widget build(BuildContext context) {
    final canGenerate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(BillingMoneyPermissions.subscriptionsCreate) ??
        false;
    final canCreate = ref.can(BillingCatalogPermissions.subscriptionsCreate);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Billing',
        title: 'Subscriptions',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add subscription',
                onPressed: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const _SubscriptionCreateScreen()),
                  );
                  if (saved == true) _reload();
                },
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search client or product',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _reload();
          },
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (value) {
              setState(() => _status = value);
              _reload();
            },
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref
                  .read(billingCatalogServiceProvider)
                  .subscriptions(
                    status: _status,
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    page: page,
                  ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                Spacing.xl,
              ),
              itemBuilder: (context, sub) => _SubscriptionCard(
                subscription: sub,
                canGenerate: canGenerate,
                busy: _billing.contains(sub.id),
                onGenerate: () => _generateInvoice(sub),
                onChanged: _reload,
              ),
              emptyIcon: Icons.autorenew_outlined,
              emptyTitle: 'No subscriptions found',
              emptyMessage: 'Try another client, product or filter.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateInvoice(StaffSubscription sub) async {
    if (_billing.contains(sub.id)) return;
    setState(() => _billing.add(sub.id));

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Reuses the money service — the same endpoint the Next Bills screen
      // calls, so behaviour stays identical wherever staff trigger it.
      final invoice = await ref
          .read(billingMoneyServiceProvider)
          .generateInvoice(sub.id);
      ref.invalidate(dashboardProvider);
      _reload();
      messenger.showSnackBar(SnackBar(content: Text(invoice.message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _billing.remove(sub.id));
    }
  }
}

/// One subscription: whose it is, what it renews, and what it is worth per
/// cycle. Billing it early is an action with consequences, so it sits on its
/// own line under the row rather than inside the reading path.
class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.canGenerate,
    required this.busy,
    required this.onGenerate,
    required this.onChanged,
  });

  final StaffSubscription subscription;
  final bool canGenerate;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final sub = subscription;
    final cycle = sub.billingCycle;
    final expiring = Formatting.daysUntil(sub.expireDate);
    final lapsed = expiring != null && expiring < 0;
    final billable = canGenerate && sub.status == 'active';
    final canUpdate = ref.can(BillingCatalogPermissions.subscriptionsUpdate);
    final canDelete = ref.can(BillingCatalogPermissions.subscriptionsDelete);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: (canUpdate || canDelete)
                ? () => _openSubscriptionActions(
                    context,
                    ref,
                    sub,
                    canUpdate,
                    canDelete,
                    onChanged,
                  )
                : null,
            title: Text(
              sub.clientName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  [
                    sub.productName ?? 'Service',
                    if (sub.label != null) sub.label!,
                  ].join(' — '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                CrmStatusLine(
                  status: sub.status,
                  // An expiry that has passed is the one thing on this row
                  // worth colouring.
                  tone: lapsed ? status.overdue : null,
                  // The renewal date leads and is left unlabelled: the tail of
                  // this line is what gets ellipsed on a phone, and on a
                  // subscription row the only date there is is the one it
                  // runs out on. Past it, the whole line turns red.
                  meta: [
                    if (sub.expireDate != null) Formatting.date(sub.expireDate),
                    if (cycle != null && cycle != 'once')
                      cycle.replaceAll('_', ' '),
                    if (sub.quantity > 1) '×${sub.quantity}',
                  ].join(' · '),
                ),
              ],
            ),
            trailing: Money(sub.lineTotal),
          ),
          if (billable)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.sm,
                0,
                Spacing.sm,
                Spacing.xs,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: busy ? null : onGenerate,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text(busy ? 'Billing…' : 'Bill now'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _openSubscriptionActions(
  BuildContext context,
  WidgetRef ref,
  StaffSubscription sub,
  bool canUpdate,
  bool canDelete,
  VoidCallback onChanged,
) async {
  final changed = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ActionsSheet(
      eyebrow: sub.clientName ?? 'Subscription',
      title: sub.productName ?? 'Service',
      subtitle: CrmStatusLine(
        status: sub.status,
        meta: sub.expireDate == null ? '' : 'renews ${Formatting.date(sub.expireDate)}',
      ),
      actions: [
        _SheetAction(
          icon: Icons.edit_outlined,
          label: 'Edit subscription',
          onTap: canUpdate
              ? () async {
                  Navigator.of(context).pop();
                  final saved = await showCrmSheet<bool>(
                    context: context,
                    builder: (_) => _SubscriptionEditForm(subscription: sub),
                  );
                  if (saved == true) onChanged();
                }
              : null,
        ),
        _SheetAction(
          icon: Icons.autorenew_rounded,
          label: 'Renew / update expiry',
          onTap: canUpdate
              ? () async {
                  Navigator.of(context).pop();
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: sub.expireDate ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked == null || !context.mounted) return;
                  try {
                    await ref
                        .read(billingCatalogServiceProvider)
                        .renewSubscription(sub.id, expireDate: picked);
                    onChanged();
                  } on ApiException catch (e) {
                    if (context.mounted) showCrmMessage(context, e.message);
                  }
                }
              : null,
        ),
        _SheetAction(
          icon: Icons.delete_outline,
          label: 'Delete subscription',
          destructive: true,
          onTap: canDelete
              ? () async {
                  final confirmed = await _confirmDelete(
                    context,
                    title: 'Delete this subscription?',
                    message:
                        'The billing record only — a provisioned hosting '
                        'account keeps running unbilled unless it is '
                        'terminated separately.',
                  );
                  if (!confirmed || !context.mounted) return;
                  try {
                    await ref
                        .read(billingCatalogServiceProvider)
                        .deleteSubscription(sub.id);
                    if (context.mounted) Navigator.of(context).pop(true);
                  } on ApiException catch (e) {
                    if (context.mounted) showCrmMessage(context, e.message);
                  }
                }
              : null,
        ),
      ],
    ),
  );
  if (changed == true) onChanged();
}

/// One line of a new order — the product, and the label/quantity/discount
/// that ride with it. `SubscriptionLineInput` carries no product name, so it
/// travels alongside its own draft here for display.
class _LineDraft {
  _LineDraft({required this.input, required this.productName});

  final SubscriptionLineInput input;
  String productName;
}

/// Raise one or more subscriptions for a client in one order — the bulk
/// endpoint the web's own "New subscription" modal calls, so a multi-product
/// order becomes one start date and one status shared by every line.
class _SubscriptionCreateScreen extends ConsumerStatefulWidget {
  const _SubscriptionCreateScreen();

  @override
  ConsumerState<_SubscriptionCreateScreen> createState() =>
      _SubscriptionCreateScreenState();
}

class _SubscriptionCreateScreenState
    extends ConsumerState<_SubscriptionCreateScreen> {
  String? _clientId;
  String? _clientName;
  DateTime _startDate = DateTime.now();
  String _status = 'active';
  final _lines = <_LineDraft>[];
  bool _submitting = false;
  String? _error;

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked == null) return;
    setState(() {
      _clientId = picked.id;
      _clientName = picked.name;
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _addLine() async {
    final draft = await showCrmSheet<_LineDraft>(
      context: context,
      builder: (_) => const _SubscriptionLineSheet(),
    );
    if (draft != null) setState(() => _lines.add(draft));
  }

  Future<void> _editLine(int index) async {
    final draft = await showCrmSheet<_LineDraft>(
      context: context,
      builder: (_) => _SubscriptionLineSheet(draft: _lines[index]),
    );
    if (draft != null) setState(() => _lines[index] = draft);
  }

  void _removeLine(int index) => setState(() => _lines.removeAt(index));

  String? get _blocker {
    if (_clientId == null) return 'Choose the client this is for.';
    if (_lines.isEmpty) return 'Add at least one product.';
    return null;
  }

  Future<void> _submit() async {
    final blocker = _blocker;
    if (blocker != null) {
      setState(() => _error = blocker);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(billingCatalogServiceProvider)
          .createSubscriptionsBulk(
            clientId: _clientId!,
            startDate: _startDate,
            status: _status,
            items: [for (final line in _lines) line.input],
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Billing', title: 'New subscription'),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          CrmPickerField(
            label: 'Client',
            value: _clientName ?? 'Choose a client',
            placeholder: _clientName == null,
            icon: Icons.person_outline,
            onTap: _submitting ? null : _pickClient,
          ),
          const SizedBox(height: Spacing.md),
          CrmPickerField(
            label: 'Start date',
            value: Formatting.date(_startDate),
            onTap: _submitting ? null : _pickStartDate,
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Status',
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'pending', label: Text('Pending')),
              ],
              selected: {_status},
              onSelectionChanged: _submitting
                  ? null
                  : (choice) => setState(() => _status = choice.first),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Products'),
          const SizedBox(height: Spacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, line) in _lines.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    onTap: _submitting ? null : () => _editLine(i),
                    onLongPress: _submitting ? null : () => _removeLine(i),
                    title: Text(
                      line.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: CrmMetaLine(
                        [
                          if (line.input.label != null) line.input.label!,
                          '×${line.input.quantity}',
                          if (line.input.discountType != null)
                            '${line.input.discountType} discount',
                        ].join(' · '),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _submitting ? null : () => _removeLine(i),
                    ),
                  ),
                ],
                if (_lines.isNotEmpty) const Divider(height: 1),
                ListTile(
                  onTap: _submitting ? null : _addLine,
                  leading: Icon(Icons.add_rounded, color: scheme.primary),
                  title: Text(
                    _lines.isEmpty ? 'Add the first product' : 'Add a product',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: PrimaryButton(
            label: _submitting ? 'Saving…' : 'Create subscription',
            busy: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ),
      ),
    );
  }
}

class _SubscriptionLineSheet extends StatefulWidget {
  const _SubscriptionLineSheet({this.draft});

  final _LineDraft? draft;

  @override
  State<_SubscriptionLineSheet> createState() => _SubscriptionLineSheetState();
}

class _SubscriptionLineSheetState extends State<_SubscriptionLineSheet> {
  String? _productId;
  String _productName = '';
  late final _label = TextEditingController(text: widget.draft?.input.label ?? '');
  late final _quantity = TextEditingController(
    text: '${widget.draft?.input.quantity ?? 1}',
  );
  late final _discountValue = TextEditingController(
    text: _plain(widget.draft?.input.discountValue),
  );
  String? _discountType;
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _productId = draft.input.productServiceId;
      _productName = draft.productName;
      _discountType = draft.input.discountType;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _quantity.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  Future<void> _pickProduct() async {
    final product = await ProductPickerSheet.show(context);
    if (product == null) return;
    setState(() {
      _productId = product.id;
      _productName = product.name;
    });
  }

  void _save() {
    final productId = _productId;
    if (productId == null || _productName.isEmpty) {
      setState(() => _error = 'Choose a product.');
      return;
    }
    final quantity = _int(_quantity) ?? 1;
    if (quantity < 1) {
      setState(() => _error = 'Quantity must be at least 1.');
      return;
    }
    Navigator.of(context).pop(
      _LineDraft(
        productName: _productName,
        input: SubscriptionLineInput(
          productServiceId: productId,
          label: _label.text.trim().isEmpty ? null : _label.text.trim(),
          quantity: quantity,
          discountType: _discountType,
          discountValue: _discountType == null ? null : _num(_discountValue),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: 'New subscription',
      title: widget.draft == null ? 'Add a product' : 'Change this product',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmPickerField(
          label: 'Product',
          value: _productName.isEmpty ? 'Choose a product' : _productName,
          placeholder: _productName.isEmpty,
          icon: Icons.inventory_2_outlined,
          onTap: _pickProduct,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Label',
          child: TextField(
            controller: _label,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Quantity',
          child: TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Discount',
                child: DropdownButtonFormField<String?>(
                  initialValue: _discountType,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('None')),
                    DropdownMenuItem(value: 'percent', child: Text('Percent')),
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
                  ],
                  onChanged: (v) => setState(() => _discountType = v),
                ),
              ),
            ),
            if (_discountType != null) ...[
              const SizedBox(width: Spacing.md),
              Expanded(
                child: CrmField(
                  label: _discountType == 'percent' ? 'Percent' : 'Amount',
                  child: TextField(
                    controller: _discountValue,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: widget.draft == null ? 'Add product' : 'Save',
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Amends the one product this subscription already runs — the client is
/// fixed once it exists, per the update endpoint's own contract.
class _SubscriptionEditForm extends ConsumerStatefulWidget {
  const _SubscriptionEditForm({required this.subscription});

  final StaffSubscription subscription;

  @override
  ConsumerState<_SubscriptionEditForm> createState() =>
      _SubscriptionEditFormState();
}

class _SubscriptionEditFormState extends ConsumerState<_SubscriptionEditForm> {
  late String? _productId = widget.subscription.productServiceId;
  late String _productName = widget.subscription.productName ?? 'Choose a product';
  late final _label = TextEditingController(
    text: widget.subscription.label ?? '',
  );
  late final _quantity = TextEditingController(
    text: '${widget.subscription.quantity}',
  );
  late DateTime _startDate = widget.subscription.startDate ?? DateTime.now();
  late String _status = widget.subscription.status;

  bool _submitting = false;
  String? _error;

  static const _statuses = ['pending', 'active', 'suspended', 'cancelled'];

  @override
  void dispose() {
    _label.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _pickProduct() async {
    final product = await ProductPickerSheet.show(context);
    if (product == null) return;
    setState(() {
      _productId = product.id;
      _productName = product.name;
    });
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    final productId = _productId;
    if (productId == null) {
      setState(() => _error = 'Choose a product.');
      return;
    }
    final quantity = _int(_quantity) ?? 1;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(billingCatalogServiceProvider)
          .updateSubscription(
            widget.subscription.id,
            productServiceId: productId,
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
            quantity: quantity,
            startDate: _startDate,
            status: _status,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = _statuses.contains(_status)
        ? _statuses
        : [_status, ..._statuses];

    return CrmSheet(
      eyebrow: 'Subscriptions',
      title: 'Edit subscription',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmDetailRow('Client', widget.subscription.clientName ?? '—'),
        const SizedBox(height: Spacing.sm),
        CrmPickerField(
          label: 'Product',
          value: _productName,
          placeholder: _productId == null,
          icon: Icons.inventory_2_outlined,
          onTap: _submitting ? null : _pickProduct,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Label',
          child: TextField(
            controller: _label,
            enabled: !_submitting,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CrmField(
                label: 'Quantity',
                child: TextField(
                  controller: _quantity,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                ),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: CrmField(
                label: 'Status',
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: [
                    for (final s in statuses)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _status = v ?? _status),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Start date',
          value: Formatting.date(_startDate),
          onTap: _submitting ? null : _pickStartDate,
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save changes',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
