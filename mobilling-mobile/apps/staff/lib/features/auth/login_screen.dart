import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../config/app_config.dart';
import '../../providers.dart';

/// Staff sign-in.
///
/// The shared /auth/login endpoint resolves staff users first but will also
/// happily sign in a client portal user — this app is for staff only, so a
/// `user_type: client` result is rejected and the session torn down rather
/// than presenting a client with an app full of 403s.
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
        case LoginSucceeded(session: final s):
          if (s.user.userType != UserType.tenant) {
            // A client credential — valid, but not for this app.
            await ref.read(sessionControllerProvider).logout();
            if (mounted) {
              setState(() => _formError =
                  'This is the staff app — please use the MoBilling client app instead.');
            }
          }
        case LoginNeedsOtp():
          // The OTP handshake only fires for client self-registration.
          setState(() => _formError =
              'This account is not a staff account. Use the client app to register.');
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
            padding: const EdgeInsets.all(Spacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.business_center_rounded,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: Spacing.md),
                    Text(AppConfig.appName,
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center),
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
