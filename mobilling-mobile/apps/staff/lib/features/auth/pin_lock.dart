import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobilling_auth/mobilling_auth.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

/// A local, device-only 4-digit unlock PIN — the keypad equivalent of
/// biometric lock, not a server-side sign-in credential. See
/// [TokenStore.setPin] for why it is fine to hold in the clear next to the
/// bearer token.

/// The styled 4-digit field shared by setup and unlock.
class PinCodeField extends StatelessWidget {
  const PinCodeField({
    super.key,
    required this.controller,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      obscureText: true,
      obscuringCharacter: '●',
      maxLength: 4,
      textAlign: TextAlign.center,
      style: Type.mono(24, tracking: 0.5, color: scheme.onSurface),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(counterText: '', hintText: '••••'),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Enter a new PIN, then confirm it. Returns the chosen 4-digit PIN, or null
/// if the sheet was dismissed without saving.
Future<String?> showPinSetupSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => const _PinSetupSheet(),
  );
}

class _PinSetupSheet extends StatefulWidget {
  const _PinSetupSheet();

  @override
  State<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends State<_PinSetupSheet> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _save() {
    if (_first.text.length != 4 || _second.text.length != 4) {
      setState(() => _error = 'Enter 4 digits in both fields.');
      return;
    }
    if (_first.text != _second.text) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    Navigator.of(context).pop(_first.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set a 4-digit PIN', style: theme.textTheme.titleLarge),
          const SizedBox(height: Spacing.sm),
          Text(
            'Use it to open MoBilling instead of typing your password every '
            'time. It stays on this phone only.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          FieldLabel('PIN'),
          const SizedBox(height: Spacing.sm),
          PinCodeField(controller: _first, autofocus: true),
          const SizedBox(height: Spacing.md),
          FieldLabel('Confirm PIN'),
          const SizedBox(height: Spacing.sm),
          PinCodeField(controller: _second, onSubmitted: (_) => _save()),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(label: 'Save PIN', onPressed: _save),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

/// Enter the PIN to unlock a PIN-locked session. Wrong PINs stay on the
/// sheet with an error rather than closing it — the same "retry, don't
/// bounce" behaviour a cancelled biometric prompt gets on the sign-in screen
/// itself.
Future<void> showPinUnlockSheet(BuildContext context, SessionController session) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (_) => _PinUnlockSheet(session: session),
  );
}

class _PinUnlockSheet extends StatefulWidget {
  const _PinUnlockSheet({required this.session});

  final SessionController session;

  @override
  State<_PinUnlockSheet> createState() => _PinUnlockSheetState();
}

class _PinUnlockSheetState extends State<_PinUnlockSheet> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pin.text.length != 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.session.unlockWithPin(_pin.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = 'Incorrect PIN.';
      _pin.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter your PIN',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.lg),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          PinCodeField(
            controller: _pin,
            autofocus: true,
            enabled: !_busy,
            onChanged: (v) {
              if (v.length == 4) _submit();
            },
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(label: 'Unlock', busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
