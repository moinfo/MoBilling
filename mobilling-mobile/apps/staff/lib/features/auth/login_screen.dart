import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/theme_mode.dart';
import '../../providers.dart';
import '../portal/portal_routes.dart';
import 'biometrics.dart';

/// The single sign-in for all three audiences.
///
/// `/auth/login` resolves the identifier against the staff `User` table, then
/// `ClientUser`, then falls back to matching a client with no portal account
/// yet — which answers 449 and means "we emailed a code", not "wrong
/// password". Nothing here decides *where* a user lands: the router reads the
/// resulting session and picks the portal, staff or admin shell.
///
/// Layout follows the web sign-in (design handoff §2) folded for a phone:
/// the ink brand panel on top, and the form card pulled up over its bottom
/// edge the way the landing page's stat strip overlaps the hero.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  String? _formError;

  /// Device biometrics exist and are enrolled — decides whether the
  /// fingerprint control and the enable prompt appear at all.
  bool _biometricsAvailable = false;
  String _biometricLabel = 'fingerprint';
  bool _unlocking = false;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    _probeBiometrics();
  }

  Future<void> _probeBiometrics() async {
    final bio = ref.read(biometricsProvider);
    final available = await bio.available;
    final label = available ? await bio.label : 'fingerprint';
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _biometricLabel = label;
    });
    // A locked session opens straight onto the system prompt — the button
    // stays for a retry after a cancel.
    if (available &&
        !_autoPrompted &&
        ref.read(sessionControllerProvider).status == SessionStatus.locked) {
      _autoPrompted = true;
      await _unlockWithBiometrics();
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_unlocking) return;
    setState(() {
      _unlocking = true;
      _formError = null;
    });
    try {
      final ok = await ref
          .read(biometricsProvider)
          .authenticate('Unlock MoBilling');
      if (!ok || !mounted) return;
      await ref.read(sessionControllerProvider).unlock();
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  /// The fingerprint button is always on screen; what it does depends on
  /// whether there is a locked session to open.
  Future<void> _biometricTap() async {
    final status = ref.read(sessionControllerProvider).status;
    if (status == SessionStatus.locked && _biometricsAvailable) {
      await _unlockWithBiometrics();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(!_biometricsAvailable
          ? 'No fingerprint or Face ID is set up on this phone.'
          : 'Sign in with your password first — you’ll be offered '
              '$_biometricLabel sign-in for next time.'),
    ));
  }

  /// Once, after a password sign-in on a capable device: offer to lock the
  /// session behind biometrics from now on.
  Future<void> _offerBiometrics() async {
    final session = ref.read(sessionControllerProvider);
    if (!_biometricsAvailable || await session.biometricLockEnabled()) return;
    if (!mounted) return;
    final label = _biometricLabel == 'Face ID' ? 'Face ID' : 'your fingerprint';
    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          _biometricLabel == 'Face ID'
              ? Icons.face_outlined
              : Icons.fingerprint,
        ),
        title: Text('Sign in with $label next time?'),
        content: const Text(
          'You stay signed in, and MoBilling asks the device to confirm it is you before opening.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (enable ?? false) await session.setBiometricLock(true);
  }

  /// How far the form card rides up over the ink panel.
  static const double _overlap = 28;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      final session = ref.read(sessionControllerProvider);
      final outcome = await session.login(
        identifier: _identifier.text,
        password: _password.text,
      );

      if (!mounted) return;

      switch (outcome) {
        case LoginSucceeded():
          // No navigation here — the router redirects off the session, and
          // picks the shell from user_type + role.
          await _offerBiometrics();
        case LoginNeedsOtp(:final challenge):
          // 449: a known client without a portal login. The code is already
          // sent, so go straight to the code step.
          context.push(
            PortalRoutes.register,
            extra: RegisterArgs(
              email: _identifier.text.trim(),
              clientName: challenge.clientName,
            ),
          );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.errorFor('identifier') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      // The ink panel sits under the status bar, so its icons must be white.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Brand panel ─────────────────────────────────────────────
              InkPanel(
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg,
                  topInset + Spacing.lg,
                  Spacing.lg,
                  Spacing.xl + _overlap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wordmark left, theme toggle right — the handoff's header
                    // row, so the choice is reachable before signing in.
                    const Reveal(
                      child: Row(
                        children: [
                          Expanded(child: Wordmark(size: 34, onInk: true)),
                          ThemeToggle(onInk: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    const Reveal(
                      delay: Duration(milliseconds: 80),
                      child: EyebrowPill('Built for East Africa'),
                    ),
                    const SizedBox(height: Spacing.md),
                    Reveal(
                      delay: const Duration(milliseconds: 160),
                      child: Text(
                        'Welcome back',
                        style: Type.display(38, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Reveal(
                      delay: const Duration(milliseconds: 240),
                      child: Text(
                        // One door for three audiences. Saying so up front stops
                        // a client wondering whether they downloaded the staff
                        // app.
                        'Clients, staff and administrators all sign in here.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: InkPanel.bodyText,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Form card, overlapping the panel ────────────────────────
              Transform.translate(
                offset: const Offset(0, -_overlap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Reveal(
                    delay: const Duration(milliseconds: 300),
                    child: _FormCard(
                      formKey: _formKey,
                      identifier: _identifier,
                      password: _password,
                      submitting: _submitting,
                      obscure: _obscure,
                      error: _formError,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmit: _submit,
                      onEdited: _formError == null
                          ? null
                          : () => setState(() => _formError = null),
                      // Always shown: the button explains itself when there is
                      // nothing to unlock yet.
                      biometric: _BiometricAction(
                        label: _biometricLabel,
                        busy: _unlocking,
                        onPressed: _biometricTap,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Below the card ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Reveal(
                  delay: const Duration(milliseconds: 420),
                  child: Column(
                    children: [
                      // The 449 path is invisible otherwise: a client who has
                      // never set a password has no way to guess that signing
                      // in *is* how they get an account.
                      Text.rich(
                        TextSpan(
                          text: 'No account yet? ',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  'Sign in with the email on your invoice and we’ll send you a code.',
                              style: TextStyle(color: scheme.onSurface),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Text(
                            'PROTECTED BY 2FA AND ROLE-BASED ACCESS',
                            style: Type.mono(
                              10.5,
                              weight: FontWeight.w400,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sign-in form on its raised card.
class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.formKey,
    required this.identifier,
    required this.password,
    required this.submitting,
    required this.obscure,
    required this.error,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onEdited,
    this.biometric,
  });

  /// Present only while a biometric-locked session is waiting.
  final _BiometricAction? biometric;

  final GlobalKey<FormState> formKey;
  final TextEditingController identifier;
  final TextEditingController password;
  final bool submitting;
  final bool obscure;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback? onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: 0.28),
            blurRadius: 44,
            offset: const Offset(0, 24),
            spreadRadius: -30,
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                ErrorBanner(message: error!),
                const SizedBox(height: Spacing.md),
              ],
              FieldLabel('Email or phone'),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: identifier,
                enabled: !submitting,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                onChanged: (_) => onEdited?.call(),
                decoration: _fieldDecoration(
                  context,
                  hint: 'you@company.com or 0712 345 678',
                  icon: Icons.alternate_email,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter your email or phone'
                    : null,
              ),
              const SizedBox(height: Spacing.md),
              FieldLabel('Password'),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: password,
                enabled: !submitting,
                obscureText: obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.go,
                onChanged: (_) => onEdited?.call(),
                onFieldSubmitted: (_) => onSubmit(),
                decoration: _fieldDecoration(
                  context,
                  hint: 'Your password',
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              const SizedBox(height: Spacing.lg),
              PrimaryButton(
                label: submitting ? 'Signing in…' : 'Sign in',
                busy: submitting,
                onPressed: submitting ? null : onSubmit,
              ),
              if (biometric != null) ...[
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                      ),
                      child: Text(
                        'OR',
                        style: Type.mono(11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                _FingerprintButton(action: biometric!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The handoff's field: 52px, radius 12, leading icon, blue focus ring.
  static InputDecoration _fieldDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      prefixIcon: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      suffixIcon: suffix,
      filled: true,
      fillColor: scheme.brightness == Brightness.light
          ? Colors.white
          : scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      border: border(scheme.outline),
      enabledBorder: border(scheme.outline),
      focusedBorder: border(scheme.primary, width: 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, width: 2),
    );
  }
}


/// What the fingerprint control needs from the screen.
class _BiometricAction {
  const _BiometricAction({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;
}

/// Full-width outlined action: the sensor icon in brand green, as the
/// handoff's secondary button. Large because it is the one-tap path.
class _FingerprintButton extends StatelessWidget {
  const _FingerprintButton({required this.action});

  final _BiometricAction action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFace = action.label == 'Face ID';
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: action.busy ? null : action.onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          side: BorderSide(color: scheme.outline),
        ),
        icon: action.busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fingerprint, size: 24, color: Brand.settled),
        label: Text(
          isFace ? 'Sign in with Face ID' : 'Sign in with fingerprint',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
