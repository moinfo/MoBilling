import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show FilterStrip;
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

class _HostingAccountsScreenState extends ConsumerState<HostingAccountsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('active', 'Active'),
    ('suspended', 'Suspended'),
    ('pending', 'Pending'),
    ('failed', 'Failed'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Hosting accounts',
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search domain or cPanel user',
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          FilterStrip(
            options: _filters,
            selected: _status,
            onSelect: (value) {
              setState(() => _status = value);
              _listKey.currentState?.reload();
            },
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
                      .hostingAccounts(
                        status: _status,
                        search: _search.text.trim().isEmpty
                            ? null
                            : _search.text.trim(),
                        page: page,
                      ),
                  itemBuilder: (context, account) => _AccountRow(
                    account: account,
                    onChanged: () => _listKey.currentState?.reload(),
                  ),
                  emptyIcon: Icons.storage_outlined,
                  emptyTitle: 'No hosting accounts',
                  emptyMessage:
                      'Try another domain, or clear the status filter.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One account: domain, status chip beside the client / package / server
/// line, and disk usage as the aligned trailing figure.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account, required this.onChanged});

  final StaffHostingAccount account;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasDisk = account.diskUsed != null && account.diskLimit != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          onTap: () => _showActions(context, ref),
          title: Text(
            account.domain ?? account.cpanelUsername ?? '—',
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                StatusChip(account.status, dense: true),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Text(
                    [
                      if (account.clientName != null) account.clientName!,
                      if (account.package != null) account.package!,
                      if (account.serverName != null) account.serverName!,
                    ].join(' · '),
                    style: meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          trailing: hasDisk
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${account.diskUsed} / ${account.diskLimit}',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text('DISK', style: meta),
                  ],
                )
              : const Icon(Icons.chevron_right),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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

class _AccountActionsSheetState extends ConsumerState<_AccountActionsSheet> {
  bool _busy = false;
  bool _changed = false;

  StaffHostingAccount get account => widget.account;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final auth = ref.watch(sessionControllerProvider).session;
    final canSuspend =
        auth?.can(SupportAdminPermissions.hostingSuspend) ?? false;
    final canSso = auth?.can(SupportAdminPermissions.hostingSso) ?? false;
    final logs = ref.watch(hostingLogsProvider(account.id));
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
                  if (account.clientName != null) ...[
                    Text(account.clientName!.toUpperCase(), style: meta),
                    const SizedBox(height: Spacing.xs),
                  ],
                  Text(
                    account.domain ?? account.cpanelUsername ?? '—',
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      StatusChip(account.status, dense: true),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: Text(
                          [
                            if (account.cpanelUsername != null)
                              account.cpanelUsername!,
                            if (account.lastSyncedAt != null)
                              'synced ${Formatting.dateTime(account.lastSyncedAt)}',
                          ].join(' · '),
                          style: meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                }),
              ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Refresh disk usage'),
              enabled: !_busy,
              onTap: () => _run(() async {
                await ref
                    .read(supportAdminServiceProvider)
                    .refreshHostingUsage(account.id);
                ref.invalidate(hostingLogsProvider(account.id));
              }, successMessage: 'Usage refreshed.'),
            ),
            if (canSuspend)
              account.isSuspended
                  ? ListTile(
                      leading: Icon(
                        Icons.play_circle_outline,
                        color: status.settled,
                      ),
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
                      leading: Icon(
                        Icons.pause_circle_outline,
                        color: scheme.error,
                      ),
                      title: Text(
                        'Suspend',
                        style: TextStyle(color: scheme.error),
                      ),
                      enabled: !_busy,
                      onTap: () async {
                        // The API records a fixed reason; confirm only.
                        final confirmed = await _confirm(
                          context,
                          'Suspend ${account.domain}?',
                          'The site goes offline until unsuspended.',
                        );
                        if (!confirmed) return;
                        await _run(
                          () => ref
                              .read(supportAdminServiceProvider)
                              .suspendHosting(account.id),
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
                        Spacing.lg,
                        Spacing.md,
                        Spacing.lg,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader('Recent provisioning'),
                          const SizedBox(height: Spacing.sm),
                          for (final entry in entries.take(4))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: Spacing.xs,
                              ),
                              child: Row(
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
                                      entry.action,
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

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
