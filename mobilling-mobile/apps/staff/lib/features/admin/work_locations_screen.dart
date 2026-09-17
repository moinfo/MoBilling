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
    final canAssignStaff = session?.can(AdminPermissions.users) ?? false;
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
                                if (canUpdate || canDelete || canAssignStaff)
                                  Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: scheme.outline,
                                  ),
                              ],
                            ),
                            onTap: (canUpdate || canDelete || canAssignStaff)
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
    final canAssignStaff =
        ref.read(sessionControllerProvider).session?.can(AdminPermissions.users) ??
        false;
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
                if (canAssignStaff)
                  ListTile(
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Assign staff'),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ListAction.assignStaff),
                  ),
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
      case _ListAction.assignStaff:
        await _openAssignStaff(context, ref, location);
      case _ListAction.edit:
        await _openForm(context, ref, location);
      case _ListAction.delete:
        await _delete(context, ref, location);
      case null:
        break;
    }
  }

  Future<void> _openAssignStaff(
    BuildContext context,
    WidgetRef ref,
    WorkLocation location,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (_) => _AssignStaffSheet(location: location),
    );
    ref.invalidate(workLocationsProvider);
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

enum _ListAction { assignStaff, edit, delete }

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

// ---------------------------------------------------------------------------
// Assign staff — the other side of the same relationship the Team edit
// sheet's "Work location" picker sets, reachable from here too now that
// admins expect to hand out a location's staff from the location itself.
// ---------------------------------------------------------------------------

/// Every active staff member, with a switch for whether *this* location is
/// theirs. Flipping a switch calls `PUT /users/{id}` immediately — there is
/// no separate save step, the same as every other toggle in this app.
class _AssignStaffSheet extends ConsumerStatefulWidget {
  const _AssignStaffSheet({required this.location});

  final WorkLocation location;

  @override
  ConsumerState<_AssignStaffSheet> createState() => _AssignStaffSheetState();
}

class _AssignStaffSheetState extends ConsumerState<_AssignStaffSheet> {
  final _search = TextEditingController();
  List<StaffUser> _results = const [];
  final Set<String> _busy = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(adminServiceProvider)
          .users(
            search: _search.text.trim().isEmpty ? null : _search.text.trim(),
            perPage: 200,
          );
      if (mounted) {
        setState(() => _results = page.items.where((u) => u.isActive).toList());
      }
    } on ApiException {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(StaffUser user, bool assign) async {
    setState(() => _busy.add(user.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminServiceProvider)
          .updateUser(
            user.id,
            workLocationId: assign ? widget.location.id : null,
            clearWorkLocation: !assign,
          );
      if (!mounted) return;
      setState(() {
        final index = _results.indexOf(user);
        if (index != -1) {
          _results[index] = StaffUser(
            id: user.id,
            name: user.name,
            isActive: user.isActive,
            email: user.email,
            phone: user.phone,
            roleName: user.roleName,
            roleId: user.roleId,
            lastLoginAt: user.lastLoginAt,
            workLocationId: assign ? widget.location.id : null,
            workLocationName: assign ? widget.location.name : null,
            attendanceDeviceModel: user.attendanceDeviceModel,
            attendanceDeviceBoundAt: user.attendanceDeviceBoundAt,
          );
        }
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: sheetBottomInset(context) + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WORK LOCATION',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Assign staff — ${widget.location.name}',
            style: Type.display(22, color: scheme.onSurface),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _search,
            autofocus: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _load,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_results.isEmpty)
            const StateMessage(
              icon: Icons.search_off_outlined,
              title: 'No matches',
              message: 'Try a different spelling, or fewer words.',
            )
          else
            Flexible(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    final assignedHere = user.workLocationId == widget.location.id;
                    final elsewhere =
                        !assignedHere && user.workLocationName != null;
                    return SwitchListTile(
                      title: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: elsewhere
                          ? Text(
                              'Currently ${user.workLocationName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      value: assignedHere,
                      onChanged: _busy.contains(user.id)
                          ? null
                          : (v) => _toggle(user, v),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
