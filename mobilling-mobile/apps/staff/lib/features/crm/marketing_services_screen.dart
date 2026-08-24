import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Manage the "services discussed" reference list: `MarketingServiceController`.
///
/// Web: `FieldMarketing.tsx`'s Services tab (`ServicesManager.tsx`). A short,
/// rarely-touched reference list, so this follows the same row-plus-sheet
/// shape as [TeamScreen] rather than an infinite-scroll list.
class MarketingServicesScreen extends ConsumerWidget {
  const MarketingServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate =
        session?.can(CrmPermissions.marketingServicesCreate) ?? false;
    final canUpdate =
        session?.can(CrmPermissions.marketingServicesUpdate) ?? false;
    final canDelete =
        session?.can(CrmPermissions.marketingServicesDelete) ?? false;
    final servicesAsync = ref.watch(marketingServicesProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Field marketing',
        title: 'Services',
        trailing: !canCreate
            ? null
            : InkActionButton(
                icon: Icons.add,
                tooltip: 'Add a service',
                onPressed: () => _openForm(context, ref, null),
              ),
      ),
      body: CrmAsyncView(
        value: servicesAsync,
        errorTitle: 'Could not load services',
        onRetry: () => ref.invalidate(marketingServicesProvider),
        builder: (items) => items.isEmpty
            ? const StateMessage(
                icon: Icons.sell_outlined,
                title: 'No services yet',
                message:
                    'Add the services your field team can tag a visit with.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.xl,
                ),
                children: [
                  Text(
                    'Shown on field visit and WhatsApp contact forms. '
                    'Changes apply to everyone in your organisation.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  CrmCardList(
                    children: [
                      for (final (index, service) in items.indexed)
                        ListTile(
                          leading: SizedBox(
                            width: 20,
                            child: Text(
                              Formatting.integer(index + 1),
                              style: Type.mono(
                                12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            service.name,
                            style: theme.textTheme.titleSmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: theme.colorScheme.outline,
                          ),
                          onTap: (!canUpdate && !canDelete)
                              ? null
                              : () => _openActions(
                                  context,
                                  ref,
                                  items,
                                  index,
                                  canUpdate: canUpdate,
                                  canDelete: canDelete,
                                ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    List<MarketingServiceItem> items,
    int index, {
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final service = items[index];
    final action = await showCrmSheet<_ServiceAction>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Field marketing',
          title: service.name,
          children: [
            CrmCardList(
              children: [
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text('Edit', style: theme.textTheme.titleSmall),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ServiceAction.edit),
                  ),
                if (canUpdate && index > 0)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: Text('Move up', style: theme.textTheme.titleSmall),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ServiceAction.moveUp),
                  ),
                if (canUpdate && index < items.length - 1)
                  ListTile(
                    leading: const Icon(Icons.arrow_downward),
                    title: Text('Move down', style: theme.textTheme.titleSmall),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ServiceAction.moveDown),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Delete',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ServiceAction.delete),
                  ),
              ],
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;
    switch (action) {
      case _ServiceAction.edit:
        await _openForm(context, ref, service);
      case _ServiceAction.moveUp:
        await _reorder(context, ref, items, index, index - 1);
      case _ServiceAction.moveDown:
        await _reorder(context, ref, items, index, index + 1);
      case _ServiceAction.delete:
        await _delete(context, ref, service);
      case null:
        break;
    }
  }

  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<MarketingServiceItem> items,
    int from,
    int to,
  ) async {
    final reordered = [...items];
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmServiceProvider).reorderMarketingServices([
        for (final s in reordered) s.id,
      ]);
      ref.invalidate(marketingServicesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MarketingServiceItem service,
  ) async {
    final scheme = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${service.name}"?'),
        content: const Text(
          'This removes it from the field visit and WhatsApp contact '
          'forms for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmServiceProvider).deleteMarketingService(service.id);
      ref.invalidate(marketingServicesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${service.name} deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    MarketingServiceItem? service,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _ServiceFormSheet(service: service),
    );
    if (saved == true) ref.invalidate(marketingServicesProvider);
  }
}

enum _ServiceAction { edit, moveUp, moveDown, delete }

class _ServiceFormSheet extends ConsumerStatefulWidget {
  const _ServiceFormSheet({required this.service});

  final MarketingServiceItem? service;

  @override
  ConsumerState<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends ConsumerState<_ServiceFormSheet> {
  late final TextEditingController _name;
  String? _error;
  bool _busy = false;

  bool get _isNew => widget.service == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.service?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the service a name.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(crmServiceProvider);
      if (_isNew) {
        await service.createMarketingService(name);
      } else {
        await service.updateMarketingService(widget.service!.id, name);
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(_isNew ? '$name added.' : '$name saved.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Field marketing',
    title: _isNew ? 'Add a service' : widget.service!.name,
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Name',
        child: TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Bulk SMS'),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _isNew ? 'Add service' : 'Save',
        busy: _busy,
        onPressed: _busy ? null : _save,
      ),
    ],
  );
}
