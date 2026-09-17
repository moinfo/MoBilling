import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmField, CrmMetaLine, CrmSheet, showCrmSheet;
import 'wifi_hotspot_providers.dart';

/// MikroTik routers registered for hotspot voucher sales. The API password
/// is write-only (never returned by the API) — the form only ever shows a
/// blank field, same as the web's own `type="password"` input.
class WifiRoutersScreen extends ConsumerStatefulWidget {
  const WifiRoutersScreen({super.key});

  @override
  ConsumerState<WifiRoutersScreen> createState() => _WifiRoutersScreenState();
}

class _WifiRoutersScreenState extends ConsumerState<WifiRoutersScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  final Set<String> _testing = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(allRoutersProvider);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _listKey.currentState?.reload(),
    );
  }

  Future<void> _openForm({MikrotikRouter? router}) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _RouterFormSheet(router: router),
    );
    if (saved == true) _reload();
  }

  Future<void> _test(MikrotikRouter router) async {
    if (_testing.contains(router.id)) return;
    setState(() => _testing.add(router.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(wifiHotspotServiceProvider)
          .testRouter(router.id);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _testing.remove(router.id));
      _reload();
    }
  }

  Future<void> _delete(MikrotikRouter router) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this router?'),
        content: Text(
          '"${router.name}" (${router.host}). Any WiFi plans on it will '
          'also stop working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(wifiHotspotServiceProvider).deleteRouter(router.id);
      _reload();
      messenger.showSnackBar(const SnackBar(content: Text('Router deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate =
        session?.can(WifiHotspotPermissions.routersCreate) ?? false;
    final canUpdate =
        session?.can(WifiHotspotPermissions.routersUpdate) ?? false;
    final canDelete =
        session?.can(WifiHotspotPermissions.routersDelete) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'WiFi Hotspot',
        title: 'Routers',
        trailing: canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add router',
                onPressed: () => _openForm(),
              )
            : null,
        bottom: InkSearchField(
          controller: _search,
          hint: 'Search name or host',
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _listKey.currentState?.reload();
          },
        ),
      ),
      body: PagedListView<MikrotikRouter>(
        key: _listKey,
        fetch: (page) => ref
            .read(wifiHotspotServiceProvider)
            .routers(
              search: _search.text.trim().isEmpty ? null : _search.text.trim(),
              page: page,
            ),
        itemBuilder: (context, router) => _RouterCard(
          router: router,
          canUpdate: canUpdate,
          canDelete: canDelete,
          testing: _testing.contains(router.id),
          onTest: () => _test(router),
          onEdit: () => _openForm(router: router),
          onDelete: () => _delete(router),
        ),
        emptyIcon: Icons.router_outlined,
        emptyTitle: 'No routers yet',
        emptyMessage: canCreate
            ? 'Add your MikroTik to start selling WiFi vouchers.'
            : 'None configured yet.',
      ),
    );
  }
}

class _RouterCard extends StatelessWidget {
  const _RouterCard({
    required this.router,
    required this.canUpdate,
    required this.canDelete,
    required this.testing,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final MikrotikRouter router;
  final bool canUpdate;
  final bool canDelete;
  final bool testing;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(router.name, style: theme.textTheme.titleSmall),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CrmMetaLine(
                [
                  '${router.host}:${router.apiPort}',
                  router.isPlatformCollected
                      ? 'Platform-collected'
                      : 'Self-managed',
                ].join(' · '),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!router.isActive) ...[
                  const StatusChip('draft', dense: true),
                  const SizedBox(width: Spacing.xs),
                ],
                _LastTestBadge(router: router),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.sm,
              0,
              Spacing.sm,
              Spacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: testing ? null : onTest,
                  icon: testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cable_outlined, size: 16),
                  label: Text(testing ? 'Testing…' : 'Test connection'),
                ),
                if (canUpdate)
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: 'Delete',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: scheme.error,
                    ),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastTestBadge extends StatelessWidget {
  const _LastTestBadge({required this.router});

  final MikrotikRouter router;

  @override
  Widget build(BuildContext context) {
    if (router.lastTestStatus == null) {
      return Text(
        'Never tested',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final ok = router.lastTestStatus == 'success';
    return Tooltip(
      message: router.lastTestMessage ?? '',
      child: StatusChip(ok ? 'connected' : 'failed', dense: true),
    );
  }
}

/// Add or edit a router. The password field is required on create and
/// optional on edit — leaving it blank keeps the current one, exactly as
/// the backend's own `nullable-on-update` rule works.
class _RouterFormSheet extends ConsumerStatefulWidget {
  const _RouterFormSheet({this.router});

  final MikrotikRouter? router;

  @override
  ConsumerState<_RouterFormSheet> createState() => _RouterFormSheetState();
}

class _RouterFormSheetState extends ConsumerState<_RouterFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _localLoginHost;
  late final TextEditingController _apiPort;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late bool _useTls;
  late String _paymentMode;
  late bool _isActive;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.router != null;

  @override
  void initState() {
    super.initState();
    final r = widget.router;
    _name = TextEditingController(text: r?.name ?? '');
    _host = TextEditingController(text: r?.host ?? '');
    _localLoginHost = TextEditingController(text: r?.localLoginHost ?? '');
    _apiPort = TextEditingController(text: '${r?.apiPort ?? 8728}');
    _username = TextEditingController(text: r?.username ?? '');
    _password = TextEditingController();
    _useTls = r?.useTls ?? false;
    _paymentMode = r?.paymentMode ?? WifiPaymentModes.selfManaged;
    _isActive = r?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _localLoginHost.dispose();
    _apiPort.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final host = _host.text.trim();
    final username = _username.text.trim();
    final password = _password.text;

    if (name.isEmpty || host.isEmpty || username.isEmpty) {
      setState(() => _error = 'Name, host and username are required.');
      return;
    }
    if (!_editing && password.isEmpty) {
      setState(() => _error = 'A password is required.');
      return;
    }
    final apiPort = int.tryParse(_apiPort.text.trim()) ?? 8728;

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(wifiHotspotServiceProvider);
      if (_editing) {
        await service.updateRouter(
          widget.router!.id,
          name: name,
          host: host,
          username: username,
          password: password.isEmpty ? null : password,
          localLoginHost: _localLoginHost.text.trim().isEmpty
              ? null
              : _localLoginHost.text.trim(),
          apiPort: apiPort,
          useTls: _useTls,
          paymentMode: _paymentMode,
          isActive: _isActive,
        );
      } else {
        await service.createRouter(
          name: name,
          host: host,
          username: username,
          password: password,
          localLoginHost: _localLoginHost.text.trim().isEmpty
              ? null
              : _localLoginHost.text.trim(),
          apiPort: apiPort,
          useTls: _useTls,
          paymentMode: _paymentMode,
          isActive: _isActive,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? 'Router updated.' : 'Router added.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: 'WiFi Hotspot',
      title: _editing ? 'Edit router' : 'New router',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'e.g. Shop WiFi'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Host / IP address',
          child: TextField(
            controller: _host,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'e.g. 41.xxx.xxx.xxx'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Local hotspot IP (optional)',
          child: TextField(
            controller: _localLoginHost,
            enabled: !_busy,
            decoration: const InputDecoration(hintText: 'e.g. 192.168.88.1'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            'The address customer devices see on the WiFi itself — lets us '
            'auto-connect them after payment instead of making them type '
            'the voucher code.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'API port',
          child: TextField(
            controller: _apiPort,
            enabled: !_busy,
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Username',
          child: TextField(controller: _username, enabled: !_busy),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Password',
          child: TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(
              hintText: _editing ? 'Leave blank to keep current password' : null,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use TLS (API-SSL, port 8729)'),
          value: _useTls,
          onChanged: _busy ? null : (v) => setState(() => _useTls = v),
        ),
        const SizedBox(height: Spacing.sm),
        CrmField(
          label: 'Payment mode',
          child: DropdownButtonFormField<String>(
            initialValue: _paymentMode,
            isExpanded: true,
            items: [
              for (final (value, label) in WifiPaymentModes.values)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _paymentMode = v ?? _paymentMode),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _isActive,
          onChanged: _busy ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Add router',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
