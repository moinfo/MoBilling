import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../../providers.dart';
import '../portal_providers.dart';

/// Manage the company's portal logins. Admin-only — the backend enforces it
/// (403) and the More tab only links here for admins.
class PortalUsersScreen extends ConsumerWidget {
  const PortalUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(portalUsersProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Your account',
        title: 'Portal users',
        trailing: InkActionButton(
          icon: Icons.person_add_outlined,
          tooltip: 'Add user',
          onPressed: () => _showUserSheet(context, ref),
        ),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load users',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(portalUsersProvider),
        ),
        data: (items) => items.isEmpty
            ? StateMessage(
                icon: Icons.group_outlined,
                title: 'No portal users yet',
                message: 'Give a colleague their own sign-in to this account.',
                actionLabel: 'Add a user',
                onAction: () => _showUserSheet(context, ref),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(portalUsersProvider.future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          for (final (i, user) in items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _UserTile(
                              user: user,
                              isSelf: user.id == me?.id,
                              onAction: (action) =>
                                  _onAction(context, ref, user, action),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    PortalUser user,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(portalServiceProvider);
    try {
      switch (action) {
        case 'role':
          await service.updatePortalUser(
            user.id,
            role: user.isAdmin ? 'viewer' : 'admin',
          );
        case 'active':
          await service.updatePortalUser(user.id, isActive: !user.isActive);
        case 'delete':
          final sure = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete ${user.name}?'),
              content: const Text('They will no longer be able to sign in.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep user'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete user'),
                ),
              ],
            ),
          );
          if (sure != true) return;
          await service.deletePortalUser(user.id);
      }
      ref.invalidate(portalUsersProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showUserSheet(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    String role = 'viewer';
    String? error;
    var submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final theme = Theme.of(sheetContext);

          Future<void> submit() async {
            setSheetState(() {
              submitting = true;
              error = null;
            });
            try {
              await ref
                  .read(portalServiceProvider)
                  .createPortalUser(
                    name: name.text.trim(),
                    email: email.text.trim(),
                    password: password.text,
                    role: role,
                    phone: phone.text.trim().isEmpty
                        ? null
                        : phone.text.trim(),
                  );
              ref.invalidate(portalUsersProvider);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } on ApiException catch (e) {
              setSheetState(() {
                submitting = false;
                error =
                    e.errorFor('email') ??
                    e.errorFor('password') ??
                    e.message;
              });
            }
          }

          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: Spacing.lg,
              right: Spacing.lg,
              top: Spacing.sm,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PORTAL USERS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Add portal user',
                  style: Type.display(22, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: Spacing.lg),
                if (error != null) ...[
                  ErrorBanner(message: error!),
                  const SizedBox(height: Spacing.md),
                ],
                _FieldLabel('Name'),
                TextField(
                  controller: name,
                  enabled: !submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Full name'),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('Email'),
                TextField(
                  controller: email,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'name@company.com',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('Phone (optional)'),
                TextField(
                  controller: phone,
                  enabled: !submitting,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: '0712 345 678'),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('Password'),
                TextField(
                  controller: password,
                  enabled: !submitting,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'At least 8 characters',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('Role'),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Viewer — can see billing & services'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrator — can also manage users'),
                    ),
                  ],
                  onChanged: submitting
                      ? null
                      : (v) => setSheetState(() => role = v!),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: submitting ? 'Adding…' : 'Add user',
                  busy: submitting,
                  onPressed: submitting ? null : submit,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onAction,
  });

  final PortalUser user;
  final bool isSelf;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: Text(
        user.name + (isSelf ? ' (you)' : ''),
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(
          children: [
            StatusChip(user.isActive ? 'active' : 'deactivated', dense: true),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                [
                  user.isAdmin ? 'administrator' : 'viewer',
                  if (user.email != null || user.phone != null)
                    user.email ?? user.phone!,
                ].join(' · ').toUpperCase(),
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
      trailing: isSelf
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Manage user',
              onSelected: onAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'role',
                  child: Text(
                    user.isAdmin ? 'Make viewer' : 'Make administrator',
                  ),
                ),
                PopupMenuItem(
                  value: 'active',
                  child: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
    );
  }
}

/// The label above a field, as the sign-in form sets it.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Spacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
