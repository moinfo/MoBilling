import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// The second step of signing in, when the account has an authenticator.
///
/// A sheet rather than a screen: the password was accepted, so this is the
/// same sign-in still in progress, and the ink panel behind it says so.
/// Nothing here can be dismissed into a half-signed-in state — the session
/// only exists once the server accepts a code.
///
/// The recovery-code path is deliberately as reachable as the digits: the
/// phone that holds the authenticator is often the phone that was lost, and
/// a recovery code is the only way back in from a new one.
class TwoFactorLoginSheet extends ConsumerStatefulWidget {
  const TwoFactorLoginSheet({
    super.key,
    required this.challengeId,
    this.message,
  });

  final String challengeId;
  final String? message;

  /// Returns true once the session is live; the router does the rest.
  static Future<bool> show(
    BuildContext context, {
    required String challengeId,
    String? message,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        // The sign-in is half-finished; dismissing it by accident would look
        // like the password was wrong.
        isDismissible: false,
        enableDrag: false,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) =>
            TwoFactorLoginSheet(challengeId: challengeId, message: message),
      ) ??
      false;

  @override
  ConsumerState<TwoFactorLoginSheet> createState() =>
      _TwoFactorLoginSheetState();
}

class _TwoFactorLoginSheetState extends ConsumerState<TwoFactorLoginSheet> {
  final _code = TextEditingController();
  bool _useRecovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _ready =>
      _useRecovery ? _code.text.trim().length >= 8 : _code.text.length == 6;

  Future<void> _submit() async {
    if (!_ready) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entered = _code.text.trim();
      await ref
          .read(sessionControllerProvider)
          .completeTwoFactorLogin(
            challengeId: widget.challengeId,
            code: _useRecovery ? null : entered,
            recoveryCode: _useRecovery ? entered : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('code') ??
            e.errorFor('recovery_code') ??
            // An expired challenge cannot be retried here — the only way on
            // is to start the sign-in again, so say that.
            e.errorFor('challenge_id') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
          sheetBottomInset(context) + Spacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'TWO-FACTOR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                _useRecovery ? 'Use a recovery code' : 'Enter your code',
                style: Type.display(22, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                _useRecovery
                    ? 'One of the codes you saved when you turned on '
                          'two-factor. Each one works once.'
                    : widget.message ??
                          'The 6-digit code from your authenticator app.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: Spacing.md),
              ],
              TextField(
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                keyboardType: _useRecovery
                    ? TextInputType.text
                    : TextInputType.number,
                maxLength: _useRecovery ? 32 : 6,
                inputFormatters: _useRecovery
                    ? null
                    : [FilteringTextInputFormatter.digitsOnly],
                style: Type.mono(_useRecovery ? 16 : 22, tracking: 0.3),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: _useRecovery ? 'recovery code' : '000000',
                ),
              ),
              const SizedBox(height: Spacing.md),
              PrimaryButton(
                label: _busy ? 'Checking…' : 'Verify and sign in',
                busy: _busy,
                onPressed: _busy || !_ready ? null : _submit,
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _useRecovery = !_useRecovery;
                        _code.clear();
                        _error = null;
                      }),
                child: Text(
                  _useRecovery
                      ? 'Use my authenticator instead'
                      : 'I don’t have my authenticator',
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel and sign in again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
