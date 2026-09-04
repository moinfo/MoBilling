import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';
import '../../../providers.dart';

/// Hosting account management: cPanel SSO, usage, password, plan change,
/// cancellation request.
class PortalHostingDetailScreen extends ConsumerWidget {
  const PortalHostingDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(portalHostingDetailProvider(accountId));

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Services',
        title: detail.valueOrNull?.domain ?? 'Hosting',
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this account',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () =>
              ref.invalidate(portalHostingDetailProvider(accountId)),
        ),
        data: (a) => _Body(account: a),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.account});

  final HostingDetail account;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  HostingDetail get a => widget.account;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sso({String service = 'cpanel', String? goto}) =>
      _run(() async {
        final url = await ref
            .read(portalServiceProvider)
            .hostingSsoUrl(a.id, service: service, goto: goto);
        if (url.isNotEmpty) {
          // One-time login URL — external browser, it's a full session.
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      });

  /// The client's own domain record for this account's domain name, if they
  /// have one — hosting and domains are separate products, so a hosted domain
  /// is often registered elsewhere and has nothing here to manage.
  String? _matchingDomainId(WidgetRef ref) {
    final name = a.domain?.toLowerCase();
    if (name == null) return null;
    final list = ref.watch(portalDomainsProvider).valueOrNull;
    if (list == null) return null;
    for (final domain in list.domains) {
      if (domain.name.toLowerCase() == name) return domain.id;
    }
    return null;
  }

  Future<void> _refreshUsage() => _run(() async {
    await ref.read(portalServiceProvider).refreshHostingUsage(a.id);
    ref.invalidate(portalHostingDetailProvider(a.id));
    ref.invalidate(portalHostingProvider);
  });

  /// Twelve characters is the server's own floor (`min:12|confirmed`), so a
  /// shorter one is a wasted round trip. The confirmation is a typo guard
  /// only — the client sends the same value for both halves, so a mismatch
  /// has to be caught here or not at all.
  static const _passwordFloor = 12;

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? fieldError;
    String? confirmError;
    final password = await _showSheet<String>(
      context,
      eyebrow: a.domain ?? 'Hosting',
      title: 'New cPanel password',
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel('Password'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            onChanged: (_) {
              if (fieldError != null) setSheetState(() => fieldError = null);
            },
            decoration: InputDecoration(
              hintText: 'At least $_passwordFloor characters',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              errorText: fieldError,
            ),
          ),
          const SizedBox(height: Spacing.md),
          FieldLabel('Confirm password'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: confirmController,
            obscureText: true,
            onChanged: (_) {
              if (confirmError != null) {
                setSheetState(() => confirmError = null);
              }
            },
            decoration: InputDecoration(
              hintText: 'Type it again',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              errorText: confirmError,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Change password',
            onPressed: () {
              if (controller.text.length < _passwordFloor) {
                setSheetState(
                  () => fieldError =
                      'Use at least $_passwordFloor characters.',
                );
                return;
              }
              if (confirmController.text != controller.text) {
                setSheetState(
                  () => confirmError = 'The two passwords do not match.',
                );
                return;
              }
              Navigator.pop(context, controller.text);
            },
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (password == null || password.length < _passwordFloor) return;
    await _run(() async {
      await ref
          .read(portalServiceProvider)
          .changeHostingPassword(a.id, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('cPanel password changed.')),
        );
      }
    });
  }

  Future<void> _requestCancellation() async {
    final reason = TextEditingController();
    String when = 'end_of_period';

    final confirmed = await _showSheet<bool>(
      context,
      eyebrow: a.domain ?? 'Hosting',
      title: 'Request cancellation',
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel('Why are you cancelling?'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: reason,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'A sentence or two helps us close it properly',
            ),
          ),
          const SizedBox(height: Spacing.md),
          FieldLabel('When'),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String>(
            initialValue: when,
            items: const [
              DropdownMenuItem(
                value: 'end_of_period',
                child: Text('At the end of my billing period'),
              ),
              DropdownMenuItem(value: 'immediate', child: Text('Immediately')),
            ],
            onChanged: (v) => setSheetState(() => when = v!),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Send request',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) return;

    await _run(() async {
      final message = await ref
          .read(portalServiceProvider)
          .requestHostingCancellation(
            a.id,
            reason: reason.text.trim(),
            when: when,
          );
      if (mounted && message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  Future<void> _upgrade() async {
    // Fetching the plans is itself a network call that can fail (403 on a
    // suspended account, the server unreachable) — inside [_run] so it lands
    // in the snackbar like every other action instead of escaping uncaught.
    HostingUpgradeOptions? options;
    await _run(() async {
      options = await ref
          .read(portalServiceProvider)
          .hostingUpgradeOptions(a.id);
    });
    if (options == null || !mounted) return;

    final selected = await _showSheet<HostingPlanOption>(
      context,
      eyebrow: 'Current plan · ${options!.currentPlan}',
      title: 'Change plan',
      padded: false,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Column(
              children: [
                for (final (i, plan) in options!.plans.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _PlanRow(
                    plan: plan,
                    onTap: () => Navigator.pop(context, plan),
                  ),
                ],
              ],
            ),
          ),
          if (options!.plans.any((p) => !p.isCurrent && p.credit > 0)) ...[
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Text(
                'A downgrade applies immediately, and the unused part of the '
                'term you have already paid for is credited to your wallet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (selected == null) return;

    await _run(() async {
      final invoice = await ref
          .read(portalServiceProvider)
          .upgradeHosting(a.id, selected.id);
      ref.invalidate(portalHostingDetailProvider(a.id));
      ref.invalidate(portalHostingProvider);
      if (!mounted) return;
      if (invoice != null) {
        // Prorated upgrade invoice — take them straight to pay it.
        context.push(PortalRoutes.invoicePath(invoice.documentId));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Plan changed.')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = a.status == 'active';
    // cPanel access, the password, the plan and cancellation all belong to
    // whoever owns the account, not to every colleague who can sign in to the
    // portal — the web hides this whole set behind the same check.
    final isAdmin = ref.watch(currentUserProvider)?.isPortalAdmin ?? false;
    final managedDomainId = _matchingDomainId(ref);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Reveal(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // The catalog family, when the API knows it:
                              // "Shared Hosting" says more than "PLAN", and
                              // the product's own name rarely repeats it.
                              (a.productGroup ?? 'Plan').toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Spacing.xs),
                            Text(
                              a.productName ?? a.package ?? '—',
                              style: Type.display(22, color: scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(a.status, dense: true),
                    ],
                  ),
                  if (a.price != null) ...[
                    const SizedBox(height: Spacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Money(a.price, scale: MoneyScale.headline),
                        const SizedBox(width: Spacing.sm),
                        _Cadence(_cadence(a.billingCycle)),
                      ],
                    ),
                  ],
                  const Divider(height: Spacing.lg),
                  _InfoRow(
                    'cPanel user',
                    child: Text(
                      a.cpanelUsername ?? '—',
                      style: Type.mono(
                        12.5,
                        weight: FontWeight.w400,
                        tracking: 0,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (a.registeredAt != null)
                    _InfoRow('Since', value: Formatting.date(a.registeredAt)),
                  if (a.nextDue != null)
                    _InfoRow('Next due', value: Formatting.date(a.nextDue)),
                  if (a.diskUsed != null) ...[
                    const SizedBox(height: Spacing.sm),
                    _DiskUsage(used: a.diskUsed, limit: a.diskLimit),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (a.domain != null) ...[
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://${a.domain}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Visit website'),
                ),
              ),
              // Only offered when this domain is actually one of theirs —
              // the web drops you on the domain list and lets you hunt,
              // which on a phone is worse than not offering it at all.
              if (managedDomainId != null) ...[
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      PortalRoutes.domainPath(managedDomainId),
                    ),
                    icon: const Icon(Icons.language_outlined, size: 18),
                    label: const Text('Manage domain'),
                  ),
                ),
              ],
            ],
          ),
        ],

        if (active && isAdmin) ...[
          const SizedBox(height: Spacing.md),
          PrimaryButton(
            label: 'Log in to cPanel',
            icon: Icons.login,
            busy: _busy,
            onPressed: _busy ? null : () => _sso(),
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _sso(service: 'webmail'),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Open webmail'),
          ),
        ],

        // cPanel's own sections, reached through the same one-time SSO. Gated
        // exactly as the login button is: they are that session, one page in.
        if (active && isAdmin && a.shortcuts.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Quick shortcuts'),
          const SizedBox(height: Spacing.sm),
          _ShortcutGrid(
            keys: a.shortcuts,
            enabled: !_busy,
            onTap: (key) => _sso(goto: key),
          ),
        ],

        const SizedBox(height: Spacing.lg),
        const SectionHeader('Manage'),
        if (!isAdmin) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            'Only portal administrators can change this account.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Refresh disk usage'),
                subtitle: a.lastSyncedAt == null
                    ? null
                    : Text(
                        'LAST SYNCED ${Formatting.dateTime(a.lastSyncedAt).toUpperCase()}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                enabled: !_busy,
                onTap: _refreshUsage,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change cPanel password'),
                enabled: !_busy && active && isAdmin,
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: _changePassword,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: const Text('Upgrade or downgrade plan'),
                enabled: !_busy && active && isAdmin,
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: _upgrade,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: scheme.error),
                title: Text(
                  'Request cancellation',
                  style: TextStyle(color: scheme.error),
                ),
                enabled: !_busy && isAdmin,
                onTap: _requestCancellation,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

/// `monthly` → `PER MONTH`, as the handoff's price-card cadence.
String _cadence(String? cycle) => switch (cycle) {
  null || 'once' => 'one-time',
  'monthly' => 'per month',
  'quarterly' => 'per quarter',
  'semi_annually' || 'semiannually' => 'per 6 months',
  'annually' || 'yearly' => 'per year',
  'biennially' => 'per 2 years',
  'triennially' => 'per 3 years',
  final c => c.replaceAll('_', ' '),
};

/// One plan in the change-plan sheet: the price as the trailing figure, the
/// prorated charge (if any) in the metadata line beside the cadence.
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.onTap});

  final HostingPlanOption plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return ListTile(
      title: Text(plan.name, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(
          children: [
            if (plan.isCurrent) ...[
              const StatusChip('active', dense: true),
              const SizedBox(width: Spacing.sm),
            ],
            Text(_cadence(plan.billingCycle).toUpperCase(), style: muted),
            if (!plan.isCurrent) ...[
              if (plan.dueNow > 0) ...[
                Text(' · DUE NOW ', style: muted),
                Money(
                  plan.dueNow,
                  scale: MoneyScale.dense,
                  showCode: false,
                  color: scheme.onSurfaceVariant,
                ),
              ] else if (plan.credit > 0) ...[
                // A downgrade: nothing to pay, and the unused term comes
                // back as wallet credit. Saying so is the difference between
                // a plan that looks free and one that pays you.
                Text(' · CREDIT ', style: muted),
                Money(
                  plan.credit,
                  scale: MoneyScale.dense,
                  showCode: false,
                  color: context.statusColors.settled,
                ),
              ] else
                Text(' · APPLIES NOW', style: muted),
            ],
          ],
        ),
      ),
      trailing: Money(plan.price),
      enabled: !plan.isCurrent,
      onTap: onTap,
    );
  }
}

/// Disk usage as a ring with the percentage in it.
///
/// cPanel reports these as display strings ("1,240M", "unlimited"), so the
/// figures are shown verbatim and only the ring needs them parsed — when they
/// don't parse, or the limit is unlimited, the ring drops away and the plain
/// figures carry the row on their own.
class _DiskUsage extends StatelessWidget {
  const _DiskUsage({this.used, this.limit});

  final String? used;
  final String? limit;

  /// "1,240M" → 1240. Anything with no digits in it (an "unlimited" limit)
  /// comes back null rather than 0, which would read as a full disk.
  static double? _mb(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^\d.]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final usedMb = _mb(used);
    final limitMb = _mb(limit);
    final fraction = (usedMb != null && limitMb != null && limitMb > 0)
        ? (usedMb / limitMb).clamp(0.0, 1.0)
        : null;
    final colour = switch (fraction) {
      null => scheme.primary,
      final f when f > 0.9 => status.overdue,
      final f when f > 0.7 => status.attention,
      _ => scheme.primary,
    };

    return Row(
      children: [
        SizedBox(
          height: 52,
          width: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 52,
                width: 52,
                child: CircularProgressIndicator(
                  value: fraction ?? 0,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colour),
                ),
              ),
              Text(
                fraction == null
                    ? '—'
                    : '${(fraction * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(color: colour),
              ),
            ],
          ),
        ),
        const SizedBox(width: Spacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DISK USAGE', style: muted),
            const SizedBox(height: 2),
            Text(
              '${used ?? '0M'} / ${limit ?? 'Unlimited'}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

/// The cPanel sections the account reports, as a tap-to-open grid.
///
/// The keys are the server's (`GOTO_MAP` in `PortalHostingController`); an
/// unknown one is skipped rather than guessed at, so adding a key server-side
/// never renders a blank tile here.
class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({
    required this.keys,
    required this.enabled,
    required this.onTap,
  });

  final List<String> keys;
  final bool enabled;
  final void Function(String key) onTap;

  static const _known = <String, (String, IconData)>{
    'email': ('Email accounts', Icons.alternate_email),
    'forwarders': ('Forwarders', Icons.forward_to_inbox_outlined),
    'files': ('File manager', Icons.folder_outlined),
    'backup': ('Backup', Icons.inventory_2_outlined),
    'domains': ('Domains', Icons.language_outlined),
    'cron': ('Cron jobs', Icons.schedule_outlined),
    'mysql': ('MySQL databases', Icons.storage_outlined),
    'phpmyadmin': ('phpMyAdmin', Icons.dns_outlined),
    'stats': ('Awstats', Icons.bar_chart_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tiles = [
      for (final key in keys)
        if (_known[key] case final entry?) (key, entry.$1, entry.$2),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Spacing.sm,
      crossAxisSpacing: Spacing.sm,
      childAspectRatio: 1.05,
      children: [
        for (final (key, label, icon) in tiles)
          InkWell(
            onTap: enabled ? () => onTap(key) : null,
            borderRadius: Radii.card,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: Radii.card,
                ),
                padding: const EdgeInsets.all(Spacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 24, color: scheme.primary),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A label-and-value metadata line: the label in the mono face because it
/// names the value, the value in the body face because it is content.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, {this.value, this.child})
    : assert(value != null || child != null);

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: child ?? Text(value!, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// The mono cadence beside a figure — `PER MONTH`.
class _Cadence extends StatelessWidget {
  const _Cadence(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The brand sheet: drag handle, an eyebrow naming the context, a display
/// title, then [builder]'s content. Rises with the keyboard so a field near
/// the bottom is never hidden behind it.
Future<T?> _showSheet<T>(
  BuildContext context, {
  required String title,
  String? eyebrow,
  bool padded = true,
  required Widget Function(BuildContext context, StateSetter setState) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
    builder: (context) {
      final theme = Theme.of(context);
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padded ? Spacing.lg : Spacing.md,
              0,
              padded ? Spacing.lg : Spacing.md,
              Spacing.lg + sheetBottomInset(context),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: padded ? 0 : Spacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                        ],
                        Text(
                          title,
                          style: Type.display(
                            22,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  builder(context, setState),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
