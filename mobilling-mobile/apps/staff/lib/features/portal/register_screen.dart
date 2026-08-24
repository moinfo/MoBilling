import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/theme_mode.dart';
import '../../providers.dart';

/// Self-registration: prove ownership of the email, then set a password.
///
/// Two entry points converge here:
///   * from sign-in, when the backend answered 449 — a code has already been
///     sent, so we open straight on the code step;
///   * from the "first time here" link, where we request the code ourselves.
///
/// Composed like the sign-in screen it follows: the ink brand panel on top
/// carrying the step's headline, and the form card pulled up over its
/// bottom edge.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.email, this.clientName});

  /// Pre-verified address carried over from the 449 handshake.
  final String? email;

  /// Company the backend matched, shown as reassurance.
  final String? clientName;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

enum _Step { requestCode, enterDetails }

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailKey = GlobalKey<FormState>();
  final _detailsKey = GlobalKey<FormState>();

  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();

  late _Step _step;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;
  String? _otpError;
  String? _notice;

  /// How far the form card rides up over the ink panel.
  static const double _overlap = 28;

  @override
  void initState() {
    super.initState();
    // Arriving from a 449 means the code is already in the user's inbox.
    final prefilled = widget.email;
    if (prefilled != null && prefilled.isNotEmpty) {
      _email.text = prefilled;
      _step = _Step.enterDetails;
      _notice = widget.clientName == null
          ? 'We sent a 6-digit code to $prefilled.'
          : 'We sent a 6-digit code to $prefilled for ${widget.clientName}.';
    } else {
      _step = _Step.requestCode;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _email,
      _otp,
      _name,
      _password,
      _confirm,
      _phone,
      _company,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_emailKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final hasAccount = await ref
          .read(authServiceProvider)
          .requestOtp(_email.text);
      if (!mounted) return;

      if (hasAccount) {
        // Already registered — sending them onward beats a dead end.
        setState(
          () => _error =
              'That address already has an account. Please sign in instead.',
        );
        return;
      }

      setState(() {
        _step = _Step.enterDetails;
        _notice = 'We sent a 6-digit code to ${_email.text.trim()}.';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('email') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _register() async {
    if (!_detailsKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
      _otpError = null;
    });

    try {
      await ref
          .read(sessionControllerProvider)
          .register(
            email: _email.text,
            otp: _otp.text,
            name: _name.text,
            password: _password.text,
            phone: _phone.text,
            company: _company.text,
          );
      // Success needs no navigation — the router follows the session status.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _otpError = e.errorFor('otp');
        _error = _otpError == null
            ? (e.errorFor('password') ?? e.errorFor('email') ?? e.message)
            : null;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final requesting = _step == _Step.requestCode;

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
                  topInset + Spacing.md,
                  Spacing.lg,
                  Spacing.xl + _overlap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Reveal(
                      child: Row(
                        children: [
                          if (context.canPop()) ...[
                            InkActionButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: 'Back to sign in',
                              onPressed: _submitting
                                  ? null
                                  : () => context.pop(),
                            ),
                            const SizedBox(width: Spacing.md - 2),
                          ],
                          const Expanded(
                            child: Wordmark(size: 30, onInk: true),
                          ),
                          const ThemeToggle(onInk: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.xl),
                    Reveal(
                      delay: const Duration(milliseconds: 80),
                      child: EyebrowPill(
                        requesting ? 'First time here' : 'Check your inbox',
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Reveal(
                      delay: const Duration(milliseconds: 160),
                      child: Text(
                        requesting
                            ? 'Set up your account'
                            : 'Verify and continue',
                        style: Type.display(34, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Reveal(
                      delay: const Duration(milliseconds: 240),
                      child: Text(
                        requesting
                            ? 'Enter the email address your service provider '
                                  'has on file. We’ll send a 6-digit code to '
                                  'confirm it’s you.'
                            : (_notice ??
                                  'Enter the 6-digit code from your email, '
                                      'then choose a password.'),
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
                    child: _RaisedCard(
                      child: requesting
                          ? _buildRequestStep(context)
                          : _buildDetailsStep(context),
                    ),
                  ),
                ),
              ),

              // ── Below the card ──────────────────────────────────────────
              // Outside the shell, so no bottom bar absorbs the home
              // indicator — the footer pads for it itself.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.lg + MediaQuery.paddingOf(context).bottom,
                ),
                child: Reveal(
                  delay: const Duration(milliseconds: 420),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        'PROTECTED BY 2FA AND ROLE-BASED ACCESS',
                        style: Type.mono(
                          10.5,
                          weight: FontWeight.w400,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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

  Widget _buildRequestStep(BuildContext context) {
    return Form(
      key: _emailKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          _FieldLabel('Email address'),
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.go,
            onFieldSubmitted: (_) => _submitting ? null : _requestCode(),
            decoration: const InputDecoration(
              hintText: 'you@company.com',
              prefixIcon: Icon(Icons.alternate_email, size: 20),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: _submitting ? 'Sending code…' : 'Send code',
            busy: _submitting,
            onPressed: _submitting ? null : _requestCode,
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: _submitting ? null : () => context.pop(),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _detailsKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: Spacing.md),
            ],

            _FieldLabel('Verification code'),
            TextFormField(
              controller: _otp,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.next,
              // The code is a figure, not a word: mono, tabular, spaced out
              // so six digits read as six digits.
              style: Type.mono(
                20,
                tracking: 0.4,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: Type.mono(
                  20,
                  tracking: 0.4,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
                counterText: '',
                prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                errorText: _otpError,
              ),
              validator: (v) => (v == null || v.trim().length != 6)
                  ? 'Enter the 6-digit code'
                  : null,
            ),
            const SizedBox(height: Spacing.md),

            _FieldLabel('Your name'),
            TextFormField(
              controller: _name,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: Spacing.md),

            _FieldLabel('Phone (optional)'),
            TextFormField(
              controller: _phone,
              enabled: !_submitting,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '0712 345 678'),
            ),
            const SizedBox(height: Spacing.md),

            _FieldLabel('Company (optional)'),
            TextFormField(
              controller: _company,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.organizationName],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Company name',
                helperText:
                    'Used only if we are creating a new account for you.',
              ),
            ),
            const SizedBox(height: Spacing.md),

            _FieldLabel('Password'),
            TextFormField(
              controller: _password,
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              // Mirrors the backend's `min:8`, so a weak password fails here
              // rather than after a round trip.
              validator: (v) => (v == null || v.length < 8)
                  ? 'Use at least 8 characters'
                  : null,
            ),
            const SizedBox(height: Spacing.md),

            _FieldLabel('Confirm password'),
            TextFormField(
              controller: _confirm,
              enabled: !_submitting,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.go,
              onFieldSubmitted: (_) => _submitting ? null : _register(),
              decoration: const InputDecoration(
                hintText: 'Type it again',
                prefixIcon: Icon(Icons.lock_outline, size: 20),
              ),
              validator: (v) =>
                  v != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: Spacing.lg),

            PrimaryButton(
              label: _submitting ? 'Creating account…' : 'Create account',
              busy: _submitting,
              onPressed: _submitting ? null : _register,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: _submitting ? null : _requestCode,
              child: const Text('Resend code'),
            ),
          ],
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your email address';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }
}

/// The form's paper card, raised over the ink with the sign-in card's soft
/// ink shadow so the overlap reads as depth rather than as a misalignment.
class _RaisedCard extends StatelessWidget {
  const _RaisedCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? scheme.surface,
        borderRadius: Radii.card,
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
      child: child,
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
