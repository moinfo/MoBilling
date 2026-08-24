import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// The payoff for deferring teardown on a 401.
///
/// Rather than discarding the screen the user was on, we overlay this and ask
/// only for the password — the identifier is already known. Signing back in
/// swaps the token underneath and the interrupted screen carries on with
/// whatever was typed into it.
///
/// Dismissing means a full sign-out, since the old token is dead either way.
class SessionExpiredSheet extends ConsumerStatefulWidget {
  const SessionExpiredSheet({super.key});

  /// Presented non-dismissibly: the session is unusable until resolved one way
  /// or the other, and a stray backdrop tap should not decide that.
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => const SessionExpiredSheet(),
  );

  @override
  ConsumerState<SessionExpiredSheet> createState() =>
      _SessionExpiredSheetState();
}

class _SessionExpiredSheetState extends ConsumerState<SessionExpiredSheet> {
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _reauthenticate() async {
    final session = ref.read(sessionControllerProvider);
    // Phone-only accounts exist, so fall back rather than assuming an email.
    final identifier = session.user?.email ?? session.user?.phone;

    if (identifier == null || identifier.isEmpty) {
      await _signOut();
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final outcome = await session.login(
        identifier: identifier,
        password: _password.text,
      );

      if (!mounted) return;

      if (outcome is LoginSucceeded) {
        Navigator.of(context).pop();
      } else {
        // A 449 here would mean the portal account no longer exists at all.
        setState(
          () => _error =
              'This account is no longer active. Please sign in again.',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('identifier') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(sessionControllerProvider).abandonExpiredSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final identifier = user?.email ?? user?.phone ?? '';

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        // Lift clear of the keyboard, otherwise the field hides behind it.
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_clock_outlined,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Session ended',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            identifier.isEmpty
                ? 'Sign in again to continue. Your work on this screen is kept.'
                : 'Sign in again as $identifier to continue. '
                      'Your work on this screen is kept.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.lg),

          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          TextField(
            controller: _password,
            enabled: !_submitting,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _reauthenticate(),
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: Spacing.md),

          FilledButton(
            onPressed: _submitting ? null : _reauthenticate,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          TextButton(
            onPressed: _submitting ? null : _signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
