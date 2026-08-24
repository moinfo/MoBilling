import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

/// Register or transfer a domain: live availability check against the
/// registry, then an order that produces an invoice.
///
/// The answer is the screen: once a name has been checked, the result card
/// carries the verdict, the price as the one figure on the screen, and the
/// single action that follows from it — register if it is free, transfer if
/// it is not.
class DomainSearchScreen extends ConsumerStatefulWidget {
  const DomainSearchScreen({super.key});

  @override
  ConsumerState<DomainSearchScreen> createState() => _DomainSearchScreenState();
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
      final order = await ref
          .read(portalServiceProvider)
          .orderDomain(
            name: result.name,
            years: _years,
            action: action,
            authInfo: action == 'transfer' ? _authInfo.text.trim() : null,
          );
      ref.invalidate(portalDomainsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order.message ??
                'Order placed — pay ${order.documentNumber} to proceed.',
          ),
        ),
      );
      context.pushReplacement(PortalRoutes.invoicePath(order.documentId));
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
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final result = _result;
    final pricing = result?.pricing;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Store', title: 'Get a domain'),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],
          FieldLabel('Domain name'),
          const SizedBox(height: Spacing.sm),
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
                    prefixIcon: Icon(Icons.language_outlined, size: 20),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Check'),
              ),
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: Spacing.lg),
            Reveal(
              // A fresh verdict earns the one piece of motion on the screen.
              key: ValueKey(result.name),
              child: Card(
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
                            size: 20,
                            color: result.available
                                ? status.settled
                                : status.overdue,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Text(
                            result.available ? 'AVAILABLE' : 'TAKEN',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: result.available
                                  ? status.settled
                                  : status.overdue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        result.name,
                        style: Type.display(22, color: scheme.onSurface),
                      ),
                      if (pricing == null) ...[
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'This extension is not offered online — contact us '
                          'and we will register it for you.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: Spacing.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Money(
                                  (result.available
                                          ? pricing.registerPrice
                                          : pricing.transferPrice) *
                                      _years,
                                  scale: MoneyScale.display,
                                ),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'FOR $_years YEAR${_years > 1 ? 'S' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: Spacing.lg),
                        FieldLabel('Registration period'),
                        const SizedBox(height: Spacing.sm),
                        DropdownButtonFormField<int>(
                          initialValue: _years,
                          items: [
                            for (
                              var y = pricing.yearsMin;
                              y <= pricing.yearsMax;
                              y++
                            )
                              DropdownMenuItem(
                                value: y,
                                child: Text('$y year${y > 1 ? 's' : ''}'),
                              ),
                          ],
                          onChanged: (v) => setState(() => _years = v!),
                        ),
                        const SizedBox(height: Spacing.md),
                        if (result.available)
                          PrimaryButton(
                            label: 'Register this domain',
                            busy: _ordering,
                            onPressed: _ordering
                                ? null
                                : () => _order('register'),
                          )
                        else ...[
                          Text(
                            'Already yours? Transfer it to us with the code '
                            'from your current registrar.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          FieldLabel('Transfer (EPP) code'),
                          const SizedBox(height: Spacing.sm),
                          TextField(
                            controller: _authInfo,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'The code from your registrar',
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          PrimaryButton(
                            label: 'Transfer this domain',
                            busy: _ordering,
                            onPressed: _ordering
                                ? null
                                : () => _order('transfer'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

