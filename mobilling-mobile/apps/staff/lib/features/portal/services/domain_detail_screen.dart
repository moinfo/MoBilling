import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../portal_routes.dart';
import '../portal_providers.dart';
import '../../../providers.dart';

/// Domain management: renew, auto-renew, EPP code, nameservers.
class PortalDomainDetailScreen extends ConsumerWidget {
  const PortalDomainDetailScreen({super.key, required this.domainId});

  final String domainId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(portalDomainDetailProvider(domainId));

    return Scaffold(
      appBar: AppBar(title: Text(detail.valueOrNull?.name ?? 'Domain')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StateMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this domain',
          message: error is ApiException ? error.message : null,
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(portalDomainDetailProvider(domainId)),
        ),
        data: (d) => _Body(domain: d),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.domain});

  final DomainDetail domain;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  DomainDetail get d => widget.domain;

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

  Future<void> _renew() async {
    int years = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Renew ${d.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.billing?.recurring != null)
                Text(
                    '${Formatting.currency(d.billing!.recurring)} per year — an invoice will be created; the renewal applies once it is paid.'),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<int>(
                initialValue: years,
                decoration: const InputDecoration(labelText: 'Years'),
                items: [
                  for (var y = 1; y <= 10; y++)
                    DropdownMenuItem(
                        value: y, child: Text('$y year${y > 1 ? 's' : ''}')),
                ],
                onChanged: (v) => setDialogState(() => years = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create invoice')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final invoice =
          await ref.read(portalServiceProvider).renewDomain(d.id, years: years);
      if (!mounted) return;
      context.push(PortalRoutes.invoicePath(invoice.documentId));
    });
  }

  Future<void> _showEppCode() => _run(() async {
        final code = await ref.read(portalServiceProvider).domainEppCode(d.id);
        if (!mounted || code.isEmpty) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Transfer (EPP) code'),
            content: SelectableText(code,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 18, letterSpacing: 1)),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Copy & close'),
              ),
            ],
          ),
        );
      });

  Future<void> _toggleAutoRenew(bool enabled) => _run(() async {
        await ref.read(portalServiceProvider).setDomainAutoRenew(d.id, enabled);
        ref.invalidate(portalDomainDetailProvider(d.id));
        ref.invalidate(portalDomainsProvider);
      });

  Future<void> _editNameservers() async {
    final current =
        await ref.read(portalServiceProvider).domainNameservers(d.id);
    if (!mounted) return;

    if (!current.editable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Nameservers for this domain cannot be edited here — contact support.')));
      return;
    }

    final controllers = [
      for (var i = 0; i < 4; i++)
        TextEditingController(
            text: i < current.nameservers.length ? current.nameservers[i] : ''),
    ];

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nameservers'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: TextField(
                  controller: controllers[i],
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'NS${i + 1}${i > 1 ? ' (optional)' : ''}',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (save != true) return;

    final nameservers = controllers
        .map((c) => c.text.trim().toLowerCase())
        .where((v) => v.isNotEmpty)
        .toList();

    await _run(() async {
      await ref
          .read(portalServiceProvider)
          .updateDomainNameservers(d.id, nameservers);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nameservers updated.')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final user = ref.watch(currentUserProvider);
    final renewable = !d.unmanaged &&
        (d.status == 'active' || d.status == 'expired');

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
                        child:
                            Text(d.name, style: theme.textTheme.titleMedium)),
                    StatusChip(d.status, dense: true),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                _InfoRow('Registered', Formatting.date(d.registeredAt)),
                _InfoRow('Expires', Formatting.date(d.expiresAt)),
                if (d.billing?.recurring != null)
                  _InfoRow('Renewal',
                      '${Formatting.currency(d.billing!.recurring)} / year'),
                if (d.sslValid != null)
                  _InfoRow(
                      'SSL',
                      d.sslValid!
                          ? 'Valid${d.sslExpiresAt == null ? '' : ' until ${Formatting.date(d.sslExpiresAt)}'}'
                          : 'Invalid or missing'),
                if (d.unmanaged) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'This domain is managed manually — renewals and DNS '
                    'changes go through support.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: status.attention),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),

        if (renewable) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _renew,
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('Renew domain'),
          ),
          const SizedBox(height: Spacing.md),
        ],

        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.event_repeat_outlined),
                title: const Text('Auto-renew'),
                subtitle: (user?.isPortalAdmin ?? false)
                    ? null
                    : const Text('Only portal administrators can change this'),
                value: d.autoRenew,
                onChanged: (_busy ||
                        d.unmanaged ||
                        !(user?.isPortalAdmin ?? false))
                    ? null
                    : _toggleAutoRenew,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Nameservers'),
                enabled: !_busy && !d.unmanaged,
                trailing: const Icon(Icons.chevron_right),
                onTap: _editNameservers,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Get transfer (EPP) code'),
                enabled: !_busy && !d.unmanaged,
                onTap: _showEppCode,
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
