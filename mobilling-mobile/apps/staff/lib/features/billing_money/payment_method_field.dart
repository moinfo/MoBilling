import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import 'billing_money_providers.dart';

/// Dropdown over the tenant's configured payment methods.
///
/// Posts [TenantPaymentMethod.value] and only ever displays the label — the
/// API validates with `Rule::in($values)`, so submitting a label is a 422.
class PaymentMethodField extends ConsumerWidget {
  const PaymentMethodField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);

    // While loading (or if the request failed) fall back to the defaults so the
    // form is never blocked on a settings lookup.
    final options = methods.valueOrNull ?? TenantPaymentMethod.defaults;

    return DropdownButtonFormField<String>(
      initialValue:
          options.any((m) => m.value == value) ? value : null,
      decoration: const InputDecoration(labelText: 'Payment method'),
      items: [
        for (final method in options)
          DropdownMenuItem(value: method.value, child: Text(method.label)),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (v) =>
          (v == null || v.isEmpty) ? 'Choose a payment method' : null,
    );
  }
}
