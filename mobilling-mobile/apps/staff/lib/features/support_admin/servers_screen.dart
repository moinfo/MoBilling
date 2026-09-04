import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmCardList, CrmField, CrmSheet, showCrmSheet;
import 'support_admin_providers.dart';

/// The WHM/cPanel boxes hosting accounts are provisioned onto.
///
/// The whole `/servers` group sits behind `hosting.settings`, which is also
/// what the package lists elsewhere read — so a staff member who cannot open
/// this screen also cannot be offered a package picker anywhere else.
class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(SupportAdminPermissions.hostingSettings) ??
        false;

    if (!canManage) {
      return const Scaffold(
        appBar: ShellTopBar(eyebrow: 'Web Services', title: 'Servers'),
        body: StateMessage(
          icon: Icons.lock_outline,
          title: 'Not available',
          message: 'Managing servers needs the hosting settings permission.',
        ),
      );
    }

    final servers = ref.watch(hostingServersProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Web Services',
        title: 'Servers',
        trailing: InkActionButton(
          icon: Icons.add_rounded,
          tooltip: 'Add server',
          onPressed: () => _openForm(context, ref, null),
        ),
      ),
      body: CrmAsyncView(
        value: servers,
        errorTitle: 'Could not load servers',
        onRetry: () => ref.invalidate(hostingServersProvider),
        builder: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(hostingServersProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              const _TokenNote(),
              const SizedBox(height: Spacing.lg),
              if (items.isEmpty)
                SizedBox(
                  height: 240,
                  child: StateMessage(
                    icon: Icons.dns_outlined,
                    title: 'No servers yet',
                    message:
                        'Add the WHM box your hosting products are '
                        'provisioned onto.',
                    actionLabel: 'Add server',
                    onAction: () => _openForm(context, ref, null),
                  ),
                )
              else ...[
                const SectionHeader('WHM servers'),
                const SizedBox(height: Spacing.sm),
                CrmCardList(
                  children: [
                    for (final server in items) _ServerRow(server: server),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the token comes from. Staff hit this screen with a WHM login in
/// hand and no idea that the API token is a separate thing generated
/// elsewhere, so the instruction belongs on the screen, not in a manual.
class _TokenNote extends StatelessWidget {
  const _TokenNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Create the API token in WHM under Development → Manage API '
              'Tokens. Hosting products are provisioned onto these servers '
              'when their subscription is activated.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One server: the name, then `user@host:port` in the mono face because that
/// is the string staff recognise from an SSH prompt, and the account count as
/// the trailing figure — the number that decides whether it can be deleted.
class _ServerRow extends ConsumerWidget {
  const _ServerRow({required this.server});

  final HostingServer server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return ListTile(
      onTap: () => _openActions(context, ref, server),
      title: Text(
        server.name,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(
              server.isActive ? 'active' : 'inactive',
              dense: true,
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                '${server.username}@${server.address}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.mono(
                  11.5,
                  weight: FontWeight.w400,
                  tracking: 0,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${server.hostingAccountsCount}',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          Text('ACCOUNTS', style: meta),
        ],
      ),
    );
  }
}

Future<void> _openActions(
  BuildContext context,
  WidgetRef ref,
  HostingServer server,
) async {
  final changed = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ServerActionsSheet(server: server),
  );
  if (changed == true) ref.invalidate(hostingServersProvider);
}

Future<void> _openForm(
  BuildContext context,
  WidgetRef ref,
  HostingServer? existing,
) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => _ServerForm(existing: existing),
  );
  if (saved == true) ref.invalidate(hostingServersProvider);
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

class _ServerActionsSheet extends ConsumerStatefulWidget {
  const _ServerActionsSheet({required this.server});

  final HostingServer server;

  @override
  ConsumerState<_ServerActionsSheet> createState() =>
      _ServerActionsSheetState();
}

class _ServerActionsSheetState extends ConsumerState<_ServerActionsSheet> {
  bool _busy = false;
  bool _changed = false;

  /// Null until a test has run; empty means WHM answered with no packages,
  /// which is a different fact from "not tested" and reads differently.
  List<String>? _packages;

  HostingServer get server => widget.server;

  /// Proves the credentials and, as a side effect, shows what the server can
  /// actually provision — the same call the package pickers read, so a green
  /// result here means those will work too.
  Future<void> _test() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final packages = await ref
          .read(supportAdminServiceProvider)
          .testServer(server.id);
      if (!mounted) return;
      setState(() => _packages = packages);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Connected — ${packages.length} '
            '${packages.length == 1 ? 'package' : 'packages'} found.',
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${server.name}?'),
        content: Text(
          server.hasAccounts
              ? '${server.hostingAccountsCount} hosting '
                    '${server.hostingAccountsCount == 1 ? 'account is' : 'accounts are'} '
                    'still on this server, so the API will refuse. Deactivate '
                    'it instead to stop new provisioning.'
              : 'MoBilling stops talking to this WHM box. Nothing on the '
                    'server itself is touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(supportAdminServiceProvider).deleteServer(server.id);
      messenger.showSnackBar(const SnackBar(content: Text('Server deleted.')));
      // Nothing left to act on.
      navigator.pop(true);
    } on ApiException catch (e) {
      // The 422 here is the "still has accounts" refusal, which already says
      // to deactivate instead.
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final packages = _packages;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: Spacing.md + sheetBottomInset(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHM SERVER',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    server.name,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      StatusChip(
                        server.isActive ? 'active' : 'inactive',
                        dense: true,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: Text(
                          '${server.username}@${server.address}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.mono(
                            11.5,
                            weight: FontWeight.w400,
                            tracking: 0,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            ListTile(
              leading: const Icon(Icons.electrical_services_outlined),
              title: const Text('Test connection'),
              subtitle: const Text('Lists the packages WHM offers'),
              enabled: !_busy,
              onTap: _test,
            ),
            if (packages != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: packages.isEmpty
                    ? Text(
                        'WHM answered, but offers no packages.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Wrap(
                        spacing: Spacing.xs,
                        runSpacing: Spacing.xs,
                        children: [
                          for (final package in packages)
                            _PackagePill(package),
                        ],
                      ),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit server'),
              enabled: !_busy,
              onTap: () async {
                final saved = await showCrmSheet<bool>(
                  context: context,
                  builder: (_) => _ServerForm(existing: server),
                );
                if (saved == true) {
                  _changed = true;
                  if (context.mounted) Navigator.of(context).pop(true);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete server',
                style: TextStyle(color: scheme.error),
              ),
              enabled: !_busy,
              onTap: _delete,
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

/// One WHM package name, in the mono face because it is an identifier that
/// has to be typed back exactly elsewhere.
class _PackagePill extends StatelessWidget {
  const _PackagePill(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        name,
        style: Type.mono(
          11,
          weight: FontWeight.w400,
          tracking: 0,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form
// ---------------------------------------------------------------------------

class _ServerForm extends ConsumerStatefulWidget {
  const _ServerForm({this.existing});

  final HostingServer? existing;

  @override
  ConsumerState<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends ConsumerState<_ServerForm> {
  late final TextEditingController _name;
  late final TextEditingController _hostname;
  late final TextEditingController _port;
  late final TextEditingController _username;
  final _token = TextEditingController();

  late bool _active;
  late bool _verifySsl;
  bool _obscureToken = true;
  bool _submitting = false;
  String? _error;

  HostingServer? get existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final server = widget.existing;
    _name = TextEditingController(text: server?.name ?? '');
    _hostname = TextEditingController(text: server?.hostname ?? '');
    _port = TextEditingController(text: '${server?.port ?? 2087}');
    _username = TextEditingController(text: server?.username ?? 'root');
    _active = server?.isActive ?? true;
    _verifySsl = server?.verifySsl ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _hostname.dispose();
    _port.dispose();
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  /// The API strips a pasted scheme and stray punctuation before validating;
  /// doing the same here means a hostname copied out of a browser bar is
  /// accepted rather than bounced back as a format error.
  static String _normalizeHostname(String raw) => raw
      .trim()
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceAll(RegExp(r'^[ ,;/]+|[ ,;/]+$'), '');

  static final _hostnamePattern = RegExp(
    r'^[a-z0-9][a-z0-9.-]*[a-z0-9]$',
    caseSensitive: false,
  );

  Future<void> _submit() async {
    final name = _name.text.trim();
    final hostname = _normalizeHostname(_hostname.text);
    final username = _username.text.trim();
    final token = _token.text.trim();
    final port = int.tryParse(_port.text.trim());

    final problem = switch (null) {
      _ when name.isEmpty => 'A name is required.',
      _ when hostname.isEmpty => 'A hostname is required.',
      _ when !_hostnamePattern.hasMatch(hostname) =>
        'That hostname does not look right — use something like '
            'server.example.com.',
      _ when port == null || port < 1 || port > 65535 =>
        'The port must be between 1 and 65535.',
      _ when username.isEmpty => 'A WHM username is required.',
      _ when existing == null && token.isEmpty =>
        'An API token is required to add a server.',
      _ => null,
    };
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(supportAdminServiceProvider);
      final server = existing;
      if (server == null) {
        await service.createServer(
          name: name,
          hostname: hostname,
          username: username,
          apiToken: token,
          port: port!,
          isActive: _active,
          verifySsl: _verifySsl,
        );
      } else {
        await service.updateServer(
          server.id,
          name: name,
          hostname: hostname,
          username: username,
          // Blank keeps the stored token — the API never reads one back, so
          // there is nothing to prefill the field with.
          apiToken: token.isEmpty ? null : token,
          port: port,
          isActive: _active,
          verifySsl: _verifySsl,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('hostname') ??
            e.errorFor('api_token') ??
            e.errorFor('name') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = existing == null;

    return CrmSheet(
      eyebrow: 'WHM servers',
      title: adding ? 'Add server' : 'Edit server',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_submitting,
            decoration: const InputDecoration(hintText: 'cPanel-01'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Hostname',
          child: TextField(
            controller: _hostname,
            enabled: !_submitting,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'server.example.com',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Port',
          child: TextField(
            controller: _port,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '2087',
              helperText: 'WHM listens on 2087 unless it was moved',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'WHM username',
          child: TextField(
            controller: _username,
            enabled: !_submitting,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'root, or a reseller account',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'API token',
          child: TextField(
            controller: _token,
            enabled: !_submitting,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: adding
                  ? 'From WHM → Development → Manage API Tokens'
                  : 'Leave blank to keep the current token',
              suffixIcon: IconButton(
                tooltip: _obscureToken ? 'Show' : 'Hide',
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureToken = !_obscureToken),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('New subscriptions can be provisioned here'),
          value: _active,
          onChanged: _submitting ? null : (v) => setState(() => _active = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Verify SSL certificate'),
          subtitle: const Text('Turn off only for a self-signed certificate'),
          value: _verifySsl,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _verifySsl = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : (adding ? 'Add server' : 'Save server'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
