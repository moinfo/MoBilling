import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'support_admin_providers.dart';

/// Hosting accounts across every client.
///
/// The API has no per-account show route — the list row plus `/logs` is
/// everything available — so actions live in a bottom sheet on the row rather
/// than a detail screen that would have nothing extra to display.
class HostingAccountsScreen extends ConsumerStatefulWidget {
  const HostingAccountsScreen({super.key});

  @override
  ConsumerState<HostingAccountsScreen> createState() =>
      _HostingAccountsScreenState();
}

class _HostingAccountsScreenState
    extends ConsumerState<HostingAccountsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('suspended', 'Suspended'),
    ('pending', 'Pending'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Hosting accounts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search domain or cPanel user',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              itemCount: _filters.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: Spacing.sm),
              itemBuilder: (context, index) {
                final (value, label) = _filters[index];
                return FilterChip(
                  label: Text(label),
                  selected: _status == value,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _status = value);
                    _listKey.currentState?.reload();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              fetch: (page) =>
                  ref.read(supportAdminServiceProvider).hostingAccounts(
                        status: _status,
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                        page: page,
                      ),
              itemBuilder: (context, account) => _AccountCard(
                account: account,
                onChanged: () => _listKey.currentState?.reload(),
              ),
              emptyIcon: Icons.storage_outlined,
              emptyTitle: 'No hosting accounts',
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account, required this.onChanged});

  final StaffHostingAccount account;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        title: Text(account.domain ?? account.cpanelUsername ?? '—'),
        subtitle: Text(
          [
            if (account.clientName != null) account.clientName!,
            if (account.package != null) account.package!,
            if (account.diskUsed != null && account.diskLimit != null)
              '${account.diskUsed} / ${account.diskLimit}',
            if (account.serverName != null) account.serverName!,
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(account.status, dense: true),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _showActions(context, ref),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _AccountActionsSheet(account: account),
    );
    if (changed == true) onChanged();
  }
}

class _AccountActionsSheet extends ConsumerStatefulWidget {
  const _AccountActionsSheet({required this.account});

  final StaffHostingAccount account;

  @override
  ConsumerState<_AccountActionsSheet> createState() =>
      _AccountActionsSheetState();
}

class _AccountActionsSheetState
    extends ConsumerState<_AccountActionsSheet> {
  bool _busy = false;
  bool _changed = false;

  StaffHostingAccount get account => widget.account;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(sessionControllerProvider).session;
    final canSuspend =
        auth?.can(SupportAdminPermissions.hostingSuspend) ?? false;
    final canSso = auth?.can(SupportAdminPermissions.hostingSso) ?? false;
    final logs = ref.watch(hostingLogsProvider(account.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(account.domain ?? '—',
                            style: theme.textTheme.titleMedium),
                      ),
                      StatusChip(account.status, dense: true),
                    ],
                  ),
                  Text(
                    [
                      if (account.clientName != null) account.clientName!,
                      if (account.cpanelUsername != null)
                        account.cpanelUsername!,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (account.lastSyncedAt != null)
                    Text(
                      'Usage synced ${Formatting.dateTime(account.lastSyncedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            if (canSso && account.isActive)
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Open cPanel'),
                enabled: !_busy,
                onTap: () => _run(() async {
                  final url = await ref
                      .read(supportAdminServiceProvider)
                      .hostingSsoUrl(account.id);
                  if (url.isNotEmpty) {
                    await launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication);
                  }
                }),
              ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Refresh disk usage'),
              enabled: !_busy,
              onTap: () => _run(
                () async {
                  await ref
                      .read(supportAdminServiceProvider)
                      .refreshHostingUsage(account.id);
                  ref.invalidate(hostingLogsProvider(account.id));
                },
                successMessage: 'Usage refreshed.',
              ),
            ),
            if (canSuspend)
              account.isSuspended
                  ? ListTile(
                      leading: Icon(Icons.play_circle_outline,
                          color: context.statusColors.settled),
                      title: const Text('Unsuspend'),
                      enabled: !_busy,
                      onTap: () => _run(
                        () => ref
                            .read(supportAdminServiceProvider)
                            .unsuspendHosting(account.id),
                        successMessage: 'Account unsuspended.',
                      ),
                    )
                  : ListTile(
                      leading: Icon(Icons.pause_circle_outline,
                          color: theme.colorScheme.error),
                      title: Text('Suspend',
                          style:
                              TextStyle(color: theme.colorScheme.error)),
                      enabled: !_busy,
                      onTap: () async {
                        final reason = await _askReason(context);
                        if (reason == null) return;
                        await _run(
                          () => ref
                              .read(supportAdminServiceProvider)
                              .suspendHosting(account.id, reason: reason),
                          successMessage: 'Account suspended.',
                        );
                      },
                    ),
            // Provisioning history — the only extra data the API offers per
            // account, and the fastest way to see why something failed.
            logs.maybeWhen(
              data: (entries) => entries.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Spacing.lg, Spacing.sm, Spacing.lg, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recent provisioning',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: Spacing.xs),
                          for (final entry in entries.take(4))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    entry.success
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    size: 14,
                                    color: entry.success
                                        ? context.statusColors.settled
                                        : context.statusColors.overdue,
                                  ),
                                  const SizedBox(width: Spacing.xs),
                                  Expanded(
                                    child: Text(
                                      '${entry.action} · ${Formatting.date(entry.createdAt)}',
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
              onPressed: () => Navigator.of(context).pop(_changed),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suspend account'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
  }
}
