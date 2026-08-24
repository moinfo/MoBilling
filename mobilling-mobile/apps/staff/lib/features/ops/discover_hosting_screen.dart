import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/pickers.dart';
import '../crm/crm_ui.dart' show CrmAsyncView;
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
    final status = context.statusColors;
    final canImport =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(OpsPermissions.hostingCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Discover accounts',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Filter by username, domain or client',
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              0,
            ),
            child: SegmentedButton<bool?>(
              segments: const [
                ButtonSegment(value: false, label: Text('Unlinked')),
                ButtonSegment(value: true, label: Text('Imported')),
                ButtonSegment(value: null, label: Text('All')),
              ],
              selected: {_imported},
              onSelectionChanged: (s) => setState(() => _imported = s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
                      Spacing.md,
                      Spacing.sm,
                      Spacing.md,
                      Spacing.xl,
                    ),
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
                              ChoiceChip(
                                label: const Text('All servers'),
                                selected: _serverId == null,
                                showCheckmark: false,
                                onSelected: (_) =>
                                    setState(() => _serverId = null),
                              ),
                              for (final entry in servers.entries) ...[
                                const SizedBox(width: Spacing.sm),
                                ChoiceChip(
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
                      StatRail(
                        items: [
                          StatRailItem(
                            label: 'Accounts',
                            value: Formatting.integer(rows.length),
                          ),
                          if (_imported != true)
                            StatRailItem(
                              label: 'Not imported',
                              value: Formatting.integer(result.unimportedCount),
                              emphasis: result.unimportedCount > 0
                                  ? status.attention
                                  : status.settled,
                            ),
                        ],
                      ),
                      const SizedBox(height: Spacing.lg),
                      const SectionHeader('On the server'),
                      const SizedBox(height: Spacing.sm),
                      if (rows.isEmpty)
                        SizedBox(
                          height: 240,
                          child: StateMessage(
                            icon: Icons.travel_explore_outlined,
                            title: _imported == false
                                ? 'Everything on the server is billed'
                                : 'No accounts match',
                            message: _imported == false
                                ? 'Every cPanel account is linked to a client.'
                                : 'Try another name, or pick a different server.',
                          ),
                        )
                      else
                        Card(
                          child: Column(
                            children: [
                              for (final (i, account) in rows.indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                _DiscoveredRow(
                                  account: account,
                                  canImport: canImport,
                                  onImport: () => _import(context, account),
                                ),
                              ],
                            ],
                          ),
                        ),
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
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _ImportSheet(account: account),
    );
    if (imported ?? false) ref.invalidate(discoveryProvider);
  }
}

/// One cPanel account: the import state (and suspension) as chips, then the
/// username, server, package and disk as one mono line. Unlinked rows carry
/// the import action; linked ones name the client they bill to.
class _DiscoveredRow extends StatelessWidget {
  const _DiscoveredRow({
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
    final importable = !account.imported && canImport;

    return ListTile(
      onTap: importable ? onImport : null,
      title: Text(
        account.domain ?? account.cpanelUsername,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(
              account.imported ? 'imported' : 'not_imported',
              dense: true,
            ),
            if (account.suspended) ...[
              const SizedBox(width: Spacing.xs),
              const StatusChip('suspended', dense: true),
            ],
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                [
                  if (account.imported && account.clientName != null)
                    account.clientName!,
                  account.cpanelUsername,
                  account.serverName,
                  if (account.plan != null) account.plan!,
                  if (account.diskUsed != null)
                    '${account.diskUsed}${account.diskLimit == null ? '' : ' / ${account.diskLimit}'}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: importable
          ? TextButton(onPressed: onImport, child: const Text('Import'))
          : null,
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
      final message = await ref
          .read(opsServiceProvider)
          .importAccount(
            serverId: widget.account.serverId,
            cpanelUsername: widget.account.cpanelUsername,
            domain: _domain.text.trim(),
            clientId: _client!.id,
            productServiceId: _product!.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message ?? 'Account imported.')));
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
    final scheme = theme.colorScheme;
    final account = widget.account;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        sheetBottomInset(context) + Spacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The server and WHM package name the context; the username is
            // the subject.
            Text(
              [
                account.serverName,
                if (account.plan != null) account.plan!,
              ].join(' · ').toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Import ${account.cpanelUsername}',
              style: Type.display(22, color: scheme.onSurface),
            ),
            const SizedBox(height: Spacing.lg),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],
            Text('Domain', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _domain,
              enabled: !_saving,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'example.co.tz'),
            ),
            const SizedBox(height: Spacing.md),
            Text('Client', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_outline, size: 18),
              label: Text(
                _client?.name ?? 'Choose client',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await ClientPickerSheet.show(context);
                      if (picked != null) setState(() => _client = picked);
                    },
            ),
            const SizedBox(height: Spacing.md),
            Text('Hosting product', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text(
                _product?.name ?? 'Choose hosting product',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _saving
                  ? null
                  : () async {
                      final picked = await ProductPickerSheet.show(context);
                      if (picked != null) setState(() => _product = picked);
                    },
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Creates an active subscription on this product for the client '
              'and links the existing cPanel account to it. Nothing is '
              'changed on the server.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: _saving ? 'Importing…' : 'Import and link',
              busy: _saving,
              onPressed: _saving ? null : _import,
            ),
          ],
        ),
      ),
    );
  }
}
