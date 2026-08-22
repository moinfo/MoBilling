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
      final page = await ref.read(staffServiceProvider).clients(
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
        hint: 'Search clients',
        controller: _search,
        loading: _loading,
        onSearch: _load,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final client = _results[index];
          return ListTile(
            dense: true,
            title: Text(client.name),
            subtitle: client.phone == null && client.email == null
                ? null
                : Text(client.phone ?? client.email!),
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
      final page = await ref.read(adminServiceProvider).users(
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
        hint: 'Search staff',
        controller: _search,
        loading: _loading,
        onSearch: _load,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final user = _results[index];
          return ListTile(
            dense: true,
            title: Text(user.name),
            subtitle: user.roleName == null ? null : Text(user.roleName!),
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
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => const ProductPickerSheet(),
      );

  @override
  ConsumerState<ProductPickerSheet> createState() =>
      _ProductPickerSheetState();
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
      final page = await ref.read(billingCatalogServiceProvider).products(
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
        hint: 'Search products',
        controller: _search,
        loading: _loading,
        onSearch: _load,
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final product = _results[index];
          return ListTile(
            dense: true,
            title: Text(product.name),
            subtitle: Text([
              Formatting.currency(product.price),
              if (product.billingCycle != null)
                product.billingCycle!.replaceAll('_', ' '),
            ].join(' / ')),
            onTap: () => Navigator.of(context).pop(product),
          );
        },
      );
}

/// The search-box-over-list layout the three pickers share.
class _PickerShell extends StatelessWidget {
  const _PickerShell({
    required this.hint,
    required this.controller,
    required this.loading,
    required this.onSearch,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String hint;
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: onSearch,
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: CircularProgressIndicator(),
            )
          else if (itemCount == 0)
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text('No matches.',
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: itemCount,
                itemBuilder: itemBuilder,
              ),
            ),
        ],
      ),
    );
  }
}
