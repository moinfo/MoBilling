import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart';
import '../crm/crm_ui.dart'
    show
        CrmDetailRow,
        CrmField,
        CrmPickerField,
        CrmSheet,
        FilterStrip,
        showCrmMessage,
        showCrmSheet;
import 'support_admin_providers.dart';

/// Domains across every client, with the registry actions staff need on the
/// move: renew, retry a failed action, auto-renew, nameservers, the EPP
/// transfer code and the registry log — plus the two registry-wide tools the
/// web keeps on this page, a .tz WHOIS lookup and the prepaid registrar
/// balance, behind masthead and header entry points rather than above the
/// list.
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

  /// '1' = registry-confirmed on our own registrar, '0' = everything else.
  String? _ours;

  /// Pseudo-statuses for the chips that are not `status` values at all: a
  /// server-side 45-day window sorted by expiry, and the sponsorship filter.
  static const _expiring = 'expiring';
  static const _oursChip = 'ours';
  static const _externalChip = 'external';

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('pending', 'Pending'),
    ('expired', 'Expired'),
    ('failed', 'Failed'),
    ('cancelled', 'Cancelled'),
    (_expiring, 'Expiring soon'),
    (_oursChip, 'Ours'),
    (_externalChip, 'External'),
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

  String? get _selectedChip {
    if (_expiringOnly) return _expiring;
    if (_ours == '1') return _oursChip;
    if (_ours == '0') return _externalChip;
    return _status;
  }

  void _select(String? value) {
    setState(() {
      _expiringOnly = value == _expiring;
      _ours = switch (value) {
        _oursChip => '1',
        _externalChip => '0',
        _ => null,
      };
      // The three pseudo-chips are not statuses — selecting one clears it.
      _status = (_expiringOnly || _ours != null) ? null : value;
    });
    _listKey.currentState?.reload();
  }

  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(domainStatsProvider);
  }

  /// The web's "Register / Transfer" button, which is really three actions.
  /// Ordering already has a screen of its own (Add order → Domain only), so
  /// this routes there and keeps only the bookkeeping form locally.
  Future<void> _showAddSheet() async {
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (context) => CrmSheet(
        eyebrow: 'Domains',
        title: 'Add a domain',
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: const Text('Register or transfer'),
                  subtitle: const Text(
                    'Checks the registry and invoices the client.',
                  ),
                  onTap: () => Navigator.pop(context, 'order'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.playlist_add_outlined),
                  title: const Text('Add existing domain'),
                  subtitle: const Text(
                    'Already registered somewhere — just track it.',
                  ),
                  onTap: () => Navigator.pop(context, 'existing'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice == 'order') {
      context.push('/orders');
      return;
    }

    final message = await showCrmSheet<String>(
      context: context,
      builder: (_) => const _AddExistingDomainSheet(),
    );
    if (!mounted || message == null) return;
    showCrmMessage(context, message);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(domainStatsProvider);
    final credit = ref.watch(registrarCreditProvider);
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.domainsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Domains',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkActionButton(
              icon: Icons.travel_explore_outlined,
              tooltip: 'WHOIS lookup',
              onPressed: () => showCrmSheet<void>(
                context: context,
                builder: (_) => const _WhoisSheet(),
              ),
            ),
            if (canCreate) ...[
              const SizedBox(width: Spacing.sm),
              InkActionButton(
                icon: Icons.add,
                tooltip: 'Register, transfer or add a domain',
                onPressed: _showAddSheet,
              ),
            ],
          ],
        ),
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search domain name',
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          stats.maybeWhen(data: _rails, orElse: () => const SizedBox.shrink()),
          credit.maybeWhen(
            data: _creditRow,
            orElse: () => const SizedBox.shrink(),
          ),
          FilterStrip(
            options: _filters,
            selected: _selectedChip,
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
                        ours: _ours,
                        page: page,
                      ),
                  itemBuilder: (context, domain) =>
                      _DomainRow(domain: domain, onChanged: _reload),
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

  /// The web's eight stat cards, as two rails. Each figure that maps to a
  /// filter selects that filter, which is what the cards do on the web.
  Widget _rails(StaffDomainStats s) {
    final status = context.statusColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      child: Column(
        children: [
          StatRail(
            items: [
              StatRailItem(
                label: 'Active',
                value: Formatting.integer(s.active),
                onTap: () => _select('active'),
              ),
              StatRailItem(
                label: 'Expiring',
                value: Formatting.integer(s.expiringSoon),
                emphasis: s.expiringSoon > 0 ? status.attention : null,
                onTap: () => _select(_expiring),
              ),
              StatRailItem(
                label: 'Expired',
                value: Formatting.integer(s.expired),
                emphasis: s.expired > 0 ? status.overdue : null,
                onTap: () => _select('expired'),
              ),
              StatRailItem(
                label: 'Pending',
                value: Formatting.integer(s.pending),
                onTap: () => _select('pending'),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          StatRail(
            items: [
              StatRailItem(
                label: 'Total',
                value: Formatting.integer(s.total),
                onTap: () => _select(null),
              ),
              // Sponsorship as the registry reports it, not as we billed it.
              StatRailItem(
                label: 'Ours',
                value: Formatting.integer(s.ours),
                onTap: () => _select(_oursChip),
              ),
              StatRailItem(
                label: 'External',
                value: Formatting.integer(s.external),
                onTap: () => _select(_externalChip),
              ),
              StatRailItem(
                label: 'Auto-renew',
                value: Formatting.integer(s.autoRenew),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Prepaid registrar credit — real money the registry draws on every
  /// register and renew. One row, because the detail belongs in the sheet;
  /// the low-balance warning is the part that has to be visible from here.
  Widget _creditRow(StaffRegistrarCredit credit) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final low = credit.low.isNotEmpty;
    // The registry answering with no zones is not the same as a zero
    // balance, and `total: 0` renders identically for both. Say which it is,
    // otherwise "TZS 0.00" reads as "you are out of credit" on a day the
    // registry simply told us nothing.
    final nothingReported = credit.ok && credit.zones.isEmpty;
    final subtitle = !credit.ok
        ? 'Registrar unreachable — balance unknown.'
        : nothingReported
        ? 'The registry reported no zones — balance unknown.'
        : low
        ? 'Low: ${credit.low.map((z) => '.$z').join(', ')} — renewals draw '
              'real prepaid credit.'
        : '${Formatting.integer(credit.fundedCount)} funded zones';

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      child: Card(
        child: ListTile(
          leading: Icon(
            low
                ? Icons.warning_amber_outlined
                : Icons.account_balance_wallet_outlined,
            color: low ? status.attention : scheme.onSurfaceVariant,
          ),
          title: Text('Registrar credit', style: theme.textTheme.titleSmall),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: low ? status.attention : scheme.onSurfaceVariant,
            ),
          ),
          trailing: (credit.ok && !nothingReported)
              ? Money(
                  credit.total,
                  scale: MoneyScale.row,
                  color: low ? status.attention : null,
                )
              : const Icon(Icons.chevron_right),
          onTap: () => showCrmSheet<void>(
            context: context,
            builder: (_) => const _RegistrarCreditSheet(),
          ),
        ),
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
          // The sheet reports each success as it happens rather than on
          // close, so a renew still refreshes the list when the sheet is
          // dismissed with a drag.
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
            builder: (_) =>
                _DomainActionsSheet(domain: domain, onChanged: onChanged),
          ),
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
  const _DomainActionsSheet({required this.domain, required this.onChanged});

  final StaffDomain domain;

  /// Called after every action the API accepted, so the list and the counters
  /// behind the sheet stay honest.
  final VoidCallback onChanged;

  @override
  ConsumerState<_DomainActionsSheet> createState() =>
      _DomainActionsSheetState();
}

class _DomainActionsSheetState extends ConsumerState<_DomainActionsSheet> {
  bool _busy = false;

  String get _id => widget.domain.id;

  /// Runs an action, shows the API's own message, and re-reads the domain and
  /// its log so the sheet reflects the new state without being closed.
  Future<void> _run(
    Future<String?> Function() action, {
    String? fallbackMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action();
      widget.onChanged();
      // The sheet can be dragged away mid-flight, taking this ref with it.
      if (mounted) {
        ref.invalidate(staffDomainProvider(_id));
        ref.invalidate(domainLogsProvider(_id));
      }
      final text = message ?? fallbackMessage;
      if (text != null) {
        messenger.showSnackBar(SnackBar(content: Text(text)));
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
        .domainAuthInfo(_id);
    if (!mounted || code.isEmpty) return null;
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
    return null;
  });

  /// Renewal is billed, not immediate: the invoice goes out now and the EPP
  /// renew — which spends real prepaid registrar credit — runs on payment.
  Future<void> _renew(StaffDomain domain) async {
    var years = 1;
    final theme = Theme.of(context);
    final confirmed = await showCrmSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => CrmSheet(
          eyebrow: domain.clientName ?? 'Domains',
          title: 'Renew ${domain.name}',
          children: [
            const FieldLabel('Years'),
            const SizedBox(height: Spacing.sm),
            DropdownButtonFormField<int>(
              initialValue: years,
              items: [
                for (var y = 1; y <= 10; y++)
                  DropdownMenuItem(
                    value: y,
                    child: Text('$y year${y > 1 ? 's' : ''}'),
                  ),
              ],
              onChanged: (value) => setSheetState(() => years = value ?? 1),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Creates a renewal invoice for the client. The registry renewal '
              'runs once it is paid, and draws real prepaid registrar credit.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: 'Create renewal invoice',
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => ref.read(supportAdminServiceProvider).renewDomain(_id, years),
      fallbackMessage: 'Renewal invoice created.',
    );
  }

  Future<void> _editNameservers() async {
    // 422 for domains managed at an external registrar — show it rather
    // than let the exception escape the sheet.
    final StaffNameservers current;
    try {
      current = await ref
          .read(supportAdminServiceProvider)
          .domainNameservers(_id);
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

    await _run(() async {
      await ref
          .read(supportAdminServiceProvider)
          .updateDomainNameservers(_id, nameservers);
      return null;
    }, fallbackMessage: 'Nameservers updated.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final auth = ref.watch(sessionControllerProvider).session;
    final canRenew = auth?.can(SupportAdminPermissions.domainsRenew) ?? false;
    final canCreate = auth?.can(SupportAdminPermissions.domainsCreate) ?? false;
    final canDns = auth?.can(SupportAdminPermissions.domainsManageDns) ?? false;
    final canTransfer =
        auth?.can(SupportAdminPermissions.domainsTransfer) ?? false;
    // The show route is fresher than the list row it was opened from, and is
    // what makes a retry visibly change the status here.
    final domain =
        ref.watch(staffDomainProvider(_id)).valueOrNull ?? widget.domain;
    final logs = ref.watch(domainLogsProvider(_id));
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: SingleChildScrollView(
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
                              if (domain.sponsoringRegistrar != null)
                                domain.sponsoringRegistrar!
                              else if (domain.registrarName != null)
                                domain.registrarName!,
                              if (domain.expiresAt != null)
                                'expires ${Formatting.date(domain.expiresAt)}',
                              if (domain.subscriptionLabel != null)
                                domain.subscriptionLabel!,
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
                subtitle: const Text(
                  "Renewals are invoiced and paid from the client's wallet.",
                ),
                value: domain.autoRenew,
                onChanged:
                    (_busy ||
                        domain.unmanaged ||
                        !canRenew ||
                        (!domain.isLive && !domain.autoRenew))
                    ? null
                    : (enabled) => _run(
                        () async {
                          await ref
                              .read(supportAdminServiceProvider)
                              .setDomainAutoRenew(_id, enabled);
                          return null;
                        },
                        fallbackMessage: enabled
                            ? 'Auto-renew on.'
                            : 'Auto-renew off.',
                      ),
              ),
              if (canRenew && domain.isLive)
                ListTile(
                  leading: const Icon(Icons.autorenew),
                  title: const Text('Renew'),
                  subtitle: const Text(
                    'Creates the renewal invoice; the registry renews on '
                    'payment.',
                  ),
                  enabled: !_busy,
                  onTap: () => _renew(domain),
                ),
              if (canCreate && domain.canRetry)
                ListTile(
                  leading: Icon(Icons.replay, color: status.attention),
                  title: Text(
                    'Retry ${domain.pendingAction}',
                    style: TextStyle(color: status.attention),
                  ),
                  subtitle: const Text('Already paid — no new invoice.'),
                  enabled: !_busy,
                  onTap: () => _run(
                    () =>
                        ref.read(supportAdminServiceProvider).retryDomain(_id),
                    fallbackMessage: 'Retrying…',
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
              // The registry log — the fastest way to see why a register or a
              // renew failed, and the audit trail for a revealed EPP code.
              logs.maybeWhen(
                data: (entries) => entries.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.lg,
                          Spacing.md,
                          Spacing.lg,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader('Registry log'),
                            const SizedBox(height: Spacing.sm),
                            for (final entry in entries.take(5))
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Spacing.xs,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          entry.success
                                              ? Icons.check_circle_outline
                                              : Icons.error_outline,
                                          size: 14,
                                          color: entry.success
                                              ? status.settled
                                              : status.overdue,
                                        ),
                                        const SizedBox(width: Spacing.sm),
                                        Expanded(
                                          child: Text(
                                            entry.label,
                                            style: theme.textTheme.bodySmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: Spacing.sm),
                                        Text(
                                          Formatting.date(entry.createdAt),
                                          style: meta,
                                        ),
                                      ],
                                    ),
                                    if (entry.error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 22,
                                          top: 2,
                                        ),
                                        child: Text(
                                          entry.error!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(color: status.overdue),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live .tz WHOIS, straight from the TZNIC registry (port 43) — the web's
/// "Domain lookup" panel. Answers "who holds this name and when does it
/// expire" for names we do not bill.
class _WhoisSheet extends ConsumerStatefulWidget {
  const _WhoisSheet();

  @override
  ConsumerState<_WhoisSheet> createState() => _WhoisSheetState();
}

class _WhoisSheetState extends ConsumerState<_WhoisSheet> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  StaffWhoisResult? _result;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final name = _name.text.trim().toLowerCase();
    if (name.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(supportAdminServiceProvider)
          .domainWhois(name);
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final canCreate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.domainsCreate) ??
        false;
    final result = _result;

    return CrmSheet(
      eyebrow: 'Registry',
      title: 'WHOIS lookup',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Domain name',
          child: TextField(
            controller: _name,
            autocorrect: false,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lookup(),
            decoration: const InputDecoration(hintText: 'example.co.tz'),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Live from the TZNIC registry (whois.tznic.or.tz). .tz names only.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        PrimaryButton(
          label: 'Look up',
          icon: Icons.search,
          busy: _busy,
          onPressed: _lookup,
        ),
        if (result != null) ...[
          const SizedBox(height: Spacing.lg),
          if (!result.found)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: Radii.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result.domain} is available',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: status.settled,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'The registry has no record of it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (canCreate) ...[
                    const SizedBox(height: Spacing.sm),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/orders');
                      },
                      child: const Text('Register it'),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            SectionHeader(result.domain),
            const SizedBox(height: Spacing.sm),
            if (result.registrar != null)
              CrmDetailRow(
                'Registrar',
                result.isOurs
                    ? '${result.registrar} · ours'
                    : result.registrar!,
              ),
            if (result.registrant != null)
              CrmDetailRow('Registrant', result.registrant!),
            if (result.registered != null)
              CrmDetailRow('Registered', result.registered!),
            if (result.expire != null) CrmDetailRow('Expires', result.expire!),
            if (result.changed != null)
              CrmDetailRow('Last changed', result.changed!),
            if (result.statuses.isNotEmpty)
              CrmDetailRow('Status', result.statuses.join(', ')),
            if (result.nsset != null)
              CrmDetailRow('Nameserver set', result.nsset!),
            if (result.nameservers.isNotEmpty)
              CrmDetailRow('Nameservers', result.nameservers.join('\n')),
            if (result.raw != null)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Raw WHOIS', style: theme.textTheme.titleSmall),
                  children: [
                    SelectableText(
                      result.raw!,
                      style: Type.mono(
                        11,
                        tracking: 0,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ],
    );
  }
}

/// Prepaid TZNIC credit per zone. Requesting a zone-to-zone transfer is a
/// `domains.settings` action that stays on the web; this is the balance staff
/// need before promising a client a renewal.
class _RegistrarCreditSheet extends ConsumerWidget {
  const _RegistrarCreditSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final credit = ref.watch(registrarCreditProvider);
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return CrmSheet(
      eyebrow: 'Registry',
      title: 'Registrar credit',
      children: credit.when(
        loading: () => const [
          Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
        error: (error, _) => [
          ErrorBanner(
            message: error is ApiException
                ? error.message
                : 'Could not load the registrar balance.',
            onRetry: () => ref.invalidate(registrarCreditProvider),
          ),
        ],
        data: (c) => [
          if (!c.ok) ...[
            ErrorBanner(
              message: c.error ?? 'Could not reach the registrar.',
              onRetry: () => ref.invalidate(registrarCreditProvider),
            ),
            const SizedBox(height: Spacing.md),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL FUNDED', style: meta),
              Money(c.total, scale: MoneyScale.headline),
            ],
          ),
          if (c.low.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: status.attention.withValues(alpha: 0.12),
                borderRadius: Radii.card,
              ),
              child: Text(
                'Low balance — top up soon: '
                '${c.low.map((z) => '.$z').join(', ')}. Renewals draw real '
                'prepaid credit at the registry.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.attention,
                ),
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Funded zones'),
          const SizedBox(height: Spacing.sm),
          if (c.fundedCount == 0)
            Text('No funded zones.', style: meta)
          else
            for (final zone in c.funded)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('.${zone.zone}', style: theme.textTheme.bodyMedium),
                    Money(
                      zone.credit,
                      scale: MoneyScale.dense,
                      color: c.isLow(zone.zone) ? status.attention : null,
                    ),
                  ],
                ),
              ),
          if (c.pendingTransfers.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            const SectionHeader('Pending transfers'),
            const SizedBox(height: Spacing.sm),
            for (final transfer in c.pendingTransfers)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        '.${transfer.fromZone} → .${transfer.toZone} · '
                        'awaiting TZNIC',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Money(transfer.amount, scale: MoneyScale.dense),
                  ],
                ),
              ),
          ],
          if (c.checkedAt != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'As of ${Formatting.dateTime(c.checkedAt)} · cached 5 min',
              style: meta,
            ),
          ],
        ],
      ),
    );
  }
}

/// Record a domain that is already registered elsewhere. Bookkeeping only —
/// no invoice, no EPP call — so the client's renewal reminders include it.
class _AddExistingDomainSheet extends ConsumerStatefulWidget {
  const _AddExistingDomainSheet();

  @override
  ConsumerState<_AddExistingDomainSheet> createState() =>
      _AddExistingDomainSheetState();
}

class _AddExistingDomainSheetState
    extends ConsumerState<_AddExistingDomainSheet> {
  final _name = TextEditingController();
  final _notes = TextEditingController();
  StaffClient? _client;
  String _registrar = 'external';
  DateTime? _expiresAt;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final picked = await ClientPickerSheet.show(context);
    if (picked != null) setState(() => _client = picked);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    final name = _name.text.trim().toLowerCase();
    if (!name.contains('.')) {
      setState(() => _error = 'Enter a full domain, e.g. example.co.tz');
      return;
    }
    if (_client == null) {
      setState(() => _error = 'Choose the client this domain belongs to.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(supportAdminServiceProvider)
          .addExistingDomain(
            name: name,
            clientId: _client!.id,
            registrar: _registrar,
            expiresAt: _expiresAt,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) Navigator.pop(context, message ?? '$name added.');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: 'Domains',
      title: 'Add existing domain',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Domain name',
          child: TextField(
            controller: _name,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'example.co.tz'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Client',
          value: _client?.name ?? 'Choose client',
          placeholder: _client == null,
          icon: Icons.person_outline,
          onTap: _pickClient,
        ),
        const SizedBox(height: Spacing.md),
        const FieldLabel('Currently registered at'),
        const SizedBox(height: Spacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'external', label: Text('External')),
            ButtonSegment(value: 'tznic', label: Text('TZNIC')),
          ],
          selected: {_registrar},
          showSelectedIcon: false,
          onSelectionChanged: (values) =>
              setState(() => _registrar = values.first),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Expiry date (optional)',
          value: _expiresAt == null ? 'Not known' : Formatting.date(_expiresAt),
          placeholder: _expiresAt == null,
          onTap: _pickExpiry,
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes (optional)',
          child: TextField(
            controller: _notes,
            decoration: const InputDecoration(
              hintText: 'Registrar name, reference',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          _registrar == 'tznic'
              ? 'Marks the domain as one of ours for future nameserver and '
                    'EPP actions. It does not take over sponsorship at the '
                    'registry.'
              : 'Records the domain against the client for renewal reminders. '
                    'No invoice is created and nothing changes at the '
                    'registry.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(label: 'Add domain', busy: _busy, onPressed: _submit),
        const SizedBox(height: Spacing.sm),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
