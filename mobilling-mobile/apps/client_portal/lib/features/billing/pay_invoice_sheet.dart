import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';

/// Pay an invoice through Pesapal.
///
/// The flow deliberately avoids deep links: card/M-Pesa entry happens on
/// Pesapal's hosted page in an in-app browser view, while this sheet polls
/// the status endpoint underneath. The IPN webhook settles the payment
/// server-side, so the poll converges no matter what the user does with the
/// browser tab — close it, background it, or let Pesapal's callback land on
/// the tenant's web portal. A URL scheme can still be added later purely as
/// polish (auto-closing the browser), but nothing depends on it.
class PayInvoiceSheet extends ConsumerStatefulWidget {
  const PayInvoiceSheet({super.key, required this.document});

  final PortalDocument document;

  /// Returns true when a payment completed, so the caller can refresh.
  static Future<bool?> show(BuildContext context, PortalDocument document) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        // Dismissal is allowed while entering the amount, but once a checkout
        // exists we keep the sheet up so the poll can report the outcome.
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        builder: (_) => PayInvoiceSheet(document: document),
      );

  @override
  ConsumerState<PayInvoiceSheet> createState() => _PayInvoiceSheetState();
}

enum _Phase { amount, waiting, completed, failed }

class _PayInvoiceSheetState extends ConsumerState<PayInvoiceSheet> {
  late final TextEditingController _amount;
  final _formKey = GlobalKey<FormState>();

  _Phase _phase = _Phase.amount;
  bool _submitting = false;
  String? _error;

  CheckoutSession? _checkout;
  InvoicePaymentStatus? _status;
  Timer? _poll;
  int _polls = 0;

  /// 4s matches the web pay page's cadence; ~75 polls ≈ 5 minutes before we
  /// stop burning battery and hand control to a manual "check again".
  static const _pollInterval = Duration(seconds: 4);
  static const _maxAutoPolls = 75;

  double get _balance => widget.document.balanceDue;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final amount = double.parse(_amount.text.trim());
      final checkout = await ref
          .read(portalServiceProvider)
          .payDocument(widget.document.id, amount: amount);

      final url = checkout.redirectUrl;
      if (url == null) {
        // Pesapal accepted nothing — the tracked payment exists but there is
        // no page to send the user to.
        setState(() =>
            _error = 'The payment gateway did not respond. Please try again.');
        return;
      }

      _checkout = checkout;

      // In-app browser view keeps the user "in" the app; falls back to the
      // external browser on platforms without custom tabs.
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!launched) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }

      setState(() => _phase = _Phase.waiting);
      _beginPolling();
    } on ApiException catch (e) {
      // The 400s here carry precise reasons ("Invoice is already paid.",
      // "Online payment is not available…") — show them verbatim.
      if (!mounted) return;
      setState(() => _error = e.errorFor('amount') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _beginPolling() {
    _polls = 0;
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _checkStatus());
  }

  Future<void> _checkStatus({bool manual = false}) async {
    final checkout = _checkout;
    if (checkout == null) return;

    if (!manual && ++_polls > _maxAutoPolls) {
      _poll?.cancel();
      if (mounted) setState(() {});
      return;
    }

    try {
      final status = await ref
          .read(portalServiceProvider)
          .paymentStatus(widget.document.id, checkout.paymentId);
      if (!mounted) return;

      if (status.isSettled) {
        _poll?.cancel();
        setState(() {
          _status = status;
          _phase = status.isCompleted ? _Phase.completed : _Phase.failed;
        });
      } else if (manual) {
        setState(() => _status = status);
      }
    } on ApiException {
      // A flaky poll is not a failed payment; the next tick retries.
    }
  }

  void _retry() {
    _poll?.cancel();
    setState(() {
      _phase = _Phase.amount;
      _checkout = null;
      _status = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While waiting, back/drag shouldn't silently discard the poll — the
      // payment may still complete. Amount entry and terminal states pop free.
      canPop: _phase != _Phase.waiting,
      child: Padding(
        padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
        ),
        child: switch (_phase) {
          _Phase.amount => _buildAmount(context),
          _Phase.waiting => _buildWaiting(context),
          _Phase.completed => _buildResult(context, success: true),
          _Phase.failed => _buildResult(context, success: false),
        },
      ),
    );
  }

  Widget _buildAmount(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pay ${widget.document.documentNumber}',
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Spacing.xs),
          Text(
            'Balance due: ${Formatting.currency(_balance)}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.lg),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          TextFormField(
            controller: _amount,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '${Formatting.tenantCurrency} ',
              helperText: 'You can pay part of the balance',
            ),
            validator: (value) {
              final parsed = double.tryParse(value?.trim() ?? '');
              if (parsed == null || parsed < 1) return 'Enter a valid amount';
              if (parsed > _balance) {
                return 'Cannot exceed ${Formatting.currency(_balance)}';
              }
              return null;
            },
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: _submitting ? null : _startCheckout,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline, size: 18),
            label: Text(_submitting ? 'Connecting…' : 'Pay with Pesapal'),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Card and mobile money via Pesapal’s secure page.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final autoPollingStopped = _polls > _maxAutoPolls;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Spacing.sm),
        const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        Text('Waiting for confirmation',
            style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: Spacing.sm),
        Text(
          autoPollingStopped
              ? 'This is taking longer than usual. If you completed the '
                  'payment, it will still be recorded — check again below.'
              : 'Complete the payment in the browser window. This screen '
                  'updates automatically once Pesapal confirms.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.lg),
        if (autoPollingStopped)
          FilledButton(
            onPressed: () => _checkStatus(manual: true),
            child: const Text('Check again'),
          )
        else
          OutlinedButton(
            onPressed: () => _checkStatus(manual: true),
            child: const Text('I have completed the payment'),
          ),
        TextButton(
          onPressed: () {
            _poll?.cancel();
            Navigator.of(context).pop(false);
          },
          child: const Text('Close — I’ll pay later'),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, {required bool success}) {
    final theme = Theme.of(context);
    final colors = context.statusColors;
    final status = _status;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          size: 48,
          color: success ? colors.settled : colors.overdue,
        ),
        const SizedBox(height: Spacing.md),
        Text(
          success ? 'Payment received' : 'Payment failed',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.sm),
        if (success && status != null) ...[
          Text(
            [
              Formatting.currency(status.amount),
              if (status.paymentMethod != null) 'via ${status.paymentMethod}',
              if (status.confirmationCode != null)
                'ref ${status.confirmationCode}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ] else if (!success)
          Text(
            'No money was taken. You can try again, or use the offline '
            'payment details on the invoice.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: Spacing.lg),
        if (success)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          )
        else ...[
          FilledButton(onPressed: _retry, child: const Text('Try again')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ],
      ],
    );
  }
}
