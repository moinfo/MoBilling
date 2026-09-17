import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmCardList,
        CrmField,
        CrmMetaLine,
        CrmSheet,
        showCrmSheet;
import '../staff_self/attendance_location.dart';
import 'admin_providers.dart';

/// Work locations — the geofences each staff member's self-check-in
/// (`AttendanceScreen`'s "Check in now") is measured against. A handful of
/// offices per tenant, so this is a plain list-and-form, the same shape as
/// bank accounts, not a paginated table.
class WorkLocationsScreen extends ConsumerWidget {
  const WorkLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(workLocationsProvider);
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(AdminPermissions.workLocationsCreate) ?? false;
    final canUpdate = session?.can(AdminPermissions.workLocationsUpdate) ?? false;
    final canDelete = session?.can(AdminPermissions.workLocationsDelete) ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const ShellTopBar(eyebrow: 'HR', title: 'Work locations'),
      body: CrmAsyncView(
        value: locations,
        errorTitle: 'Could not load work locations',
        onRetry: () => ref.invalidate(workLocationsProvider),
        builder: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(workLocationsProvider);
            await ref.read(workLocationsProvider.future);
          },
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 420,
                      child: StateMessage(
                        icon: Icons.location_city_outlined,
                        title: 'No work locations',
                        message: canCreate
                            ? 'Add one to let staff without a fingerprint '
                                  'device check in from their phone.'
                            : 'None configured yet.',
                        actionLabel: canCreate ? 'Add work location' : null,
                        onAction: canCreate ? () => _openForm(context, ref, null) : null,
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.md,
                    Spacing.md,
                    Spacing.md,
                    Spacing.xxl + Spacing.lg,
                  ),
                  children: [
                    CrmCardList(
                      children: [
                        for (final location in items)
                          ListTile(
                            title: Text(
                              location.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: CrmMetaLine(
                                [
                                  'within ${location.radiusMeters}m',
                                  if (location.staffCount != null)
                                    '${location.staffCount} staff',
                                ].join(' · '),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!location.isActive) ...[
                                  const StatusChip('draft', dense: true),
                                  const SizedBox(width: Spacing.xs),
                                ],
                                if (canUpdate || canDelete)
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                              ],
                            ),
                            onTap: (canUpdate || canDelete)
                                ? () => _openActions(
                                    context,
                                    ref,
                                    location,
                                    canUpdate: canUpdate,
                                    canDelete: canDelete,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              heroTag: 'work-location-fab',
              onPressed: () => _openForm(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Add location'),
            )
          : null,
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    WorkLocation location, {
    required bool canUpdate,
    required bool canDelete,
  }) async {
    final action = await showCrmSheet<_ListAction>(
      context: context,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return CrmSheet(
          eyebrow: 'Work location',
          title: location.name,
          children: [
            CrmCardList(
              children: [
                if (canUpdate)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () => Navigator.of(sheetContext).pop(_ListAction.edit),
                  ),
                if (canDelete)
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text('Delete', style: TextStyle(color: scheme.error)),
                    onTap: () => Navigator.of(sheetContext).pop(_ListAction.delete),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case _ListAction.edit:
        await _openForm(context, ref, location);
      case _ListAction.delete:
        await _delete(context, ref, location);
      case null:
        break;
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    WorkLocation location,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${location.name}?'),
        content: const Text(
          'Staff assigned to it will need a new work location before they '
          'can check in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
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
      await ref.read(adminServiceProvider).deleteWorkLocation(location.id);
      ref.invalidate(workLocationsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Work location deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    WorkLocation? location,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _WorkLocationFormSheet(location: location),
    );
    if (saved == true) ref.invalidate(workLocationsProvider);
  }
}

enum _ListAction { edit, delete }

/// Add or edit a work location. "Use my current location" fills the two
/// coordinate fields from a live GPS read — the same [currentPosition] the
/// staff self-check-in uses — since typing latitude/longitude by hand is
/// exactly the kind of thing an admin standing in the office would rather
/// not do.
class _WorkLocationFormSheet extends ConsumerStatefulWidget {
  const _WorkLocationFormSheet({this.location});

  final WorkLocation? location;

  @override
  ConsumerState<_WorkLocationFormSheet> createState() =>
      _WorkLocationFormSheetState();
}

class _WorkLocationFormSheetState
    extends ConsumerState<_WorkLocationFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _radiusMeters;
  late bool _isActive;
  bool _busy = false;
  bool _locating = false;
  String? _error;

  bool get _editing => widget.location != null;

  @override
  void initState() {
    super.initState();
    final l = widget.location;
    _name = TextEditingController(text: l?.name ?? '');
    _latitude = TextEditingController(
      text: l == null ? '' : l.latitude.toString(),
    );
    _longitude = TextEditingController(
      text: l == null ? '' : l.longitude.toString(),
    );
    _radiusMeters = TextEditingController(text: '${l?.radiusMeters ?? 150}');
    _isActive = l?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radiusMeters.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final position = await currentPosition();
      setState(() {
        _latitude.text = position.latitude.toString();
        _longitude.text = position.longitude.toString();
      });
    } on LocationUnavailable catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    final radius = int.tryParse(_radiusMeters.text.trim());

    String? complaint;
    if (name.isEmpty) {
      complaint = 'A name is required.';
    } else if (latitude == null || latitude < -90 || latitude > 90) {
      complaint = 'Enter a valid latitude.';
    } else if (longitude == null || longitude < -180 || longitude > 180) {
      complaint = 'Enter a valid longitude.';
    } else if (radius == null || radius < 10) {
      complaint = 'Enter a radius of at least 10 metres.';
    }
    if (complaint != null) {
      setState(() => _error = complaint);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final service = ref.read(adminServiceProvider);
      if (_editing) {
        await service.updateWorkLocation(
          widget.location!.id,
          name: name,
          latitude: latitude!,
          longitude: longitude!,
          radiusMeters: radius!,
          isActive: _isActive,
        );
      } else {
        await service.createWorkLocation(
          name: name,
          latitude: latitude!,
          longitude: longitude!,
          radiusMeters: radius!,
          isActive: _isActive,
        );
      }
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _editing ? 'Work location updated.' : 'Work location added.',
          ),
        ),
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
  Widget build(BuildContext context) {
    return CrmSheet(
      eyebrow: 'Work location',
      title: _editing ? 'Edit work location' : 'Add work location',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'e.g. Head Office'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        OutlinedButton.icon(
          icon: _locating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, size: 18),
          label: Text(_locating ? 'Locating…' : 'Use my current location'),
          onPressed: _busy || _locating ? null : _useCurrentLocation,
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: CrmField(
                label: 'Latitude',
                child: TextField(
                  controller: _latitude,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: CrmField(
                label: 'Longitude',
                child: TextField(
                  controller: _longitude,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Radius (metres)',
          child: TextField(
            controller: _radiusMeters,
            enabled: !_busy,
            keyboardType: TextInputType.number,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            'How far from this point a check-in is still accepted.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          value: _isActive,
          onChanged: _busy ? null : (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _editing ? 'Save changes' : 'Add work location',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
