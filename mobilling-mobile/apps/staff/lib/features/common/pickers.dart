import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../admin/admin_providers.dart';
import '../billing_catalog/billing_catalog_providers.dart';

/// Searchable bottom-sheet pickers over the three lists staff choose from
/// most: clients, colleagues and catalog products.
///
/// Each is a thin shell around one search endpoint. They return the chosen
/// row through `Navigator.pop`, so call sites read as
/// `final client = await ClientPickerSheet.show(context);`.

class ClientPickerSheet extends ConsumerStatefulWidget {
  const ClientPickerSheet({super.key});

  static Future<StaffClient?> show(BuildContext context) =>
      showModalBottomSheet<StaffClient>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const ClientPickerSheet(),
      );

  @override
  ConsumerState<ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<ClientPickerSheet> {
  final _search = TextEditingController();
  List<StaffClient> _results = const [];
  bool _loading = false;

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
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(staffServiceProvider)
          .clients(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            perPage: 50,
          );
      if (mounted) setState(() => _results = page.items);
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PickerShell(
    eyebrow: 'Clients',
    title: 'Choose a client',
    hint: 'Search by name, phone or email',
    controller: _search,
    loading: _loading,
    onSearch: _load,
    itemCount: _results.length,
    itemBuilder: (context, index) {
      final client = _results[index];
      final contact = client.phone ?? client.email;
      return ListTile(
        title: Text(client.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: contact == null ? null : _Meta(contact),
        onTap: () => Navigator.of(context).pop(client),
      );
    },
  );
}

/// A colleague — for salaries, loans, leave allocations. Needs
/// `settings.users` on the API; callers only show it to users who hold it.
class StaffUserPickerSheet extends ConsumerStatefulWidget {
  const StaffUserPickerSheet({super.key});

  static Future<StaffUser?> show(BuildContext context) =>
      showModalBottomSheet<StaffUser>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const StaffUserPickerSheet(),
      );

  @override
  ConsumerState<StaffUserPickerSheet> createState() =>
      _StaffUserPickerSheetState();
}

class _StaffUserPickerSheetState extends ConsumerState<StaffUserPickerSheet> {
  final _search = TextEditingController();
  List<StaffUser> _results = const [];
  bool _loading = false;

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
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(adminServiceProvider)
          .users(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            perPage: 100,
          );
      if (mounted) {
        setState(() => _results = page.items.where((u) => u.isActive).toList());
      }
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PickerShell(
    eyebrow: 'Team',
    title: 'Choose a colleague',
    hint: 'Search by name',
    controller: _search,
    loading: _loading,
    onSearch: _load,
    itemCount: _results.length,
    itemBuilder: (context, index) {
      final user = _results[index];
      return ListTile(
        title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: user.roleName == null
            ? null
            : _Meta(user.roleName!, upperCase: true),
        onTap: () => Navigator.of(context).pop(user),
      );
    },
  );
}

/// A catalog product — for importing a discovered hosting account onto the
/// right plan. Active products only.
class ProductPickerSheet extends ConsumerStatefulWidget {
  const ProductPickerSheet({super.key});

  static Future<ProductService?> show(BuildContext context) =>
      showModalBottomSheet<ProductService>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const ProductPickerSheet(),
      );

  @override
  ConsumerState<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends ConsumerState<ProductPickerSheet> {
  final _search = TextEditingController();
  List<ProductService> _results = const [];
  bool _loading = false;

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
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(billingCatalogServiceProvider)
          .products(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            activeOnly: true,
            perPage: 50,
          );
      if (mounted) setState(() => _results = page.items);
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PickerShell(
    eyebrow: 'Catalog',
    title: 'Choose a product',
    hint: 'Search by name or code',
    controller: _search,
    loading: _loading,
    onSearch: _load,
    itemCount: _results.length,
    itemBuilder: (context, index) {
      final product = _results[index];
      return ListTile(
        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: product.billingCycle == null
            ? null
            : _Meta(
                product.billingCycle!.replaceAll('_', ' '),
                upperCase: true,
              ),
        // The price was a string in the subtitle; as a trailing [Money] it
        // lines up into the one column every other list in the app has.
        trailing: Money(product.price),
        onTap: () => Navigator.of(context).pop(product),
      );
    },
  );
}

/// The search-box-over-list layout the three pickers share: an eyebrow and
/// display-face title naming what is being chosen, the themed field, and
/// the results as one card of hairline-divided rows.
class _PickerShell extends StatelessWidget {
  const _PickerShell({
    required this.eyebrow,
    required this.title,
    required this.hint,
    required this.controller,
    required this.loading,
    required this.onSearch,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String eyebrow;
  final String title;
  final String hint;
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(title, style: Type.display(22, color: scheme.onSurface)),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: onSearch,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (itemCount == 0)
            const StateMessage(
              icon: Icons.search_off_outlined,
              title: 'No matches',
              message: 'Try a different spelling, or fewer words.',
            )
          else
            Flexible(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: itemCount,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: itemBuilder,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A picker row's metadata line — a phone, an email, a role, a billing
/// cycle — in the mono face. Identifiers keep their case; labels that name
/// something are upper-cased like every other eyebrow.
class _Meta extends StatelessWidget {
  const _Meta(this.text, {this.upperCase = false});

  final String text;
  final bool upperCase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      upperCase ? text.toUpperCase() : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
