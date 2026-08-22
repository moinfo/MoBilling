import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'support_admin_providers.dart';

/// Domains across every client, with the registry actions staff need on the
/// move: auto-renew, nameservers, and the EPP transfer code.
class StaffDomainsScreen extends ConsumerStatefulWidget {
  const StaffDomainsScreen({super.key});

  @override
  ConsumerState<StaffDomainsScreen> createState() =>
      _StaffDomainsScreenState();
}

class _StaffDomainsScreenState extends ConsumerState<StaffDomainsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;
  bool _expiringOnly = false;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('expired', 'Expired'),
    ('cancelled', 'Cancelled'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400),
        () => _listKey.currentState?.reload());
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(domainStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Domains')),
      body: Column(
        children: [
          stats.maybeWhen(
            data: (s) => Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.sm, Spacing.md, 0),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(label: 'Active', value: '${s.active}'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Expiring',
                      value: '${s.expiringSoon}',
                      emphasis: s.expiringSoon > 0
                          ? context.statusColors.attention
                          : null,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Expired',
                      value: '${s.expired}',
                      emphasis: s.expired > 0
                          ? context.statusColors.overdue
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search domain name',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              children: [
                for (final (value, label) in _filters) ...[
                  FilterChip(
                    label: Text(label),
                    selected: _status == value && !_expiringOnly,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _status = value;
                        _expiringOnly = false;
                      });
                      _listKey.currentState?.reload();
                    },
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
                // Server-side 45-day window, sorted by expiry — the view staff
                // actually work from.
                FilterChip(
                  label: const Text('Expiring soon'),
                  selected: _expiringOnly,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      _expiringOnly = !_expiringOnly;
                      if (_expiringOnly) _status = null;
                    });
                    _listKey.currentState?.reload();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) => ref.read(supportAdminServiceProvider).domains(
                    status: _status,
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    expiring: _expiringOnly ? true : null,
                    page: page,
                  ),
              itemBuilder: (context, domain) => _DomainCard(
                domain: domain,
                onChanged: () {
                  _listKey.currentState?.reload();
                  ref.invalidate(domainStatsProvider);
                },
              ),
              emptyIcon: Icons.public_outlined,
              emptyTitle: 'No domains found',
            ),
          ),
        ],
      ),
    );
  }
}

class _DomainCard extends ConsumerWidget {
  const _DomainCard({required this.domain, required this.onChanged});

  final StaffDomain domain;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        title: Text(domain.name),
        subtitle: Text(
          [
            if (domain.clientName != null) domain.clientName!,
            if (domain.expiresAt != null)
              'expires ${Formatting.date(domain.expiresAt)}',
            if (domain.autoRenew) 'auto-renew',
            if (domain.unmanaged) 'unmanaged',
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: domain.expiringSoon
                ? context.statusColors.attention
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(domain.status, dense: true),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () async {
          final changed = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
            builder: (_) => _DomainActionsSheet(domain: domain),
          );
          if (changed == true) onChanged();
        },
      ),
    );
  }
}

class _DomainActionsSheet extends ConsumerStatefulWidget {
  const _DomainActionsSheet({required this.domain});

  final StaffDomain domain;

  @override
  ConsumerState<_DomainActionsSheet> createState() =>
      _DomainActionsSheetState();
}

class _DomainActionsSheetState extends ConsumerState<_DomainActionsSheet> {
  bool _busy = false;
  bool _changed = false;

  StaffDomain get domain => widget.domain;

  Future<void> _run(Future<void> Function() action,
      {String? successMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      _changed = true;
      if (successMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAuthInfo() => _run(() async {
        final code = await ref
            .read(supportAdminServiceProvider)
            .domainAuthInfo(domain.id);
        if (!mounted || code.isEmpty) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Transfer (EPP) code'),
            content: SelectableText(code,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 18, letterSpacing: 1)),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Copy & close'),
              ),
            ],
          ),
        );
      });

  Future<void> _editNameservers() async {
    // 422 for domains managed at an external registrar — show it rather
    // than let the exception escape the sheet.
    final StaffNameservers current;
    try {
      current = await ref
          .read(supportAdminServiceProvider)
          .domainNameservers(domain.id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;

    if (!current.editable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nameservers cannot be edited for this domain.')));
      return;
    }

    final controllers = [
      for (var i = 0; i < 4; i++)
        TextEditingController(
            text: i < current.nameservers.length
                ? current.nameservers[i]
                : ''),
    ];

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nameservers'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: TextField(
                    controller: controllers[i],
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'NS${i + 1}${i > 1 ? ' (optional)' : ''}',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (save != true) return;

    final nameservers = controllers
        .map((c) => c.text.trim().toLowerCase())
        .where((v) => v.isNotEmpty)
        .toList();

    await _run(
      () => ref
          .read(supportAdminServiceProvider)
          .updateDomainNameservers(domain.id, nameservers),
      successMessage: 'Nameservers updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(sessionControllerProvider).session;
    final canRenew = auth?.can(SupportAdminPermissions.domainsRenew) ?? false;
    final canDns =
        auth?.can(SupportAdminPermissions.domainsManageDns) ?? false;
    final canTransfer =
        auth?.can(SupportAdminPermissions.domainsTransfer) ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(domain.name,
                            style: theme.textTheme.titleMedium),
                      ),
                      StatusChip(domain.status, dense: true),
                    ],
                  ),
                  Text(
                    [
                      if (domain.clientName != null) domain.clientName!,
                      if (domain.registrarName != null) domain.registrarName!,
                      if (domain.expiresAt != null)
                        'expires ${Formatting.date(domain.expiresAt)}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (domain.unmanaged)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Text(
                        'Managed manually — registry actions unavailable.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.statusColors.attention),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            SwitchListTile(
              secondary: const Icon(Icons.event_repeat_outlined),
              title: const Text('Auto-renew'),
              value: domain.autoRenew,
              onChanged: (_busy || domain.unmanaged || !canRenew)
                  ? null
                  : (enabled) => _run(
                        () => ref
                            .read(supportAdminServiceProvider)
                            .setDomainAutoRenew(domain.id, enabled),
                        successMessage: enabled
                            ? 'Auto-renew on.'
                            : 'Auto-renew off.',
                      ),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Nameservers'),
              enabled: !_busy && !domain.unmanaged && canDns,
              onTap: _editNameservers,
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Transfer (EPP) code'),
              enabled: !_busy && !domain.unmanaged && canTransfer,
              onTap: _showAuthInfo,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
