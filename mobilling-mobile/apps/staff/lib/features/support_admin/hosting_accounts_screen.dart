import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  /// Runs one action behind the busy guard, with the standard error snackbar.
  /// Answers whether it succeeded, so a caller that must follow up — the
  /// terminate row closes the sheet — can tell.
  Future<bool> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      _changed = true;
      if (successMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// [_run] for the endpoints that answer with their own message. The queued
  /// ones (terminate, change package) only report what was *started*, so
  /// their wording matters more than anything this screen could invent.
  Future<bool> _runWithMessage(
    Future<String?> Function() action, {
    required String fallback,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    return _run(() async {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message ?? fallback)));
    });
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
    final canTerminate =
        auth?.can(SupportAdminPermissions.hostingTerminate) ?? false;
    // The same permission gates the package change and both password calls.
    final canChangePackage =
        auth?.can(SupportAdminPermissions.hostingChangePackage) ?? false;
    final service = ref.read(supportAdminServiceProvider);
    final name = account.domain ?? account.cpanelUsername ?? 'this account';
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
            // The billing side of the same thing: the subscription is where
            // the plan, the dates and the money live, and none of that is on
            // an account row. Only reachable when something was ordered —
            // an imported account may have no subscription behind it.
            if (account.subscriptionId != null)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Open service'),
                subtitle: const Text('Plan, billing and dates'),
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                enabled: !_busy,
                onTap: () {
                  Navigator.of(context).pop(_changed);
                  context.push('/hosting/services/${account.subscriptionId}');
                },
              ),
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
            // Package and password changes stay available on a suspended
            // account — WHM accepts both — so they are gated on permission
            // alone, the way the API gates them.
            if (canChangePackage) ...[
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Change package'),
                subtitle: account.package == null
                    ? null
                    : Text('Currently ${account.package}'),
                enabled: !_busy,
                onTap: () async {
                  final package = await _askPackage(context);
                  if (package == null) return;
                  await _runWithMessage(
                    () => service.changeHostingPackage(account.id, package),
                    fallback: 'Package change started.',
                  );
                  ref.invalidate(hostingLogsProvider(account.id));
                },
              ),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change cPanel password'),
                enabled: !_busy,
                onTap: () async {
                  final password = await _askPassword(context);
                  if (password == null) return;
                  await _runWithMessage(
                    () => service.changeHostingPassword(account.id, password),
                    fallback: 'cPanel password changed.',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Reset password & resend welcome'),
                enabled: !_busy,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final confirmed = await _confirm(
                    context,
                    'Reset the password for $name?',
                    'The server picks a new cPanel password and sends the '
                        'client the welcome message carrying it. The current '
                        'password stops working straight away.',
                    confirmLabel: 'Reset & send',
                  );
                  if (!confirmed) return;
                  String? generated;
                  final done = await _run(() async {
                    final result = await service.resetHostingWelcome(
                      account.id,
                    );
                    generated = result.password;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          result.message ??
                              'Password reset and welcome message sent.',
                        ),
                      ),
                    );
                  });
                  // The response is the only place this ever appears — staff
                  // on a call need to be able to read it out.
                  if (done && generated != null && context.mounted) {
                    await _showGeneratedPassword(context, generated!);
                  }
                },
              ),
            ],
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
                          'Suspend $name?',
                          'The site goes offline until unsuspended.',
                          confirmLabel: 'Suspend',
                          destructive: true,
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
            // Last, and the only one that cannot be walked back: the account
            // and everything on it leaves the server.
            if (canTerminate && account.status != 'terminated')
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: scheme.error,
                ),
                title: Text('Terminate', style: TextStyle(color: scheme.error)),
                enabled: !_busy,
                onTap: () async {
                  final confirmed = await _confirm(
                    context,
                    'Terminate $name?',
                    'The cPanel account for $name is deleted from '
                        '${account.serverName ?? 'the server'} — its files, '
                        'databases, and mailboxes go with it. This cannot be '
                        'undone.',
                    confirmLabel: 'Terminate',
                    destructive: true,
                  );
                  if (!confirmed) return;
                  final done = await _runWithMessage(
                    () => service.terminateHosting(account.id),
                    fallback: 'Termination started.',
                  );
                  // Nothing left to act on — close rather than leave the
                  // other actions live against a doomed account.
                  if (done && context.mounted) {
                    Navigator.of(context).pop(true);
                  }
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

  /// [confirmLabel] names the verb rather than saying "OK", so the button
  /// itself states what is about to happen; [destructive] paints it in the
  /// error colour.
  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body, {
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final scheme = Theme.of(context).colorScheme;
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
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Shown once, after the server has generated it. The welcome message is
  /// the client's copy; this is the only time the password reaches staff, so
  /// it is selectable and copyable rather than something to memorise.
  Future<void> _showGeneratedPassword(BuildContext context, String password) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New cPanel password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Note it now — it is not shown again. The client also has it '
              'in the welcome message.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: Type.mono(
                        13,
                        weight: FontWeight.w400,
                        tracking: 0,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password copied.')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// The WHM package list sits behind `GET /servers/{id}/packages`, which
  /// needs `hosting.settings`. With that permission and the account's server
  /// this offers the real list; without either — or if WHM cannot be reached
  /// — it degrades to a typed field, the same swap the web makes when its
  /// package query errors.
  Future<String?> _askPackage(BuildContext context) {
    final canListPackages =
        ref.read(sessionControllerProvider).session?.can(
          SupportAdminPermissions.hostingSettings,
        ) ??
        false;

    return showDialog<String>(
      context: context,
      builder: (context) => _PackageDialog(
        current: account.package,
        serverId: canListPackages ? account.serverId : null,
        service: ref.read(supportAdminServiceProvider),
      ),
    );
  }

  /// Obscured by default, with the same 8-character floor the API enforces
  /// so a typo comes back before the round trip. The password is never shown
  /// again once it is set.
  Future<String?> _askPassword(BuildContext context) async {
    final controller = TextEditingController();
    var obscured = true;
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('New cPanel password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sets the password for '
                  '${account.cpanelUsername ?? account.domain ?? 'this account'} '
                  'on the server. The client is told it changed, never what '
                  'it is.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'At least 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      tooltip: obscured ? 'Show' : 'Hide',
                      icon: Icon(
                        obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setLocal(() => obscured = !obscured),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Generate'),
                    // Shown so it can be copied before it is sent; it is the
                    // only moment staff ever see it.
                    onPressed: () => setLocal(() {
                      controller.text = _generatedPassword();
                      obscured = false;
                    }),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.length < 8
                      ? null
                      : () => Navigator.pop(context, value.text),
                  child: const Text('Set password'),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  /// Mixed case and digits from an alphabet without the lookalike
  /// characters, then a symbol and a digit so WHM's strength check passes
  /// whatever the random draw was.
  static String _generatedPassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    const symbols = '!@#%^&*-_=+';
    final random = Random.secure();
    final body = List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return '$body${symbols[random.nextInt(symbols.length)]}${random.nextInt(10)}';
  }
}

/// Picks the new WHM package, from the server's own list where that is
/// readable and by hand where it is not.
///
/// A [serverId] of null means the caller could not offer the list — no
/// `hosting.settings`, or an account with no server — and the dialog opens
/// straight into the typed field. A WHM that cannot be reached lands in the
/// same place, with the reason said out loud.
class _PackageDialog extends StatefulWidget {
  const _PackageDialog({
    required this.current,
    required this.serverId,
    required this.service,
  });

  final String? current;
  final String? serverId;
  final SupportAdminService service;

  @override
  State<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<_PackageDialog> {
  final _typed = TextEditingController();
  final _filter = TextEditingController();

  List<String>? _packages;
  bool _loading = false;

  /// Set when WHM refused or could not be reached, to distinguish "we never
  /// asked" from "we asked and it failed" in the typed field's explanation.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _typed.text = widget.current ?? '';
    if (widget.serverId != null) _load(widget.serverId!);
  }

  @override
  void dispose() {
    _typed.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load(String serverId) async {
    setState(() => _loading = true);
    try {
      final packages = await widget.service.serverPackages(serverId);
      if (!mounted) return;
      // The account's own package may predate the list, or have been renamed
      // on the server — keep it selectable either way.
      final current = widget.current;
      final all =
          {if (current != null && current.isNotEmpty) current, ...packages}
              .toList()
            ..sort();
      setState(() {
        // A server that reports no packages at all leaves nothing to pick
        // from — the typed field is the only way through.
        _packages = all.isEmpty ? null : all;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packages = _packages;

    return AlertDialog(
      title: const Text('Change package'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            : packages == null
            ? _typedField(theme)
            : _picker(theme, packages),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (packages == null && !_loading)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _typed,
            builder: (context, value, _) {
              final package = value.text.trim();
              return FilledButton(
                onPressed: package.isEmpty || package == widget.current
                    ? null
                    : () => Navigator.pop(context, package),
                child: const Text('Change package'),
              );
            },
          ),
      ],
    );
  }

  Widget _typedField(ThemeData theme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _loadError == null
            ? 'Type the WHM package name exactly as the server spells it.'
            : 'Could not load packages from the server — type the exact WHM '
                  'package name.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: Spacing.md),
      TextField(
        controller: _typed,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          hintText: widget.current == null
              ? 'WHM package name'
              : 'Currently ${widget.current}',
          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
        ),
      ),
    ],
  );

  Widget _picker(ThemeData theme, List<String> packages) {
    final query = _filter.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? packages
        : packages.where((p) => p.toLowerCase().contains(query)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A WHM box with a handful of packages does not need a search field
        // taking the top of a dialog this small.
        if (packages.length > 8) ...[
          TextField(
            controller: _filter,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Filter packages',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  child: Text(
                    'No package matches that.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final package = shown[i];
                    final isCurrent = package == widget.current;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        package,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isCurrent
                          ? const StatusChip('active', dense: true)
                          : null,
                      enabled: !isCurrent,
                      onTap: () => Navigator.pop(context, package),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
