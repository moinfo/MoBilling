import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';

/// Profile: edit name/phone, view the company record, change password.
class PortalProfileScreen extends ConsumerWidget {
  const PortalProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(portalProfileProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Your account', title: 'My profile'),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your profile',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(portalProfileProvider),
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
  String? _error;

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
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(portalServiceProvider)
          .updateProfile(name: _name.text.trim(), phone: _phone.text.trim());
      ref.invalidate(portalProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final fresh = TextEditingController();
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
            if (fresh.text.length < 8) {
              setSheetState(() => error = 'Use at least 8 characters.');
              return;
            }
            setSheetState(() {
              submitting = true;
              error = null;
            });
            try {
              await ref
                  .read(portalServiceProvider)
                  .changePassword(
                    currentPassword: current.text,
                    newPassword: fresh.text,
                  );
              if (sheetContext.mounted) Navigator.pop(sheetContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password changed.')),
                );
              }
            } on ApiException catch (e) {
              setSheetState(() {
                submitting = false;
                error = e.errorFor('current_password') ?? e.message;
              });
            }
          }

          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: Spacing.lg,
              right: Spacing.lg,
              top: Spacing.sm,
              bottom: sheetBottomInset(sheetContext) + Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'YOUR ACCOUNT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Change password',
                  style: Type.display(22, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: Spacing.lg),
                if (error != null) ...[
                  ErrorBanner(message: error!),
                  const SizedBox(height: Spacing.md),
                ],
                _FieldLabel('Current password'),
                TextField(
                  controller: current,
                  enabled: !submitting,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Your current password',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('New password'),
                TextField(
                  controller: fresh,
                  enabled: !submitting,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submitting ? null : submit(),
                  decoration: const InputDecoration(
                    hintText: 'At least 8 characters',
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: submitting ? 'Changing…' : 'Change password',
                  busy: submitting,
                  onPressed: submitting ? null : submit,
                ),
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(sheetContext),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
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
        const SectionHeader('Your details'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: Spacing.md),
                ],
                _FieldLabel('Name'),
                TextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: _error == null
                      ? null
                      : (_) => setState(() => _error = null),
                  decoration: const InputDecoration(hintText: 'Your name'),
                ),
                const SizedBox(height: Spacing.md),
                _FieldLabel('Phone'),
                TextField(
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saving ? null : _save(),
                  onChanged: _error == null
                      ? null
                      : (_) => setState(() => _error = null),
                  decoration: const InputDecoration(hintText: '0712 345 678'),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Signed in as ${p.email ?? '—'} · ${p.isAdmin ? 'administrator' : 'viewer'}'
                      .toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                PrimaryButton(
                  label: _saving ? 'Saving…' : 'Save changes',
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton(
                  onPressed: _changePassword,
                  child: const Text('Change password'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),

        const SectionHeader('Billing account'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.companyName ?? '—', style: theme.textTheme.titleSmall),
                if (p.companyAddress != null ||
                    p.companyEmail != null ||
                    p.companyPhone != null ||
                    p.taxId != null)
                  const SizedBox(height: Spacing.xs),
                if (p.companyAddress != null)
                  Text(p.companyAddress!, style: theme.textTheme.bodySmall),
                if (p.companyEmail != null)
                  Text(p.companyEmail!, style: theme.textTheme.bodySmall),
                if (p.companyPhone != null)
                  Text(p.companyPhone!, style: theme.textTheme.bodySmall),
                if (p.taxId != null)
                  Text('TIN: ${p.taxId}', style: theme.textTheme.bodySmall),
                const SizedBox(height: Spacing.sm),
                Text(
                  'To change these details, contact your service provider.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.xl),
      ],
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
