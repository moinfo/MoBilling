import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Register or transfer a domain: live availability check against the
/// registry, then an order that produces an invoice.
class DomainSearchScreen extends ConsumerStatefulWidget {
  const DomainSearchScreen({super.key});

  @override
  ConsumerState<DomainSearchScreen> createState() =>
      _DomainSearchScreenState();
}

class _DomainSearchScreenState extends ConsumerState<DomainSearchScreen> {
  final _name = TextEditingController();
  final _authInfo = TextEditingController();

  DomainCheckResult? _result;
  bool _checking = false;
  bool _ordering = false;
  int _years = 1;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _authInfo.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final name = _name.text.trim().toLowerCase();
    if (name.isEmpty || !name.contains('.')) {
      setState(() => _error = 'Enter a full domain, e.g. mycompany.co.tz');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref.read(portalServiceProvider).checkDomain(name);
      if (!mounted) return;
      setState(() {
        _result = result;
        _years = result.pricing?.yearsMin ?? 1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _order(String action) async {
    final result = _result;
    if (result == null) return;

    setState(() {
      _ordering = true;
      _error = null;
    });
    try {
      final order = await ref.read(portalServiceProvider).orderDomain(
            name: result.name,
            years: _years,
            action: action,
            authInfo:
                action == 'transfer' ? _authInfo.text.trim() : null,
          );
      ref.invalidate(domainsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(order.message ??
              'Order placed — pay ${order.documentNumber} to proceed.')));
      context.pushReplacement(Routes.invoicePath(order.documentId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final result = _result;
    final pricing = result?.pricing;

    return Scaffold(
      appBar: AppBar(title: const Text('Get a domain')),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _check(),
                  decoration: const InputDecoration(
                    hintText: 'mycompany.co.tz',
                    prefixIcon: Icon(Icons.language_outlined),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: _checking ? null : _check,
                child: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Check'),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: Spacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          result.available
                              ? Icons.check_circle_outline
                              : Icons.cancel_outlined,
                          color: result.available
                              ? status.settled
                              : status.overdue,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            result.available
                                ? '${result.name} is available!'
                                : '${result.name} is taken',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    if (pricing == null) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        'This extension is not offered online — contact us.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ] else ...[
                      const SizedBox(height: Spacing.md),
                      DropdownButtonFormField<int>(
                        initialValue: _years,
                        decoration:
                            const InputDecoration(labelText: 'Period'),
                        items: [
                          for (var y = pricing.yearsMin;
                              y <= pricing.yearsMax;
                              y++)
                            DropdownMenuItem(
                                value: y,
                                child: Text('$y year${y > 1 ? 's' : ''}')),
                        ],
                        onChanged: (v) => setState(() => _years = v!),
                      ),
                      const SizedBox(height: Spacing.md),
                      if (result.available)
                        FilledButton(
                          onPressed:
                              _ordering ? null : () => _order('register'),
                          child: Text(_ordering
                              ? 'Placing order…'
                              : 'Register — ${Formatting.currency(pricing.registerPrice * _years)}'),
                        )
                      else ...[
                        TextField(
                          controller: _authInfo,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Transfer (EPP) code',
                            helperText:
                                'Already yours? Transfer it to us with the code from your registrar.',
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        OutlinedButton(
                          onPressed:
                              _ordering ? null : () => _order('transfer'),
                          child: Text(
                              'Transfer — ${Formatting.currency(pricing.transferPrice * _years)}'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
