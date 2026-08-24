import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../crm/crm_ui.dart'
    show CrmAsyncView, CrmDetailRow, CrmField, CrmSheet, showCrmSheet;
import 'admin_providers.dart';

/// The signed-in person's own sign-in security.
///
/// Self-service: `/auth/2fa/*` is gated on being authenticated and nothing
/// else, so there is no permission on this screen — every staff account can
/// (and should) manage its own second factor. It matters more here than on
/// the web: the phone is the device most likely to be lost, and the person
/// holding it needs to be able to check, turn on, or revoke the factor from
/// the device they still have.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(twoFactorStatusProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Account', title: 'Security'),
      body: CrmAsyncView(
        value: status,
        errorTitle: 'Could not load your security settings',
        onRetry: () => ref.invalidate(twoFactorStatusProvider),
        builder: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(twoFactorStatusProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              Spacing.md,
              Spacing.xl,
            ),
            children: [
              const SectionHeader('Two-factor authentication'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Authenticator app',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          StatusChip(data.enabled ? 'active' : 'off'),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        data.enabled
                            ? 'Signing in needs your password and a six-digit '
                                  'code from your authenticator app.'
                            : 'Signing in needs only your password. Add a '
                                  'code from an authenticator app and a '
                                  'stolen password stops being enough.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (data.enabled && data.recoveryCodesRemaining != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.md),
                          child: CrmDetailRow(
                            'Recovery codes',
                            '${Formatting.integer(data.recoveryCodesRemaining)} '
                                'unused',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (data.recoveryCodesLow) ...[
                const SizedBox(height: Spacing.md),
                ErrorBanner(
                  message: data.recoveryCodesRemaining == 0
                      ? 'No recovery codes left. Lose the phone and you lose '
                            'the account — generate a new set now.'
                      : 'Only '
                            '${Formatting.integer(data.recoveryCodesRemaining)} '
                            'recovery code'
                            '${data.recoveryCodesRemaining == 1 ? '' : 's'} '
                            'left. Generate a new set.',
                ),
              ],
              const SizedBox(height: Spacing.lg),
              if (!data.enabled)
                PrimaryButton(
                  label: 'Turn on two-factor',
                  icon: Icons.lock_outline_rounded,
                  onPressed: () => _startSetup(context, ref),
                )
              else ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Generate new recovery codes'),
                  onPressed: () => _regenerate(context, ref),
                ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  icon: Icon(
                    Icons.lock_open_outlined,
                    size: 18,
                    color: scheme.error,
                  ),
                  label: Text(
                    'Turn off two-factor',
                    style: TextStyle(color: scheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: scheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  onPressed: () => _disable(context, ref),
                ),
              ],
              const SizedBox(height: Spacing.lg),
              Text(
                'Recovery codes are the way back in if this phone is lost or '
                'wiped. Keep them somewhere that is not this phone.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enable → confirm → recovery codes, in that order. `POST /auth/2fa/enable`
  /// only mints a pending secret; nothing about sign-in changes unless the
  /// confirm step accepts a code, so abandoning halfway is safe.
  Future<void> _startSetup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final TwoFactorSetup setup;
    try {
      setup = await ref.read(adminServiceProvider).enableTwoFactor();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      ref.invalidate(twoFactorStatusProvider);
      return;
    }
    if (!context.mounted) return;

    final codes = await showCrmSheet<List<String>>(
      context: context,
      builder: (_) => _SetupSheet(setup: setup),
    );
    ref.invalidate(twoFactorStatusProvider);
    if (codes == null || codes.isEmpty || !context.mounted) return;

    await _showRecoveryCodes(context, codes, isNew: true);
  }

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final password = await _askPassword(
      context,
      title: 'Generate new recovery codes',
      note: 'Your current codes stop working the moment the new ones appear.',
      verb: 'Generate',
    );
    if (password == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final codes = await ref
          .read(adminServiceProvider)
          .regenerateRecoveryCodes(password);
      ref.invalidate(twoFactorStatusProvider);
      if (!context.mounted) return;
      await _showRecoveryCodes(context, codes, isNew: false);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Turning the second factor off is the destructive one, and the API
  /// insists on the account password for exactly that reason — a found,
  /// unlocked phone must not be able to strip it.
  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final password = await _askPassword(
      context,
      title: 'Turn off two-factor',
      note:
          'Your password alone will get into this account again, from any '
          'device. Your recovery codes are destroyed.',
      verb: 'Turn off',
      destructive: true,
    );
    if (password == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await ref
          .read(adminServiceProvider)
          .disableTwoFactor(password);
      ref.invalidate(twoFactorStatusProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(message ?? 'Two-factor authentication is off.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<String?> _askPassword(
    BuildContext context, {
    required String title,
    required String note,
    required String verb,
    bool destructive = false,
  }) => showCrmSheet<String>(
    context: context,
    builder: (_) => _PasswordSheet(
      title: title,
      note: note,
      verb: verb,
      destructive: destructive,
    ),
  );

  Future<void> _showRecoveryCodes(
    BuildContext context,
    List<String> codes, {
    required bool isNew,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The one sheet in the app that cannot be dismissed by accident: these
    // codes exist only in this widget's memory. The server keeps hashes.
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => _RecoveryCodesSheet(codes: codes, isNew: isNew),
  );
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

/// The enable handshake, without a QR code.
///
/// The server hands back a base-32 secret and the `otpauth://` URI a QR code
/// would have encoded. Rendering that as a QR would mean a new dependency, so
/// this screen gives the authenticator's *manual entry* path instead: the key
/// as selectable, copyable text plus the account and issuer the QR would have
/// carried, which is everything an app asks for on its "enter a setup key"
/// screen.
class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet({required this.setup});

  final TwoFactorSetup setup;

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final setup = widget.setup;
    final ready = _code.text.trim().length == 6;

    return CrmSheet(
      eyebrow: 'Security',
      title: 'Set up two-factor',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'In your authenticator app — Google Authenticator, Authy, '
          '1Password, whichever you use — choose to add an account by '
          'entering a setup key, then type in the key below.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SETUP KEY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                // Selectable so it can be copied by hand as well as by the
                // button, and spaced in fours so it can be read aloud or
                // typed without losing your place.
                SelectableText(
                  _spaced(setup.secret),
                  style: Type.mono(16, tracking: 0.06, color: scheme.onSurface),
                ),
                const SizedBox(height: Spacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy key'),
                    onPressed: () => _copy(setup.secret, 'Setup key copied.'),
                  ),
                ),
                const Divider(height: Spacing.lg),
                if (setup.account != null)
                  CrmDetailRow('Account', setup.account!),
                if (setup.issuer != null) CrmDetailRow('Issuer', setup.issuer!),
                const CrmDetailRow('Type', 'Time-based, 6 digits'),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Code from the app',
          child: TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofocus: false,
            maxLength: 6,
            style: Type.mono(20, tracking: 0.3, color: scheme.onSurface),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '000000',
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: 'Confirm and turn on',
          busy: _busy,
          onPressed: !ready || _busy ? null : _confirm,
        ),
        const SizedBox(height: Spacing.sm),
        TextButton(
          onPressed: _busy
              ? null
              : () => _copy(
                  widget.setup.otpauthUrl,
                  'Setup link copied — paste it into your authenticator or '
                  'password manager.',
                ),
          child: const Text('Copy the setup link instead'),
        ),
      ],
    );
  }

  Future<void> _copy(String value, String message) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: value));
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final codes = await ref
          .read(adminServiceProvider)
          .confirmTwoFactor(_code.text.trim());
      navigator.pop(codes);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  /// `JBSWY3DPEHPK3PXP` → `JBSW Y3DP EHPK 3PXP`. The copy button still puts
  /// the unspaced key on the clipboard, which is what apps expect.
  static String _spaced(String secret) {
    final buffer = StringBuffer();
    for (var i = 0; i < secret.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(secret.substring(i, math.min(i + 4, secret.length)));
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// Recovery codes
// ---------------------------------------------------------------------------

/// Shown exactly once, because that is all the server can offer: it stores
/// hashes of these and cannot produce them again.
class _RecoveryCodesSheet extends StatelessWidget {
  const _RecoveryCodesSheet({required this.codes, required this.isNew});

  final List<String> codes;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      // A stray back-swipe here costs the codes for good.
      canPop: false,
      child: CrmSheet(
        eyebrow: 'Security',
        title: isNew ? 'Two-factor is on' : 'New recovery codes',
        children: [
          const ErrorBanner(
            message: 'Save these now — they will not be shown again.',
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Each code signs you in once if you lose your authenticator app. '
            'Keep them somewhere other than this phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: SelectableText(
                codes.join('\n'),
                style: Type.mono(15, tracking: 0.04, color: scheme.onSurface),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copy all codes'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    '${Formatting.integer(codes.length)} recovery codes '
                    'copied. Paste them somewhere safe.',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: Spacing.md),
          PrimaryButton(
            label: 'I have saved them',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Password confirmation
// ---------------------------------------------------------------------------

/// `POST /auth/2fa/disable` and the recovery-code regeneration both require
/// the account password. This sheet is that requirement, and — for the
/// destructive one — the confirmation step as well: the warning and the verb
/// on the button are here rather than in a dialog before it, so there is one
/// place to read what is about to happen and one place to stop.
class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({
    required this.title,
    required this.note,
    required this.verb,
    required this.destructive,
  });

  final String title;
  final String note;
  final String verb;
  final bool destructive;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _password = TextEditingController();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = _password.text.isNotEmpty;

    return CrmSheet(
      eyebrow: 'Security',
      title: widget.title,
      children: [
        Text(
          widget.note,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: widget.destructive ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Your password',
          child: TextField(
            controller: _password,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'The password you sign in with',
              suffixIcon: IconButton(
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                ),
                tooltip: _visible ? 'Hide' : 'Show',
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
            onSubmitted: (_) {
              if (ready) Navigator.of(context).pop(_password.text);
            },
          ),
        ),
        const SizedBox(height: Spacing.lg),
        if (widget.destructive)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: ready
                ? () => Navigator.of(context).pop(_password.text)
                : null,
            child: Text(widget.verb),
          )
        else
          PrimaryButton(
            label: widget.verb,
            onPressed: ready
                ? () => Navigator.of(context).pop(_password.text)
                : null,
          ),
      ],
    );
  }
}
