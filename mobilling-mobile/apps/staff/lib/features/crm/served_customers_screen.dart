import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';
import 'field_marketing_screen.dart' show confirmCrmAction;

/// The counter's daily target — `GET /served/target`, null until someone sets
/// one. Declared here because only this screen reads it.
final AutoDisposeFutureProvider<ServedTarget?> servedTargetProvider =
    FutureProvider.autoDispose<ServedTarget?>(
      (ref) => ref.watch(crmServiceProvider).servedTarget(),
    );

/// Walk-in customers served at the counter, plus this week's progress against
/// target. Recording someone served is a counter-staff action, so the form is
/// deliberately short: name, what they came for, optional phone.
class ServedCustomersScreen extends ConsumerStatefulWidget {
  const ServedCustomersScreen({super.key});

  @override
  ConsumerState<ServedCustomersScreen> createState() =>
      _ServedCustomersScreenState();
}

class _ServedCustomersScreenState extends ConsumerState<ServedCustomersScreen> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(servedWeeklySummaryProvider);
    final status = context.statusColors;
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(CrmPermissions.servedCreate) ?? false;
    final canSettings = session?.can(CrmPermissions.servedSettings) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Served customers',
        trailing: (canCreate || canSettings)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canSettings)
                    InkActionButton(
                      icon: Icons.flag_outlined,
                      tooltip: 'Daily target',
                      onPressed: () => _editTarget(context),
                    ),
                  if (canCreate)
                    Padding(
                      padding: EdgeInsets.only(
                        left: canSettings ? Spacing.sm : 0,
                      ),
                      child: InkActionButton(
                        icon: Icons.person_add_alt_1_outlined,
                        tooltip: 'Record a customer',
                        onPressed: () => _recordCustomer(context),
                      ),
                    ),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          summary.maybeWhen(
            data: (s) {
              final metTarget =
                  s.newCustomersTarget != null &&
                  s.newCustomersAchieved >= s.newCustomersTarget!;
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  0,
                ),
                child: Reveal(
                  child: StatRail(
                    items: [
                      StatRailItem(
                        label: 'New this week',
                        value: s.newCustomersTarget == null
                            ? Formatting.integer(s.newCustomersAchieved)
                            : '${Formatting.integer(s.newCustomersAchieved)}'
                                  '/${Formatting.integer(s.newCustomersTarget)}',
                        emphasis: metTarget ? status.settled : null,
                      ),
                      StatRailItem(
                        label: 'Calls this week',
                        value: s.callsTarget == null
                            ? Formatting.integer(s.callsAchieved)
                            : '${Formatting.integer(s.callsAchieved)}'
                                  '/${Formatting.integer(s.callsTarget)}',
                      ),
                    ],
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: PagedListView(
              key: _listKey,
              padding: const EdgeInsets.all(Spacing.md),
              fetch: (page) =>
                  ref.read(crmServiceProvider).servedCustomers(page: page),
              itemBuilder: (context, customer) =>
                  _CustomerCard(customer: customer, onChanged: _reload),
              emptyIcon: Icons.how_to_reg_outlined,
              emptyTitle: 'Nobody logged yet',
              emptyMessage: 'Walk-in customers you serve appear here.',
            ),
          ),
        ],
      ),
    );
  }

  void _reload() {
    _listKey.currentState?.reload();
    ref.invalidate(servedWeeklySummaryProvider);
  }

  Future<void> _recordCustomer(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _ServedCustomerFormSheet(),
    );
    if (saved == true) _reload();
  }

  Future<void> _editTarget(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _ServedTargetSheet(),
    );
    if (saved == true) {
      ref.invalidate(servedTargetProvider);
      ref.invalidate(servedWeeklySummaryProvider);
    }
  }
}

/// One customer served: who and when, what they came for, and — once a
/// follow-up call has been made — how it went.
class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.onChanged});

  final ServedCustomer customer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastFeedback = customer.feedbacks.isEmpty
        ? null
        : customer.feedbacks.first;
    final hasPhone = customer.phone != null;
    final needsCall = lastFeedback == null;
    final canLogFeedback =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.servedCreate) ??
        false;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showCrmSheet<void>(
          context: context,
          builder: (_) =>
              _CustomerSheet(customer: customer, onChanged: onChanged),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            hasPhone || needsCall ? Spacing.xs : Spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customer.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (lastFeedback?.rating != null) ...[
                    const SizedBox(width: Spacing.sm),
                    RatingStars(rating: lastFeedback!.rating, compact: true),
                  ],
                ],
              ),
              const SizedBox(height: Spacing.xs),
              CrmMetaLine(
                [
                  if (customer.servedDate != null)
                    Formatting.date(customer.servedDate),
                  if (customer.createdByName != null)
                    'by ${customer.createdByName}',
                ].join(' · '),
              ),
              if (customer.services.isNotEmpty) ...[
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.xs,
                  runSpacing: Spacing.xs,
                  children: [
                    for (final service in customer.services)
                      Chip(
                        label: Text(service.name.toUpperCase()),
                        labelStyle: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              if (lastFeedback?.outcome != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  'Last call: ${lastFeedback!.outcome}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (hasPhone || needsCall) ...[
                const SizedBox(height: Spacing.xs),
                Row(
                  children: [
                    ContactRow(phone: customer.phone, compact: true),
                    const Spacer(),
                    if (needsCall && canLogFeedback)
                      TextButton.icon(
                        icon: const Icon(
                          Icons.phone_in_talk_outlined,
                          size: 18,
                        ),
                        label: const Text('Log follow-up call'),
                        onPressed: () async {
                          final saved = await showCrmSheet<bool>(
                            context: context,
                            builder: (_) => _FeedbackSheet(customer: customer),
                          );
                          if (saved == true) onChanged();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything you can do to one logged walk-in, opened by tapping its card:
/// what was recorded, the calls made about it, and the correct/remove pair a
/// mistyped entry needs.
class _CustomerSheet extends ConsumerWidget {
  const _CustomerSheet({required this.customer, required this.onChanged});

  final ServedCustomer customer;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(CrmPermissions.servedCreate) ?? false;
    final canUpdate = session?.can(CrmPermissions.servedUpdate) ?? false;
    final canDelete = session?.can(CrmPermissions.servedDelete) ?? false;

    return CrmSheet(
      eyebrow: customer.servedDate == null
          ? 'Served customers'
          : Formatting.date(customer.servedDate),
      title: customer.name,
      children: [
        ContactRow(phone: customer.phone),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Record'),
        const SizedBox(height: Spacing.sm),
        if (customer.phone != null) CrmDetailRow('Phone', customer.phone!),
        if (customer.servedDate != null)
          CrmDetailRow('Served', Formatting.date(customer.servedDate)),
        if (customer.services.isNotEmpty)
          CrmDetailRow(
            'Services',
            customer.services.map((s) => s.name).join(', '),
          ),
        if (customer.notes != null) CrmDetailRow('Notes', customer.notes!),
        if (customer.createdByName != null)
          CrmDetailRow('Recorded by', customer.createdByName!),
        const SizedBox(height: Spacing.lg),
        SectionHeader(
          'Follow-up calls',
          trailing: canCreate
              ? TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log a call'),
                  onPressed: () async {
                    final saved = await showCrmSheet<bool>(
                      context: context,
                      builder: (_) => _FeedbackSheet(customer: customer),
                    );
                    if (saved == true && context.mounted) {
                      onChanged();
                      Navigator.of(context).pop();
                    }
                  },
                )
              : null,
        ),
        const SizedBox(height: Spacing.sm),
        if (customer.feedbacks.isEmpty)
          Text(
            'No calls logged yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          CrmCardList(
            children: [
              for (final feedback in customer.feedbacks)
                ListTile(
                  dense: true,
                  title: Text(
                    _outcomeLabel(feedback.outcome),
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CrmMetaLine(
                        [
                          if (feedback.calledAt != null)
                            Formatting.date(feedback.calledAt),
                          if (feedback.createdByName != null)
                            feedback.createdByName!,
                        ].join(' · '),
                      ),
                      if (feedback.feedback != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          feedback.feedback!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (feedback.rating != null)
                        RatingStars(rating: feedback.rating, compact: true),
                      if (canDelete)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Delete this call',
                          color: status.overdue,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _deleteFeedback(context, ref, feedback),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        if (canUpdate || canDelete) ...[
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              if (canUpdate)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: () async {
                      final saved = await showCrmSheet<bool>(
                        context: context,
                        builder: (_) =>
                            _ServedCustomerFormSheet(customer: customer),
                      );
                      if (saved == true && context.mounted) {
                        onChanged();
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              if (canUpdate && canDelete) const SizedBox(width: Spacing.sm),
              if (canDelete)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: status.overdue,
                    ),
                    onPressed: () => _deleteCustomer(context, ref),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _deleteCustomer(BuildContext context, WidgetRef ref) async {
    final sure = await confirmCrmAction(
      context,
      title: 'Delete the record for ${customer.name}?',
      message:
          'The entry and any calls logged about it come off the week’s count.',
      verb: 'Delete',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(crmServiceProvider).deleteServedCustomer(customer.id);
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Record deleted.')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteFeedback(
    BuildContext context,
    WidgetRef ref,
    ServedFeedback feedback,
  ) async {
    final sure = await confirmCrmAction(
      context,
      title: 'Delete this logged call?',
      message: 'The call comes off ${customer.name}’s history.',
      verb: 'Delete',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .deleteServedFeedback(customer.id, feedback.id);
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Call removed.')));
      // The sheet renders the feedback list it was handed, so close rather
      // than show a stale row.
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  static String _outcomeLabel(String? outcome) {
    for (final (value, label) in ServedFeedbackOutcomes.values) {
      if (value == outcome) return label;
    }
    return outcome ?? 'Called';
  }
}

/// The counter's daily target — one row per tenant, not per person, so this
/// sheet always edits the same record.
class _ServedTargetSheet extends ConsumerStatefulWidget {
  const _ServedTargetSheet();

  @override
  ConsumerState<_ServedTargetSheet> createState() => _ServedTargetSheetState();
}

class _ServedTargetSheetState extends ConsumerState<_ServedTargetSheet> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _newCustomers = TextEditingController(text: '10');
  final _calls = TextEditingController(text: '5');
  final Set<int> _activeDays = {1, 2, 3, 4, 5};

  DateTime _effectiveFrom = DateTime.now();
  bool _loaded = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _newCustomers.dispose();
    _calls.dispose();
    super.dispose();
  }

  /// Seed the form from the stored target the first time it arrives, then
  /// leave the fields alone so a refetch cannot overwrite typing.
  void _seed(ServedTarget? target) {
    if (_loaded || target == null) return;
    _loaded = true;
    _newCustomers.text = '${target.newCustomersTarget}';
    _calls.text = '${target.calledCustomersTarget}';
    if (target.activeDays.isNotEmpty) {
      _activeDays
        ..clear()
        ..addAll(target.activeDays);
    }
    _effectiveFrom = target.effectiveFrom ?? _effectiveFrom;
  }

  Future<void> _submit() async {
    final newCustomers = int.tryParse(_newCustomers.text.trim()) ?? 0;
    final calls = int.tryParse(_calls.text.trim()) ?? 0;
    if (newCustomers < 1 || calls < 1) {
      setState(() => _error = 'Both targets must be at least one a day.');
      return;
    }
    if (_activeDays.isEmpty) {
      setState(() => _error = 'Pick at least one day the target applies to.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(crmServiceProvider)
          .setServedTarget(
            newCustomersTarget: newCustomers,
            calledCustomersTarget: calls,
            activeDays: _activeDays.toList()..sort(),
            effectiveFrom: _effectiveFrom,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Target saved.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = ref.watch(servedTargetProvider);
    _seed(target.valueOrNull);

    return CrmSheet(
      eyebrow: 'Served customers',
      title: target.valueOrNull == null ? 'Set the target' : 'Edit the target',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        if (target.isLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: Spacing.md),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        CrmField(
          label: 'New customers a day',
          child: TextField(
            controller: _newCustomers,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 10'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Follow-up calls a day',
          child: TextField(
            controller: _calls,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 5'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Days the target applies',
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(_dayNames[day - 1].toUpperCase()),
                  selected: _activeDays.contains(day),
                  showCheckmark: false,
                  onSelected: _submitting
                      ? null
                      : (on) => setState(
                          () => on
                              ? _activeDays.add(day)
                              : _activeDays.remove(day),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Effective from',
          value: Formatting.date(_effectiveFrom),
          onTap: _submitting
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _effectiveFrom,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 2, 12, 31),
                  );
                  if (picked != null) {
                    setState(() => _effectiveFrom = picked);
                  }
                },
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'The weekly figures at the top of this screen are measured against '
          'this.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save target',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Record a walk-in, or correct one already recorded.
///
/// `storeCustomer` and `updateCustomer` validate the same fields, so one form
/// serves both; only the date differs, and only because back-dating an entry
/// is a manager's call (`served.change_date`).
class _ServedCustomerFormSheet extends ConsumerStatefulWidget {
  const _ServedCustomerFormSheet({this.customer});

  final ServedCustomer? customer;

  @override
  ConsumerState<_ServedCustomerFormSheet> createState() =>
      _ServedCustomerFormSheetState();
}

class _ServedCustomerFormSheetState
    extends ConsumerState<_ServedCustomerFormSheet> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _notes = TextEditingController(text: widget.customer?.notes ?? '');
  late final Set<String> _serviceIds = {
    ...?widget.customer?.services.map((s) => s.id),
  };

  late DateTime _servedDate = widget.customer?.servedDate ?? DateTime.now();
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.customer != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the customer name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final service = ref.read(crmServiceProvider);
      final phone = _phone.text.trim();
      final notes = _notes.text.trim();
      final customer = widget.customer;
      if (customer == null) {
        await service.recordServedCustomer(
          name: _name.text.trim(),
          serviceIds: _serviceIds.toList(),
          phone: phone.isEmpty ? null : phone,
          servedDate: _servedDate,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await service.updateServedCustomer(
          customer.id,
          name: _name.text.trim(),
          phone: phone,
          servedDate: _servedDate,
          notes: notes,
          serviceIds: _serviceIds.toList(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(
        context,
        _isEdit ? 'Record updated.' : 'Customer recorded.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = ref.watch(servedServicesProvider);
    final canChangeDate =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.servedChangeDate) ??
        false;

    return CrmSheet(
      eyebrow: 'Served customers',
      title: _isEdit ? 'Edit record' : 'Record a customer',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Name',
          child: TextField(
            controller: _name,
            enabled: !_submitting,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Customer’s name'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Phone (optional)',
          child: TextField(
            controller: _phone,
            enabled: !_submitting,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '0712 345 678'),
          ),
        ),
        const SizedBox(height: Spacing.md),
        // Back-dating an entry moves it into another day's count, which is
        // why the web keeps it behind `served.change_date`.
        CrmPickerField(
          label: 'Date served',
          value: Formatting.date(_servedDate),
          onTap: (_submitting || !canChangeDate)
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _servedDate,
                    firstDate: DateTime(now.year - 1),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => _servedDate = picked);
                },
        ),
        if (!canChangeDate) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            'Only managers can change the date served.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Services',
          child: services.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => Text(
              'Could not load services. Close this sheet and try again.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            data: (items) => Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final service in items.where((s) => s.isActive))
                  FilterChip(
                    label: Text(service.name.toUpperCase()),
                    selected: _serviceIds.contains(service.id),
                    showCheckmark: false,
                    onSelected: _submitting
                        ? null
                        : (on) => setState(
                            () => on
                                ? _serviceIds.add(service.id)
                                : _serviceIds.remove(service.id),
                          ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes (optional)',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Anything worth remembering',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting
              ? 'Saving…'
              : (_isEdit ? 'Save changes' : 'Save customer'),
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

class _FeedbackSheet extends ConsumerStatefulWidget {
  const _FeedbackSheet({required this.customer});

  final ServedCustomer customer;

  @override
  ConsumerState<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends ConsumerState<_FeedbackSheet> {
  final _feedback = TextEditingController();
  final _challenges = TextEditingController();

  String _outcome = 'satisfied';
  int? _rating;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    _challenges.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(crmServiceProvider)
          .recordServedFeedback(
            widget.customer.id,
            outcome: _outcome,
            rating: _rating,
            feedback: _feedback.text.trim().isEmpty
                ? null
                : _feedback.text.trim(),
            challenges: _challenges.text.trim().isEmpty
                ? null
                : _challenges.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Feedback saved.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reached = _outcome == 'reached';

    return CrmSheet(
      eyebrow: widget.customer.name,
      title: 'Follow-up call',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Outcome',
          child: DropdownButtonFormField<String>(
            initialValue: _outcome,
            // What `storeFeedback` validates.
            items: [
              for (final (value, label) in ServedFeedbackOutcomes.values)
                DropdownMenuItem(value: value, child: Text(label)),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _outcome = v!),
          ),
        ),
        if (reached) ...[
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Rating',
            child: Align(
              alignment: Alignment.centerLeft,
              child: RatingStars(
                rating: _rating,
                onChanged: (v) => setState(() => _rating = v),
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Feedback',
            child: TextField(
              controller: _feedback,
              enabled: !_submitting,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'How was the service they received?',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Challenges they mentioned',
            child: TextField(
              controller: _challenges,
              enabled: !_submitting,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Anything that got in their way',
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Save call',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
