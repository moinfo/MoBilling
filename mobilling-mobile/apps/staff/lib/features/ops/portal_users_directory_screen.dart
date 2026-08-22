import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmDetailRow, FilterStrip;
import 'ops_providers.dart';

/// Every client's portal logins, tenant-wide: find one, fix their role or
/// phone, reset a forgotten password, or remove them.
///
/// "Login as" (web) is deliberately absent — it swaps the browser session
/// for a portal token, which has no sensible equivalent inside the staff
/// app. Per-client management also lives on the client detail screen.
class PortalUsersDirectoryScreen extends ConsumerStatefulWidget {
  const PortalUsersDirectoryScreen({super.key});

  @override
  ConsumerState<PortalUsersDirectoryScreen> createState() =>
      _PortalUsersDirectoryScreenState();
}

class _PortalUsersDirectoryScreenState
    extends ConsumerState<PortalUsersDirectoryScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _role;
  bool? _active;

  static const _roleFilters = <(String?, String)>[
    (null, 'All roles'),
    ('admin', 'Admins'),
    ('viewer', 'Viewers'),
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
      appBar: AppBar(title: const Text('Portal users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, 0),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search name, email or client',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          FilterStrip(
            options: _roleFilters,
            selected: _role,
            onSelect: (v) {
              setState(() => _role = v);
              _listKey.currentState?.reload();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, 0),
            child: SegmentedButton<bool?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(value: true, label: Text('Active')),
                ButtonSegment(value: false, label: Text('Disabled')),
              ],
              selected: {_active},
              onSelectionChanged: (s) {
                setState(() => _active = s.first);
                _listKey.currentState?.reload();
              },
              showSelectedIcon: false,
              style:
                  const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: PagedListView<PortalUserRow>(
              key: _listKey,
              fetch: (page) => ref.read(opsServiceProvider).portalUsers(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    role: _role,
                    active: _active,
                    page: page,
                  ),
              itemBuilder: (context, user) => _PortalUserCard(
                user: user,
                onTap: () => _openActions(context, user),
              ),
              emptyIcon: Icons.admin_panel_settings_outlined,
              emptyTitle: 'No portal users found',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openActions(BuildContext context, PortalUserRow user) async {
    final auth = ref.read(sessionControllerProvider).session;
    final canEdit = auth?.can(OpsPermissions.clientsUpdate) ?? false;
    final canReset = auth?.can(OpsPermissions.portalPassword) ?? false;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(opsServiceProvider);

    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Spacing.xs),
                    CrmDetailRow('Client', user.clientName),
                    CrmDetailRow('Email', user.email),
                    if (user.phone != null) CrmDetailRow('Phone', user.phone!),
                    CrmDetailRow('Role', user.role),
                    CrmDetailRow(
                        'Last login',
                        user.lastLoginAt == null
                            ? 'Never'
                            : Formatting.dateTime(user.lastLoginAt)),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit details'),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              if (canEdit)
                ListTile(
                  leading: Icon(user.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline),
                  title: Text(user.isActive ? 'Disable login' : 'Enable login'),
                  onTap: () => Navigator.pop(context, 'toggle'),
                ),
              if (canReset)
                ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('Reset password'),
                  onTap: () => Navigator.pop(context, 'password'),
                ),
              if (canEdit)
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  title: Text('Delete portal user',
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;

    try {
      switch (action) {
        case 'edit':
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
            builder: (_) => _EditPortalUserSheet(user: user),
          );
          if (!(saved ?? false)) return;
        case 'toggle':
          await service.updatePortalUser(user.clientId, user.id,
              isActive: !user.isActive);
          messenger.showSnackBar(SnackBar(
              content: Text(user.isActive ? 'Login disabled.' : 'Login enabled.')));
        case 'password':
          final password = await _askPassword(context, user);
          if (password == null) return;
          final message = await service.resetPortalPassword(user.clientId,
              portalUserId: user.id, password: password);
          messenger.showSnackBar(
              SnackBar(content: Text(message ?? 'Password updated.')));
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete ${user.name}?'),
              content: Text(
                  'They lose portal access to ${user.clientName}. The client record itself is untouched.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
              ],
            ),
          );
          if (!(confirmed ?? false)) return;
          await service.deletePortalUser(user.clientId, user.id);
          messenger
              .showSnackBar(const SnackBar(content: Text('Portal user deleted.')));
      }
      _listKey.currentState?.reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<String?> _askPassword(BuildContext context, PortalUserRow user) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New password for ${user.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Password (min 8 characters)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              if (value.length < 8) return;
              Navigator.pop(context, value);
            },
            child: const Text('Set password'),
          ),
        ],
      ),
    );
  }
}

class _PortalUserCard extends StatelessWidget {
  const _PortalUserCard({required this.user, required this.onTap});

  final PortalUserRow user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
        ),
        title: Text(user.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${user.clientName} · ${user.email}',
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusChip(user.role, dense: true),
            if (!user.isActive) ...[
              const SizedBox(height: 2),
              StatusChip('inactive', dense: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditPortalUserSheet extends ConsumerStatefulWidget {
  const _EditPortalUserSheet({required this.user});

  final PortalUserRow user;

  @override
  ConsumerState<_EditPortalUserSheet> createState() =>
      _EditPortalUserSheetState();
}

class _EditPortalUserSheetState extends ConsumerState<_EditPortalUserSheet> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late String _role = widget.user.role;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(opsServiceProvider).updatePortalUser(
            widget.user.clientId,
            widget.user.id,
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            role: _role,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Edit — ${widget.user.name}',
              style: theme.textTheme.titleMedium),
          Text(widget.user.clientName, style: theme.textTheme.bodySmall),
          const SizedBox(height: Spacing.md),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.sm),
          ],
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: Spacing.sm),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'admin', label: Text('Admin')),
              ButtonSegment(value: 'viewer', label: Text('Viewer')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Admins can add and remove other portal users for their company.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
