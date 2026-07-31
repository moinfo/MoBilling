import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../providers.dart';
import '../../router.dart';

/// Sign-in with an email address or a phone number.
///
/// The backend resolves the identifier in three steps — staff user, portal
/// user, then a client with no portal account yet — so a "wrong" password can
/// legitimately produce an OTP challenge rather than a failure. That case is
/// handled below as a normal outcome, not an error.
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
  String? _identifierError;
  String? _passwordError;

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
      _identifierError = null;
      _passwordError = null;
    });

    try {
      final outcome = await ref.read(sessionControllerProvider).login(
            identifier: _identifier.text,
            password: _password.text,
          );

      if (!mounted) return;

      switch (outcome) {
        case LoginSucceeded():
          // No navigation here — the router redirects off the session status.
          break;
        case LoginNeedsOtp(:final challenge):
          context.push(
            Routes.register,
            extra: RegisterArgs(
              email: _identifier.text.trim(),
              clientName: challenge.clientName,
            ),
          );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // 422 binds back onto the offending fields; anything else is a banner.
        _identifierError = e.errorFor('identifier') ?? e.errorFor('email');
        _passwordError = e.errorFor('password');
        _formError = (_identifierError == null && _passwordError == null)
            ? e.message
            : null;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      AppConfig.appName,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Client area',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.xl),

                    if (_formError != null) ...[
                      ErrorBanner(message: _formError!),
                      const SizedBox(height: Spacing.md),
                    ],

                    TextFormField(
                      controller: _identifier,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Email or phone',
                        prefixIcon: const Icon(Icons.person_outline),
                        errorText: _identifierError,
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Enter your email address or phone number'
                              : null,
                    ),
                    const SizedBox(height: Spacing.md),

                    TextFormField(
                      controller: _password,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: _passwordError,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: Spacing.lg),

                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: Spacing.md),

                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => context.push(Routes.register),
                      child: const Text("First time here? Set up your account"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
