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
      appBar: ShellTopBar(
        eyebrow: 'Services',
        title: detail.valueOrNull?.name ?? 'Domain',
      ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew() async {
    int years = 1;
    final confirmed = await _showSheet<bool>(
      context,
      eyebrow: 'Renew',
      title: d.name,
      builder: (context, setSheetState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.billing?.recurring != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Money(d.billing!.recurring, scale: MoneyScale.headline),
                const SizedBox(width: Spacing.sm),
                _Cadence('per year'),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'An invoice will be created; the renewal applies once it is paid.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.lg),
          ],
          FieldLabel('Years'),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<int>(
            initialValue: years,
            items: [
              for (var y = 1; y <= 10; y++)
                DropdownMenuItem(
                  value: y,
                  child: Text('$y year${y > 1 ? 's' : ''}'),
                ),
            ],
            onChanged: (v) => setSheetState(() => years = v!),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Create invoice',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final invoice = await ref
          .read(portalServiceProvider)
          .renewDomain(d.id, years: years);
      if (!mounted) return;
      context.push(PortalRoutes.invoicePath(invoice.documentId));
    });
  }

  Future<void> _showEppCode() => _run(() async {
    final code = await ref.read(portalServiceProvider).domainEppCode(d.id);
    if (!mounted || code.isEmpty) return;
    await _showSheet<void>(
      context,
      eyebrow: d.name,
      title: 'Transfer (EPP) code',
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              style: Type.mono(
                18,
                tracking: 0.08,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Copy and close',
            icon: Icons.copy_outlined,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) Navigator.pop(context);
            },
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
    final current = await ref
        .read(portalServiceProvider)
        .domainNameservers(d.id);
    if (!mounted) return;

    if (!current.editable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nameservers for this domain cannot be edited here — contact support.',
          ),
        ),
      );
      return;
    }

    final controllers = [
      for (var i = 0; i < 4; i++)
        TextEditingController(
          text: i < current.nameservers.length ? current.nameservers[i] : '',
        ),
    ];

    final save = await _showSheet<bool>(
      context,
      eyebrow: d.name,
      title: 'Nameservers',
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: Spacing.md),
            FieldLabel('NS${i + 1}${i > 1 ? ' (optional)' : ''}'),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: controllers[i],
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'ns.example.com'),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          PrimaryButton(
            label: 'Save nameservers',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: Spacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nameservers updated.')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final user = ref.watch(currentUserProvider);
    final renewable =
        !d.unmanaged && (d.status == 'active' || d.status == 'expired');

    // The expiry date is the one figure this screen is about; it carries
    // its own colour only once it is the news.
    final daysLeft = Formatting.daysUntil(d.expiresAt);
    final expiryColor = switch (daysLeft) {
      null => scheme.onSurface,
      < 0 => status.overdue,
      <= 45 => status.attention,
      _ => scheme.onSurface,
    };

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
                              'EXPIRES',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: Spacing.xs),
                            Text(
                              Formatting.date(d.expiresAt),
                              style: Type.display(26, color: expiryColor),
                            ),
                            if (daysLeft != null) ...[
                              const SizedBox(height: Spacing.xs),
                              Text(
                                switch (daysLeft) {
                                  < 0 => 'Expired ${-daysLeft} days ago',
                                  0 => 'Expires today',
                                  1 => 'Expires tomorrow',
                                  _ => 'In $daysLeft days',
                                },
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      StatusChip(d.status, dense: true),
                    ],
                  ),
                  const Divider(height: Spacing.lg),
                  _InfoRow(
                    'Registered',
                    value: Formatting.date(d.registeredAt),
                  ),
                  if (d.billing?.recurring != null)
                    _InfoRow(
                      'Renewal',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Money(d.billing!.recurring, scale: MoneyScale.dense),
                          const SizedBox(width: Spacing.xs),
                          _Cadence('per year'),
                        ],
                      ),
                    ),
                  if (d.sslValid != null)
                    _InfoRow(
                      'SSL',
                      value: d.sslValid!
                          ? 'Valid${d.sslExpiresAt == null ? '' : ' until ${Formatting.date(d.sslExpiresAt)}'}'
                          : 'Invalid or missing',
                      color: d.sslValid! ? null : status.overdue,
                    ),
                  if (d.unmanaged) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'This domain is managed manually — renewals and DNS '
                      'changes go through support.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: status.attention,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (renewable) ...[
          const SizedBox(height: Spacing.md),
          PrimaryButton(
            label: 'Renew domain',
            icon: Icons.autorenew,
            busy: _busy,
            onPressed: _busy ? null : _renew,
          ),
        ],

        const SizedBox(height: Spacing.lg),
        const SectionHeader('Manage'),
        const SizedBox(height: Spacing.sm),
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
                onChanged:
                    (_busy || d.unmanaged || !(user?.isPortalAdmin ?? false))
                    ? null
                    : _toggleAutoRenew,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Nameservers'),
                enabled: !_busy && !d.unmanaged,
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: _editNameservers,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Get transfer (EPP) code'),
                enabled: !_busy && !d.unmanaged,
                trailing: Icon(Icons.chevron_right, color: scheme.outline),
                onTap: _showEppCode,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

/// A label-and-value metadata line: the label in the mono face because it
/// names the value, the value in the body face because it is content.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, {this.value, this.child, this.color})
    : assert(value != null || child != null);

  final String label;
  final String? value;
  final Widget? child;
  final Color? color;

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
            child:
                child ??
                Text(
                  value!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
          ),
        ],
      ),
    );
  }
}

/// The mono cadence beside a figure — `PER YEAR`.
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
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg + sheetBottomInset(context),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    style: Type.display(22, color: theme.colorScheme.onSurface),
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
