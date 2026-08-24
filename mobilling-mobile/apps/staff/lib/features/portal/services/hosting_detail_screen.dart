import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';

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
          onAction: () => ref.invalidate(portalHostingDetailProvider(accountId)),
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

  Future<void> _refreshUsage() => _run(() async {
    await ref.read(portalServiceProvider).refreshHostingUsage(a.id);
    ref.invalidate(portalHostingDetailProvider(a.id));
    ref.invalidate(portalHostingProvider);
  });

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    String? fieldError;
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
              hintText: 'At least 8 characters',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              errorText: fieldError,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Change password',
            onPressed: () {
              if (controller.text.length < 8) {
                setSheetState(
                  () => fieldError = 'Use at least 8 characters.',
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
    if (password == null || password.length < 8) {
      if (password != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Use at least 8 characters.')),
        );
      }
      return;
    }
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
    final options = await ref
        .read(portalServiceProvider)
        .hostingUpgradeOptions(a.id);
    if (!mounted) return;

    final selected = await _showSheet<HostingPlanOption>(
      context,
      eyebrow: 'Current plan · ${options.currentPlan}',
      title: 'Change plan',
      padded: false,
      builder: (context, _) => Card(
        child: Column(
          children: [
            for (final (i, plan) in options.plans.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _PlanRow(
                plan: plan,
                onTap: () => Navigator.pop(context, plan),
              ),
            ],
          ],
        ),
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
                              'PLAN',
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
                  if (a.diskUsed != null)
                    _InfoRow(
                      'Disk',
                      value: '${a.diskUsed} / ${a.diskLimit ?? '∞'}',
                    ),
                ],
              ),
            ),
          ),
        ),

        if (active) ...[
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

        const SizedBox(height: Spacing.lg),
        const SectionHeader('Manage'),
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
                enabled: !_busy && active,
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: _changePassword,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: const Text('Upgrade or downgrade plan'),
                enabled: !_busy && active,
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
                enabled: !_busy,
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
            if (!plan.isCurrent && plan.dueNow > 0) ...[
              Text(' · DUE NOW ', style: muted),
              Money(
                plan.dueNow,
                scale: MoneyScale.dense,
                showCode: false,
                color: scheme.onSurfaceVariant,
              ),
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
              Spacing.lg + MediaQuery.viewInsetsOf(context).bottom,
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
