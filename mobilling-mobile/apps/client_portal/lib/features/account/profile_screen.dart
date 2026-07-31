import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Profile: edit name/phone, view the company record, change password.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your profile',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(profileProvider),
        ),
        data: (p) => _Body(profile: p),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.profile});

  final PortalProfile profile;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _phone = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(portalServiceProvider).updateProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
          );
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final fresh = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: Spacing.sm),
              ],
              TextField(
                controller: current,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password'),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: fresh,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New password (min 8 characters)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (fresh.text.length < 8) {
                  setDialogState(
                      () => error = 'Use at least 8 characters.');
                  return;
                }
                try {
                  await ref.read(portalServiceProvider).changePassword(
                        currentPassword: current.text,
                        newPassword: fresh.text,
                      );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Password changed.')));
                  }
                } on ApiException catch (e) {
                  setDialogState(() =>
                      error = e.errorFor('current_password') ?? e.message);
                }
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.profile;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Text('Your details', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _name,
          enabled: !_saving,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _phone,
          enabled: !_saving,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'Signed in as ${p.email ?? '—'} · ${p.isAdmin ? 'administrator' : 'viewer'}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.md),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
        OutlinedButton(
          onPressed: _changePassword,
          child: const Text('Change password'),
        ),
        const SizedBox(height: Spacing.lg),

        Text('Billing account', style: theme.textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.companyName ?? '—', style: theme.textTheme.titleSmall),
                if (p.companyAddress != null) Text(p.companyAddress!),
                if (p.companyEmail != null) Text(p.companyEmail!),
                if (p.companyPhone != null) Text(p.companyPhone!),
                if (p.taxId != null) Text('TIN: ${p.taxId}'),
                const SizedBox(height: Spacing.xs),
                Text(
                  'To change these details, contact your service provider.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
