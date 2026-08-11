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
      appBar: AppBar(title: Text(detail.valueOrNull?.domain ?? 'Hosting')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sso({String service = 'cpanel', String? goto}) => _run(() async {
        final url = await ref
            .read(portalServiceProvider)
            .hostingSsoUrl(a.id, service: service, goto: goto);
        if (url.isNotEmpty) {
          // One-time login URL — external browser, it's a full session.
          await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
        }
      });

  Future<void> _refreshUsage() => _run(() async {
        await ref.read(portalServiceProvider).refreshHostingUsage(a.id);
        ref.invalidate(portalHostingDetailProvider(a.id));
        ref.invalidate(portalHostingProvider);
      });

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New cPanel password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password (min 8)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Change')),
        ],
      ),
    );
    if (password == null || password.length < 8) {
      if (password != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use at least 8 characters.')));
      }
      return;
    }
    await _run(() async {
      await ref
          .read(portalServiceProvider)
          .changeHostingPassword(a.id, password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('cPanel password changed.')));
      }
    });
  }

  Future<void> _requestCancellation() async {
    final reason = TextEditingController();
    String when = 'end_of_period';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request cancellation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Why are you cancelling?'),
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String>(
                initialValue: when,
                decoration: const InputDecoration(labelText: 'When'),
                items: const [
                  DropdownMenuItem(
                      value: 'end_of_period',
                      child: Text('At the end of my billing period')),
                  DropdownMenuItem(
                      value: 'immediate', child: Text('Immediately')),
                ],
                onChanged: (v) => setDialogState(() => when = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Back')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit request')),
          ],
        ),
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) return;

    await _run(() async {
      final message = await ref
          .read(portalServiceProvider)
          .requestHostingCancellation(a.id,
              reason: reason.text.trim(), when: when);
      if (mounted && message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  Future<void> _upgrade() async {
    final options =
        await ref.read(portalServiceProvider).hostingUpgradeOptions(a.id);
    if (!mounted) return;

    final selected = await showModalBottomSheet<HostingPlanOption>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Text('Change plan',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final plan in options.plans)
              ListTile(
                title: Text(plan.name),
                subtitle: Text([
                  Formatting.currency(plan.price),
                  if (plan.billingCycle != null)
                    plan.billingCycle!.replaceAll('_', ' '),
                  if (!plan.isCurrent && plan.dueNow > 0)
                    'due now ${Formatting.currency(plan.dueNow)}',
                ].join(' · ')),
                trailing: plan.isCurrent
                    ? const StatusChip('active', dense: true)
                    : const Icon(Icons.chevron_right),
                enabled: !plan.isCurrent,
                onTap: () => Navigator.pop(context, plan),
              ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
    if (selected == null) return;

    await _run(() async {
      final invoice =
          await ref.read(portalServiceProvider).upgradeHosting(a.id, selected.id);
      ref.invalidate(portalHostingDetailProvider(a.id));
      ref.invalidate(portalHostingProvider);
      if (!mounted) return;
      if (invoice != null) {
        // Prorated upgrade invoice — take them straight to pay it.
        context.push(PortalRoutes.invoicePath(invoice.documentId));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan changed.')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(a.domain ?? '—',
                            style: theme.textTheme.titleMedium)),
                    StatusChip(a.status, dense: true),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                _InfoRow('Plan', a.productName ?? a.package ?? '—'),
                if (a.price != null)
                  _InfoRow(
                      'Price',
                      '${Formatting.currency(a.price)}'
                      '${a.billingCycle == null ? '' : ' / ${a.billingCycle!.replaceAll('_', ' ')}'}'),
                _InfoRow('cPanel user', a.cpanelUsername ?? '—'),
                if (a.registeredAt != null)
                  _InfoRow('Since', Formatting.date(a.registeredAt)),
                if (a.nextDue != null)
                  _InfoRow('Next due', Formatting.date(a.nextDue)),
                if (a.diskUsed != null)
                  _InfoRow('Disk', '${a.diskUsed} / ${a.diskLimit ?? '∞'}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),

        if (a.status == 'active') ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _sso(),
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Log in to cPanel'),
          ),
          const SizedBox(height: Spacing.sm),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _sso(service: 'webmail'),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Open webmail'),
          ),
          const SizedBox(height: Spacing.md),
        ],

        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Refresh disk usage'),
                subtitle: a.lastSyncedAt == null
                    ? null
                    : Text('Last synced ${Formatting.dateTime(a.lastSyncedAt)}'),
                enabled: !_busy,
                onTap: _refreshUsage,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Change cPanel password'),
                enabled: !_busy && a.status == 'active',
                onTap: _changePassword,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.swap_vert),
                title: const Text('Upgrade / downgrade plan'),
                enabled: !_busy && a.status == 'active',
                onTap: _upgrade,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cancel_outlined,
                    color: theme.colorScheme.error),
                title: Text('Request cancellation',
                    style: TextStyle(color: theme.colorScheme.error)),
                enabled: !_busy,
                onTap: _requestCancellation,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
