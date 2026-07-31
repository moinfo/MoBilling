import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Manage the company's portal logins. Admin-only — the backend enforces it
/// (403) and the More tab only links here for admins.
class PortalUsersScreen extends ConsumerWidget {
  const PortalUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(portalUsersProvider);
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Portal users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserSheet(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add user'),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load users',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalUsersProvider),
        ),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(Spacing.md),
          itemCount: items.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: Spacing.sm),
          itemBuilder: (context, index) {
            final user = items[index];
            final isSelf = user.id == me?.id;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                    child: Text(user.name.isEmpty
                        ? '?'
                        : user.name[0].toUpperCase())),
                title: Text(user.name + (isSelf ? ' (you)' : '')),
                subtitle: Text([
                  user.email ?? user.phone ?? '',
                  user.isAdmin ? 'administrator' : 'viewer',
                  if (!user.isActive) 'deactivated',
                ].where((s) => s.isNotEmpty).join(' · ')),
                trailing: isSelf
                    ? null
                    : PopupMenuButton<String>(
                        onSelected: (action) =>
                            _onAction(context, ref, user, action),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'role',
                            child: Text(user.isAdmin
                                ? 'Make viewer'
                                : 'Make administrator'),
                          ),
                          PopupMenuItem(
                            value: 'active',
                            child: Text(
                                user.isActive ? 'Deactivate' : 'Reactivate'),
                          ),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, PortalUser user,
      String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(portalServiceProvider);
    try {
      switch (action) {
        case 'role':
          await service.updatePortalUser(user.id,
              role: user.isAdmin ? 'viewer' : 'admin');
        case 'active':
          await service.updatePortalUser(user.id, isActive: !user.isActive);
        case 'delete':
          final sure = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete ${user.name}?'),
              content:
                  const Text('They will no longer be able to sign in.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
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
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add portal user',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              if (error != null) ...[
                ErrorBanner(message: error!),
                const SizedBox(height: Spacing.sm),
              ],
              TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: Spacing.sm),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: Spacing.sm),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)')),
              const SizedBox(height: Spacing.sm),
              TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password (min 8 characters)')),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Viewer — can see billing & services')),
                  DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrator — can also manage users')),
                ],
                onChanged: (v) => setSheetState(() => role = v!),
              ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
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
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } on ApiException catch (e) {
                          setSheetState(() {
                            submitting = false;
                            error = e.errorFor('email') ??
                                e.errorFor('password') ??
                                e.message;
                          });
                        }
                      },
                child: Text(submitting ? 'Adding…' : 'Add user'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
