import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../providers.dart';
import '../portal/portal_routes.dart';

/// The single sign-in for all three audiences.
///
/// `/auth/login` resolves the identifier against the staff `User` table, then
/// `ClientUser`, then falls back to matching a client with no portal account
/// yet — which answers 449 and means "we emailed a code", not "wrong
/// password". Nothing here decides *where* a user lands: the router reads the
/// resulting session and picks the portal, staff or admin shell.
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
          break;
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
      setState(() =>
          _formError = e.errorFor('identifier') ?? e.message);
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
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 64),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      AppConfig.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    // One door for three audiences. Saying so up front stops
                    // clients wondering whether they downloaded the staff app.
                    Text(
                      'One sign-in for clients, staff and administrators.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                      decoration: const InputDecoration(
                        labelText: 'Email or phone',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your email or phone'
                          : null,
                    ),
                    const SizedBox(height: Spacing.md),
                    TextFormField(
                      controller: _password,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
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
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: Spacing.lg),
                    // The 449 path is invisible otherwise: a client who has
                    // never set a password has no way to guess that signing
                    // in *is* how they get an account.
                    Text(
                      'No account yet? Enter the email address on your '
                      'invoices and we’ll send you a code.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
