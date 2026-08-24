import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';

/// Recover a forgotten password, for staff and clients alike.
///
/// Three steps on one screen rather than three screens: the identifier never
/// changes between them, and showing it stay put is what makes the code feel
/// like it belongs to the address it was sent to. The step only advances when
/// the server agrees, so a wrong code is caught while it is still the only
/// thing being asked for.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.identifier});

  /// Prefilled from whatever was typed on the sign-in form.
  final String? identifier;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

enum _Step { identify, code, password }

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _identifier = TextEditingController(text: widget.identifier ?? '');
  final _otp = TextEditingController();
  final _password = TextEditingController();

  _Step _step = _Step.identify;
  String? _channel;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  /// The server's own words about where the code went — more use than
  /// anything this screen could invent, since only it knows the address.
  String? _sentMessage;

  @override
  void dispose() {
    _identifier.dispose();
    _otp.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<String?> Function() action,
    VoidCallback onOk,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() => _sentMessage = message);
      onOk();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('identifier') ??
            e.errorFor('otp') ??
            e.errorFor('password') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendCode() => _run(
    () => ref
        .read(authServiceProvider)
        .requestPasswordReset(identifier: _identifier.text, channel: _channel),
    () => setState(() => _step = _Step.code),
  );

  void _verifyCode() => _run(
    () => ref
        .read(authServiceProvider)
        .verifyPasswordResetOtp(
          identifier: _identifier.text,
          otp: _otp.text.trim(),
        ),
    () => setState(() => _step = _Step.password),
  );

  void _setPassword() => _run(
    () => ref
        .read(authServiceProvider)
        .resetPassword(
          identifier: _identifier.text,
          otp: _otp.text.trim(),
          password: _password.text,
        ),
    () {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _sentMessage ?? 'Password changed. Sign in with the new one.',
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkPanel(
                padding: EdgeInsets.fromLTRB(
                  Spacing.lg,
                  topInset + Spacing.sm,
                  Spacing.lg,
                  Spacing.xl + 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkActionButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to sign in',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(switch (_step) {
                      _Step.identify => 'Forgot your password?',
                      _Step.code => 'Check your messages',
                      _Step.password => 'Choose a new password',
                    }, style: Type.display(32, color: Colors.white)),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      switch (_step) {
                        _Step.identify =>
                          'Enter the email or phone you sign in with and '
                              'we’ll send you a six-digit code.',
                        _Step.code =>
                          _sentMessage ??
                              'Enter the six-digit code we just sent.',
                        _Step.password =>
                          'At least eight characters. You’ll sign in with '
                              'this from now on.',
                      },
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: InkPanel.bodyText,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Container(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: Spacing.md),
                        ],
                        ..._stepFields(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepFields() => switch (_step) {
    _Step.identify => [
      const FieldLabel('Email or phone'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _identifier,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'you@company.com or 0712 345 678',
          prefixIcon: Icon(Icons.alternate_email, size: 20),
        ),
      ),
      const SizedBox(height: Spacing.md),
      const FieldLabel('Send the code by'),
      const SizedBox(height: Spacing.sm),
      // The server picks sensibly when this is left alone; the choice is
      // here because a client with no email still has WhatsApp.
      SegmentedButton<String?>(
        segments: const [
          ButtonSegment(value: null, label: Text('Either')),
          ButtonSegment(value: 'email', label: Text('Email')),
          ButtonSegment(value: 'whatsapp', label: Text('WhatsApp')),
        ],
        selected: {_channel},
        showSelectedIcon: false,
        onSelectionChanged: _busy
            ? null
            : (s) => setState(() => _channel = s.first),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _busy ? 'Sending…' : 'Send the code',
        busy: _busy,
        onPressed: _busy || _identifier.text.trim().isEmpty ? null : _sendCode,
      ),
    ],
    _Step.code => [
      const FieldLabel('Six-digit code'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _otp,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: Type.mono(22, tracking: 0.3),
        decoration: const InputDecoration(counterText: '', hintText: '000000'),
      ),
      const SizedBox(height: Spacing.md),
      PrimaryButton(
        label: _busy ? 'Checking…' : 'Check the code',
        busy: _busy,
        onPressed: _busy || _otp.text.trim().length < 6 ? null : _verifyCode,
      ),
      const SizedBox(height: Spacing.sm),
      TextButton(
        onPressed: _busy ? null : _sendCode,
        child: const Text('Send it again'),
      ),
    ],
    _Step.password => [
      const FieldLabel('New password'),
      const SizedBox(height: Spacing.sm),
      TextField(
        controller: _password,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        obscureText: _obscure,
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
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _busy ? 'Saving…' : 'Save and sign in',
        busy: _busy,
        onPressed: _busy || _password.text.length < 8 ? null : _setPassword,
      ),
    ],
  };
}
