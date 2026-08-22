import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView, CrmDetailRow;
import 'ops_providers.dart';

/// Cross-check WHM against what MoBilling bills: every cPanel account on
/// every server, flagged when no client here is linked to it, with a
/// one-step import that creates the missing subscription.
///
/// Accounts created straight on the server (or missed in the WHMCS import)
/// are otherwise hosted for free and invisible to collections.
class DiscoverHostingScreen extends ConsumerStatefulWidget {
  const DiscoverHostingScreen({super.key});

  @override
  ConsumerState<DiscoverHostingScreen> createState() =>
      _DiscoverHostingScreenState();
}

class _DiscoverHostingScreenState extends ConsumerState<DiscoverHostingScreen> {
  final _search = TextEditingController();

  /// null = all, false = not imported, true = imported. Default to the
  /// accounts that need attention.
  bool? _imported = false;
  String? _serverId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryProvider(_imported));
    final theme = Theme.of(context);
    final status = context.statusColors;
    final canImport = ref.watch(sessionControllerProvider).session?.can(
            OpsPermissions.hostingCreate) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Discover cPanel accounts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Filter by username, domain or client',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: SegmentedButton<bool?>(
              segments: const [
                ButtonSegment(value: false, label: Text('Unlinked')),
                ButtonSegment(value: true, label: Text('Imported')),
                ButtonSegment(value: null, label: Text('All')),
              ],
              selected: {_imported},
              onSelectionChanged: (s) => setState(() => _imported = s.first),
              showSelectedIcon: false,
              style:
                  const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          Expanded(
            child: CrmAsyncView(
              value: discovery,
              errorTitle: 'Could not reach WHM',
              onRetry: () => ref.invalidate(discoveryProvider(_imported)),
              builder: (result) {
                // Servers come from the rows themselves: listing /servers
                // needs hosting.settings, which a hosting-read user may lack.
                final servers = <String, String>{
                  for (final a in result.accounts) a.serverId: a.serverName,
                };
                final needle = _search.text.trim().toLowerCase();
                final rows = result.accounts.where((a) {
                  if (_serverId != null && a.serverId != _serverId) {
                    return false;
                  }
                  if (needle.isEmpty) return true;
                  return a.cpanelUsername.toLowerCase().contains(needle) ||
                      (a.domain?.toLowerCase().contains(needle) ?? false) ||
                      (a.clientName?.toLowerCase().contains(needle) ?? false);
                }).toList();

                return RefreshIndicator(
                  onRefresh: () =>
                      ref.refresh(discoveryProvider(_imported).future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.md, 0, Spacing.md, Spacing.xl),
                    children: [
                      for (final error in result.errors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.sm),
                          child: ErrorBanner(message: error),
                        ),
                      if (servers.length > 1) ...[
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              FilterChip(
                                label: const Text('All servers'),
                                selected: _serverId == null,
                                showCheckmark: false,
                                onSelected: (_) =>
                                    setState(() => _serverId = null),
                              ),
                              for (final entry in servers.entries) ...[
                                const SizedBox(width: Spacing.sm),
                                FilterChip(
                                  label: Text(entry.value),
                                  selected: _serverId == entry.key,
                                  showCheckmark: false,
                                  onSelected: (_) =>
                                      setState(() => _serverId = entry.key),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                      ],
                      Row(
                        children: [
                          Text('${rows.length} account${rows.length == 1 ? '' : 's'}',
                              style: theme.textTheme.bodySmall),
                          const Spacer(),
                          if (_imported != true)
                            Text(
                              '${result.unimportedCount} not imported',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: result.unimportedCount > 0
                                    ? status.attention
                                    : status.settled,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      if (rows.isEmpty)
                        SizedBox(
                          height: 240,
                          child: StateMessage(
                            icon: Icons.travel_explore_outlined,
                            title: _imported == false
                                ? 'Everything on the server is billed'
                                : 'No accounts match',
                          ),
                        )
                      else
                        for (final account in rows) ...[
                          _DiscoveredCard(
                            account: account,
                            canImport: canImport,
                            onImport: () => _import(context, account),
                          ),
                          const SizedBox(height: Spacing.sm),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, DiscoveredAccount account) async {
    final imported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ImportSheet(account: account),
    );
    if (imported ?? false) ref.invalidate(discoveryProvider);
  }
}

class _DiscoveredCard extends StatelessWidget {
  const _DiscoveredCard({
    required this.account,
    required this.canImport,
    required this.onImport,
  });

  final DiscoveredAccount account;
  final bool canImport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(account.domain ?? account.cpanelUsername,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (account.suspended) ...[
                  const StatusChip('suspended', dense: true),
                  const SizedBox(width: Spacing.xs),
                ],
                StatusChip(account.imported ? 'imported' : 'not_imported',
                    dense: true),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                account.cpanelUsername,
                account.serverName,
                if (account.plan != null) account.plan!,
                if (account.diskUsed != null)
                  '${account.diskUsed}${account.diskLimit == null ? '' : ' / ${account.diskLimit}'}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (account.imported && account.clientName != null) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.link, size: 14, color: status.settled),
                  const SizedBox(width: Spacing.xs),
                  Text(account.clientName!, style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            if (!account.imported && canImport) ...[
              const SizedBox(height: Spacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Import'),
                  onPressed: onImport,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({required this.account});

  final DiscoveredAccount account;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  late final _domain = TextEditingController(text: widget.account.domain ?? '');
  StaffClient? _client;
  ProductService? _product;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_client == null || _product == null || _domain.text.trim().isEmpty) {
      setState(() => _error = 'Choose the client and the hosting product.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final message = await ref.read(opsServiceProvider).importAccount(
            serverId: widget.account.serverId,
            cpanelUsername: widget.account.cpanelUsername,
            domain: _domain.text.trim(),
            clientId: _client!.id,
            productServiceId: _product!.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message ?? 'Account imported.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = widget.account;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Import ${account.cpanelUsername}',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          CrmDetailRow('Server', account.serverName),
          if (account.plan != null) CrmDetailRow('WHM package', account.plan!),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          TextField(
            controller: _domain,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Domain'),
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_outline, size: 18),
            label: Text(_client?.name ?? 'Choose client'),
            onPressed: () async {
              final picked = await ClientPickerSheet.show(context);
              if (picked != null) setState(() => _client = picked);
            },
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(_product?.name ?? 'Choose hosting product'),
            onPressed: () async {
              final picked = await ProductPickerSheet.show(context);
              if (picked != null) setState(() => _product = picked);
            },
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Creates an active subscription on this product for the client '
            'and links the existing cPanel account to it. Nothing is '
            'changed on the server.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _saving ? null : _import,
            child: Text(_saving ? 'Importing…' : 'Import and link'),
          ),
        ],
      ),
    );
  }
}
