import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Self-registration: prove ownership of the email, then set a password.
///
/// Two entry points converge here:
///   * from sign-in, when the backend answered 449 — a code has already been
///     sent, so we open straight on the code step;
///   * from the "first time here" link, where we request the code ourselves.
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
    for (final c in [_email, _otp, _name, _password, _confirm, _phone, _company]) {
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
      final hasAccount =
          await ref.read(authServiceProvider).requestOtp(_email.text);
      if (!mounted) return;

      if (hasAccount) {
        // Already registered — sending them onward beats a dead end.
        setState(() => _error =
            'That address already has an account. Please sign in instead.');
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
      await ref.read(sessionControllerProvider).register(
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == _Step.requestCode
            ? 'Set up your account'
            : 'Verify and continue'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _step == _Step.requestCode
                  ? _buildRequestStep(context)
                  : _buildDetailsStep(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestStep(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _emailKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the email address your service provider has on file. '
            "We'll send a 6-digit code to confirm it's you.",
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.lg),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          TextFormField(
            controller: _email,
            enabled: !_submitting,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _submitting ? null : _requestCode,
            child: _submitting
                ? const _ButtonSpinner()
                : const Text('Send code'),
          ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice != null) ...[
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: Radii.card,
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 20, color: theme.colorScheme.onSecondaryContainer),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      _notice!,
                      style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          TextFormField(
            controller: _otp,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(letterSpacing: 8, fontSize: 20),
            decoration: InputDecoration(
              labelText: 'Verification code',
              counterText: '',
              prefixIcon: const Icon(Icons.pin_outlined),
              errorText: _otpError,
            ),
            validator: (v) => (v == null || v.trim().length != 6)
                ? 'Enter the 6-digit code'
                : null,
          ),
          const SizedBox(height: Spacing.md),

          TextFormField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter your name'
                : null,
          ),
          const SizedBox(height: Spacing.md),

          TextFormField(
            controller: _phone,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: Spacing.md),

          TextFormField(
            controller: _company,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Company (optional)',
              prefixIcon: Icon(Icons.business_outlined),
              helperText: 'Used only if we are creating a new account for you',
            ),
          ),
          const SizedBox(height: Spacing.md),

          TextFormField(
            controller: _password,
            enabled: !_submitting,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
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

          TextFormField(
            controller: _confirm,
            enabled: !_submitting,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) =>
                v != _password.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: Spacing.lg),

          FilledButton(
            onPressed: _submitting ? null : _register,
            child: _submitting
                ? const _ButtonSpinner()
                : const Text('Create account'),
          ),
          TextButton(
            onPressed: _submitting ? null : _requestCode,
            child: const Text('Resend code'),
          ),
        ],
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

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
