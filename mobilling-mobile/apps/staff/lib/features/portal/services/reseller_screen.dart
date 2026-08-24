import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_providers.dart';
import '../portal_routes.dart';
import '../portal_sheet.dart';

/// Domain reseller: buy and renew domains at MoBilling's own wholesale cost.
///
/// Two screens in one, because the API is one endpoint: a non-member sees the
/// pitch and the price list, a member sees the search, the price list and
/// their own domains ready to renew. Every reseller order settles from the
/// wallet in the same request — there is no invoice to pay afterwards, so the
/// wallet balance is the figure this screen keeps in view.
class PortalResellerScreen extends ConsumerWidget {
  const PortalResellerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(portalResellerStatusProvider);

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'Services', title: 'Reseller'),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load reseller pricing',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(portalResellerStatusProvider),
        ),
        data: (data) => data.isReseller
            ? _ResellerBody(status: data)
            : _JoinBody(status: data),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Not a reseller yet
// ---------------------------------------------------------------------------

class _JoinBody extends ConsumerStatefulWidget {
  const _JoinBody({required this.status});

  final ResellerStatus status;

  @override
  ConsumerState<_JoinBody> createState() => _JoinBodyState();
}

class _JoinBodyState extends ConsumerState<_JoinBody> {
  bool _busy = false;
  String? _error;

  Future<void> _subscribe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invoice = await ref.read(portalServiceProvider).subscribeReseller();
      ref.invalidate(portalResellerStatusProvider);
      ref.invalidate(portalDashboardProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invoice.message ??
                'Pay ${invoice.documentNumber} to activate your membership.',
          ),
        ),
      );
      // Membership activates when the invoice is paid, by any means — take
      // them straight to it rather than leaving them to find it.
      context.push(PortalRoutes.invoicePath(invoice.documentId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.status;
    final price = s.membershipPrice;

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Reveal(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ANNUAL MEMBERSHIP',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Money(price ?? 0, scale: MoneyScale.display),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        'PER YEAR',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'Resellers buy .tz and other domains at our own wholesale '
                    'cost — the price we pay the registry — instead of retail. '
                    'Worth it if you register or renew domains for your own '
                    'clients.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(height: Spacing.lg),
                  const _Benefit(
                    icon: Icons.percent,
                    text:
                        'Wholesale pricing on registration, transfer and '
                        'renewal',
                  ),
                  const SizedBox(height: Spacing.sm),
                  const _Benefit(
                    icon: Icons.credit_card_outlined,
                    text:
                        'Pay the fee any way you like — card, mobile money, '
                        'bank transfer or wallet credit',
                  ),
                  const SizedBox(height: Spacing.sm),
                  const _Benefit(
                    icon: Icons.autorenew,
                    text:
                        'Renews every year while your membership stays '
                        'active',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (price == null)
          StateMessage(
            icon: Icons.storefront_outlined,
            title: 'Membership is not on sale right now',
            message: 'Get in touch and we will set your account up manually.',
          )
        else
          PrimaryButton(
            label: 'Become a reseller',
            icon: Icons.workspace_premium_outlined,
            busy: _busy,
            onPressed: _busy ? null : _subscribe,
          ),
        const SizedBox(height: Spacing.lg),
        _WholesalePrices(tlds: s.tlds),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: Spacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Active reseller
// ---------------------------------------------------------------------------

class _ResellerBody extends ConsumerStatefulWidget {
  const _ResellerBody({required this.status});

  final ResellerStatus status;

  @override
  ConsumerState<_ResellerBody> createState() => _ResellerBodyState();
}

class _ResellerBodyState extends ConsumerState<_ResellerBody> {
  final _name = TextEditingController();
  final _authInfo = TextEditingController();

  ResellerCheckResult? _result;
  bool _checking = false;
  bool _busy = false;
  int _years = 1;
  String? _error;

  ResellerStatus get s => widget.status;

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
      final result = await ref
          .read(portalServiceProvider)
          .checkResellerDomain(name);
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
    if (action == 'transfer' && _authInfo.text.trim().isEmpty) {
      setState(
        () => _error =
            'A transfer needs the EPP code from the '
            'current registrar.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(portalServiceProvider)
          .orderResellerDomain(
            name: result.name,
            years: _years,
            action: action,
            authInfo: action == 'transfer' ? _authInfo.text.trim() : null,
          );
      _afterWalletSpend(order.message ?? '${result.name} ordered.');
      if (mounted) {
        setState(() {
          _result = null;
          _name.clear();
          _authInfo.clear();
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew(PortalDomain domain, ResellerTld pricing) async {
    var years = pricing.yearsMin;

    final confirmed = await showPortalSheet<bool>(
      context,
      eyebrow: domain.name,
      title: 'Renew at wholesale',
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel('Renewal period'),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<int>(
            initialValue: years,
            items: [
              for (var y = pricing.yearsMin; y <= pricing.yearsMax; y++)
                DropdownMenuItem(
                  value: y,
                  child: Text('$y year${y > 1 ? 's' : ''}'),
                ),
            ],
            onChanged: (v) => setSheetState(() => years = v!),
          ),
          const SizedBox(height: Spacing.md),
          _WalletLine(
            total: pricing.resellerPrice * years,
            balance: s.walletBalance,
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Pay from wallet',
            onPressed: pricing.resellerPrice * years > s.walletBalance
                ? null
                : () => Navigator.pop(context, true),
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(portalServiceProvider)
          .renewResellerDomain(domain.id, years: years);
      _afterWalletSpend(order.message ?? '${domain.name} renewed.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Both order paths debit the wallet and touch the domain list, so every
  /// figure on and around this screen is stale afterwards.
  void _afterWalletSpend(String message) {
    ref.invalidate(portalResellerStatusProvider);
    ref.invalidate(portalDomainsProvider);
    ref.invalidate(portalCreditProvider);
    ref.invalidate(portalDashboardProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColors = context.statusColors;
    final result = _result;
    final pricing = result?.pricing;
    final total = (pricing?.resellerPrice ?? 0) * _years;
    final domains =
        ref.watch(portalDomainsProvider).valueOrNull?.domains ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(portalResellerStatusProvider);
        ref.invalidate(portalDomainsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: Spacing.md),
          ],

          // The wallet is the only way a reseller order gets paid, so it is
          // the figure this screen leads with.
          Reveal(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const StatusChip('active', dense: true),
                        const Spacer(),
                        Text(
                          s.expireDate == null
                              ? 'MEMBERSHIP ACTIVE'
                              : 'UNTIL ${Formatting.date(s.expireDate).toUpperCase()}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      'WALLET BALANCE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Money(
                        s.walletBalance,
                        scale: MoneyScale.display,
                        color: s.walletBalance > 0
                            ? statusColors.settled
                            : statusColors.overdue,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    OutlinedButton.icon(
                      onPressed: () => context.push(PortalRoutes.credit),
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                      ),
                      label: const Text('Top up wallet'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),

          const SectionHeader('Register or transfer'),
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
            const SizedBox(height: Spacing.md),
            Reveal(
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
                                ? statusColors.settled
                                : statusColors.overdue,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Text(
                            result.available ? 'AVAILABLE' : 'TAKEN',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: result.available
                                  ? statusColors.settled
                                  : statusColors.overdue,
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
                          result.message ??
                              'We do not offer this extension at reseller '
                                  'pricing — please contact us.',
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
                                child: Money(total, scale: MoneyScale.display),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'WHOLESALE · $_years YEAR${_years > 1 ? 'S' : ''}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: Spacing.lg),
                        FieldLabel('Period'),
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
                        if (!result.available) ...[
                          const SizedBox(height: Spacing.md),
                          FieldLabel('Transfer (EPP) code'),
                          const SizedBox(height: Spacing.sm),
                          TextField(
                            controller: _authInfo,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'The code from the current registrar',
                            ),
                          ),
                        ],
                        const SizedBox(height: Spacing.md),
                        _WalletLine(total: total, balance: s.walletBalance),
                        const SizedBox(height: Spacing.md),
                        PrimaryButton(
                          label: result.available
                              ? 'Register — pay from wallet'
                              : 'Transfer — pay from wallet',
                          busy: _busy,
                          onPressed: _busy || total > s.walletBalance
                              ? null
                              : () => _order(
                                  result.available ? 'register' : 'transfer',
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: Spacing.lg),
          _WholesalePrices(tlds: s.tlds),

          const SizedBox(height: Spacing.lg),
          const SectionHeader('Renew at wholesale'),
          const SizedBox(height: Spacing.sm),
          if (domains.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(
                  'You have no domains yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final (i, domain) in domains.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _RenewRow(
                      domain: domain,
                      pricing: s.pricingFor(domain.name),
                      enabled: !_busy,
                      onRenew: (p) => _renew(domain, p),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

/// What this order costs against what the wallet holds — the only funding
/// source a reseller order has, so the shortfall must be visible before the
/// button is tapped rather than arriving as a 422.
class _WalletLine extends StatelessWidget {
  const _WalletLine({required this.total, required this.balance});

  final double total;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final short = total > balance;

    return Row(
      children: [
        Expanded(
          child: Text(
            short
                ? 'SHORT BY ${Formatting.currency(total - balance)}'
                : 'WALLET ${Formatting.currency(balance)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: short
                  ? context.statusColors.overdue
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
        Money(total, scale: MoneyScale.row),
      ],
    );
  }
}

/// The wholesale price list. Two columns of TLD-and-price — a table of four
/// numbers does not need rows.
class _WholesalePrices extends StatelessWidget {
  const _WholesalePrices({required this.tlds});

  final List<ResellerTld> tlds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Wholesale prices'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: tlds.isEmpty
                ? Text(
                    'No extensions are priced for resellers yet — contact us.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, tld) in tlds.indexed) ...[
                        if (i > 0) const Divider(height: Spacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '.${tld.tld}',
                                style: Type.mono(
                                  13,
                                  weight: FontWeight.w500,
                                  tracking: 0,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            Money(
                              tld.resellerPrice,
                              scale: MoneyScale.dense,
                              showCode: false,
                            ),
                            const SizedBox(width: Spacing.xs),
                            Text(
                              '/YR',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// One of the reseller's own domains, with its wholesale renewal price as the
/// trailing figure.
class _RenewRow extends StatelessWidget {
  const _RenewRow({
    required this.domain,
    required this.pricing,
    required this.enabled,
    required this.onRenew,
  });

  final PortalDomain domain;

  /// Null when this extension carries no reseller price.
  final ResellerTld? pricing;

  final bool enabled;
  final void Function(ResellerTld pricing) onRenew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = pricing;
    final blocked = p == null || domain.unmanaged;

    return ListTile(
      title: Text(domain.name, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(
          children: [
            StatusChip(domain.status, dense: true),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                domain.unmanaged
                    ? 'RENEWED MANUALLY'
                    : p == null
                    ? 'NO RESELLER PRICE'
                    : 'EXPIRES ${Formatting.date(domain.expiresAt).toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: blocked
          ? null
          : Money(p.resellerPrice, scale: MoneyScale.dense, showCode: false),
      enabled: enabled && !blocked,
      onTap: blocked ? null : () => onRenew(p),
    );
  }
}
