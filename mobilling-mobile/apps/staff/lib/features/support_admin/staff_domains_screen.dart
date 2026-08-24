import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show FilterStrip;
import 'support_admin_providers.dart';

/// Domains across every client, with the registry actions staff need on the
/// move: auto-renew, nameservers, and the EPP transfer code.
class StaffDomainsScreen extends ConsumerStatefulWidget {
  const StaffDomainsScreen({super.key});

  @override
  ConsumerState<StaffDomainsScreen> createState() => _StaffDomainsScreenState();
}

class _StaffDomainsScreenState extends ConsumerState<StaffDomainsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;
  bool _expiringOnly = false;

  /// Pseudo-status for the "expiring soon" chip, which is a server-side
  /// 45-day window sorted by expiry — the view staff actually work from.
  static const _expiring = 'expiring';

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('expired', 'Expired'),
    ('cancelled', 'Cancelled'),
    (_expiring, 'Expiring soon'),
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

  void _select(String? value) {
    setState(() {
      _expiringOnly = value == _expiring;
      _status = _expiringOnly ? null : value;
    });
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(domainStatsProvider);
    final status = context.statusColors;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Domains',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search domain name',
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          stats.maybeWhen(
            data: (s) => Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                0,
              ),
              child: StatRail(
                items: [
                  StatRailItem(
                    label: 'Active',
                    value: Formatting.integer(s.active),
                  ),
                  StatRailItem(
                    label: 'Expiring',
                    value: Formatting.integer(s.expiringSoon),
                    emphasis: s.expiringSoon > 0 ? status.attention : null,
                  ),
                  StatRailItem(
                    label: 'Expired',
                    value: Formatting.integer(s.expired),
                    emphasis: s.expired > 0 ? status.overdue : null,
                  ),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          FilterStrip(
            options: _filters,
            selected: _expiringOnly ? _expiring : _status,
            onSelect: _select,
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              // One card, rows divided by hairlines — the paged list scrolls
              // inside it.
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: PagedListView(
                  key: _listKey,
                  padding: EdgeInsets.zero,
                  separated: false,
                  fetch: (page) => ref
                      .read(supportAdminServiceProvider)
                      .domains(
                        status: _status,
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                        expiring: _expiringOnly ? true : null,
                        page: page,
                      ),
                  itemBuilder: (context, domain) => _DomainRow(
                    domain: domain,
                    onChanged: () {
                      _listKey.currentState?.reload();
                      ref.invalidate(domainStatsProvider);
                    },
                  ),
                  emptyIcon: Icons.public_outlined,
                  emptyTitle: 'No domains found',
                  emptyMessage: 'Try another name, or clear the filter.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One domain: status chip and the client / expiry / renewal facts as a mono
/// line, with days-to-expiry as the aligned trailing figure — the
/// dashboard's expiring-domains row, for every domain.
class _DomainRow extends ConsumerWidget {
  const _DomainRow({required this.domain, required this.onChanged});

  final StaffDomain domain;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final daysLeft = Formatting.daysUntil(domain.expiresAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          onTap: () async {
            final changed = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
              builder: (_) => _DomainActionsSheet(domain: domain),
            );
            if (changed == true) onChanged();
          },
          title: Text(
            domain.name,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                StatusChip(domain.status, dense: true),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Text(
                    [
                      if (domain.clientName != null) domain.clientName!,
                      if (domain.expiresAt != null)
                        'expires ${Formatting.date(domain.expiresAt)}',
                      if (domain.autoRenew) 'auto-renew',
                      if (domain.unmanaged) 'unmanaged',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: daysLeft == null
              ? const Icon(Icons.chevron_right)
              : Text(
                  switch (daysLeft) {
                    final n when n < 0 => 'Expired',
                    0 => 'Today',
                    final n => '${n}d',
                  },
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: daysLeft <= 0
                        ? status.overdue
                        : domain.expiringSoon
                        ? status.attention
                        : scheme.onSurfaceVariant,
                  ),
                ),
        ),
        const Divider(height: 1),
      ],
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

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
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
        content: SelectableText(
          code,
          style: Type.mono(
            18,
            tracking: 0.06,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy and close'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;

    if (!current.editable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nameservers cannot be edited for this domain.'),
        ),
      );
      return;
    }

    final controllers = [
      for (var i = 0; i < 4; i++)
        TextEditingController(
          text: i < current.nameservers.length ? current.nameservers[i] : '',
        ),
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
                      hintText: 'ns${i + 1}.example.com',
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save nameservers'),
          ),
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
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final auth = ref.watch(sessionControllerProvider).session;
    final canRenew = auth?.can(SupportAdminPermissions.domainsRenew) ?? false;
    final canDns = auth?.can(SupportAdminPermissions.domainsManageDns) ?? false;
    final canTransfer =
        auth?.can(SupportAdminPermissions.domainsTransfer) ?? false;
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (domain.clientName != null) ...[
                    Text(domain.clientName!.toUpperCase(), style: meta),
                    const SizedBox(height: Spacing.xs),
                  ],
                  Text(
                    domain.name,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      StatusChip(domain.status, dense: true),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: Text(
                          [
                            if (domain.registrarName != null)
                              domain.registrarName!,
                            if (domain.expiresAt != null)
                              'expires ${Formatting.date(domain.expiresAt)}',
                          ].join(' · '),
                          style: meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (domain.unmanaged)
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.sm),
                      child: Text(
                        'Managed manually — registry actions unavailable.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: status.attention,
                        ),
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
