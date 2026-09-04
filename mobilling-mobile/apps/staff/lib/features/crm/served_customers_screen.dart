import 'dart:async';

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

/// A week's achievement plus its daily breakdown, read from `/served/report`
/// scoped to Monday–Sunday.
///
/// `/served/weekly-summary` (`CrmService.servedWeeklySummary`) takes no
/// parameters and always answers for the current week, so it cannot back a
/// "previous/next week" control. `/served/report` accepts an arbitrary date
/// range and already reports per-day target + percent achieved, so scoping it
/// to one week is how week navigation works without adding anything to the
/// API layer.
final AutoDisposeFutureProviderFamily<ServedReport, int>
_servedWeekReportProvider = FutureProvider.autoDispose
    .family<ServedReport, int>((ref, weekOffset) {
      final start = _weekStart(weekOffset);
      return ref
          .watch(crmServiceProvider)
          .servedReport(
            startDate: start,
            endDate: start.add(const Duration(days: 6)),
          );
    });

/// A calendar month's daily breakdown for the Report tab, keyed by months
/// offset from the current one (0 = this month).
final AutoDisposeFutureProviderFamily<ServedReport, int>
_servedMonthReportProvider = FutureProvider.autoDispose
    .family<ServedReport, int>((ref, monthOffset) {
      final start = _monthAnchor(monthOffset);
      return ref
          .watch(crmServiceProvider)
          .servedReport(startDate: start, endDate: _monthEnd(start));
    });

/// Monday of the ISO week [offset] weeks from the current one (0 = this
/// week), matching the web's `dayjs().isoWeekday(1).add(offset, 'week')`.
DateTime _weekStart(int offset) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  return monday.add(Duration(days: 7 * offset));
}

/// The first of the month [offset] months from the current one (0 = this
/// month).
DateTime _monthAnchor(int offset) {
  final now = DateTime.now();
  return DateTime(now.year, now.month + offset, 1);
}

DateTime _monthEnd(DateTime monthStart) =>
    DateTime(monthStart.year, monthStart.month + 1, 0);

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthLabel(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

/// Green/yellow/red by percent achieved, matching the web's `barColor` /
/// `pctColor` helpers. `null` (no target) reads as neutral, not red.
Color _pctColor(BuildContext context, num? pct) {
  final status = context.statusColors;
  if (pct == null) return Theme.of(context).colorScheme.onSurfaceVariant;
  if (pct >= 100) return status.settled;
  if (pct >= 50) return status.attention;
  return status.overdue;
}

enum _Section { customers, target, report, services }

/// Walk-in customers served at the counter: who was served, this week's and
/// this month's progress against target, and the service types they can be
/// logged under.
///
/// Web: `ServedCustomers.tsx`'s four tabs (Customers / Target / Report /
/// Services). Kept as one screen with an in-page `TabController` here too,
/// rather than four routes, so switching tabs never leaves the module.
class ServedCustomersScreen extends ConsumerStatefulWidget {
  const ServedCustomersScreen({super.key});

  @override
  ConsumerState<ServedCustomersScreen> createState() =>
      _ServedCustomersScreenState();
}

class _ServedCustomersScreenState extends ConsumerState<ServedCustomersScreen>
    with SingleTickerProviderStateMixin {
  final _customersTabKey = GlobalKey<_CustomersTabState>();
  late final List<_Section> _sections;
  late final TabController _tabs;
  late _Section _section;

  @override
  void initState() {
    super.initState();
    // Read once rather than watch: permissions do not change for the life of
    // this screen, and a `TabController`'s length cannot change after the
    // fact anyway.
    final session = ref.read(sessionControllerProvider).session;
    final canRead = session?.can(CrmPermissions.servedRead) ?? false;
    final canSettings = session?.can(CrmPermissions.servedSettings) ?? false;
    _sections = [
      if (canRead) _Section.customers,
      if (canRead) _Section.target,
      if (canRead) _Section.report,
      if (canSettings) _Section.services,
    ];
    // The menu already gates entry to this screen on one of the two
    // permissions above, so an empty list would mean a menu/permission
    // mismatch — fall back to Customers rather than hand a 0-length
    // TabController to the mixin.
    if (_sections.isEmpty) _sections.add(_Section.customers);
    _section = _sections.first;
    _tabs = TabController(length: _sections.length, vsync: this)
      ..addListener(_onTab);
  }

  void _onTab() {
    final next = _sections[_tabs.index];
    if (next != _section) setState(() => _section = next);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).session;
    final canCreate = session?.can(CrmPermissions.servedCreate) ?? false;
    final canSettings = session?.can(CrmPermissions.servedSettings) ?? false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Served customers',
        trailing: switch (_section) {
          _Section.customers when canCreate => InkActionButton(
            icon: Icons.person_add_alt_1_outlined,
            tooltip: 'Record a customer',
            onPressed: () => _recordCustomer(context),
          ),
          _Section.target when canSettings => InkActionButton(
            icon: Icons.flag_outlined,
            tooltip: 'Daily target',
            onPressed: () => _editTarget(context, ref),
          ),
          _Section.services when canSettings => InkActionButton(
            icon: Icons.add,
            tooltip: 'Add a service',
            onPressed: () => _addService(context, ref),
          ),
          _ => null,
        },
        bottom: _sections.length > 1
            ? InkTabBar(
                controller: _tabs,
                tabs: [for (final s in _sections) _sectionLabel(s)],
              )
            : null,
      ),
      body: switch (_section) {
        _Section.customers => _CustomersTab(key: _customersTabKey),
        _Section.target => const _TargetTab(),
        _Section.report => const _ReportTab(),
        _Section.services => const _ServicesTab(),
      },
    );
  }

  static String _sectionLabel(_Section section) => switch (section) {
    _Section.customers => 'Customers',
    _Section.target => 'Target',
    _Section.report => 'Report',
    _Section.services => 'Services',
  };

  Future<void> _recordCustomer(BuildContext context) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _ServedCustomerFormSheet(),
    );
    if (saved == true) _customersTabKey.currentState?.reload();
  }
}

/// Set or edit the daily target, and refresh everything it feeds: the
/// target itself plus every week/month report already fetched (an offset a
/// viewer isn't currently looking at should not go stale silently).
Future<void> _editTarget(BuildContext context, WidgetRef ref) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => const _ServedTargetSheet(),
  );
  if (saved == true) {
    ref.invalidate(servedTargetProvider);
    ref.invalidate(_servedWeekReportProvider);
    ref.invalidate(_servedMonthReportProvider);
  }
}

// ─────────────────────────────────────────────────────────────
// Customers tab
// ─────────────────────────────────────────────────────────────

/// The walk-in log: search, a date filter, a running record count, and the
/// infinite-scroll list itself. All three fetch parameters are already
/// accepted by [CrmService.servedCustomers] — this tab is what was missing to
/// reach them.
class _CustomersTab extends ConsumerStatefulWidget {
  const _CustomersTab({super.key});

  @override
  ConsumerState<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends ConsumerState<_CustomersTab> {
  final _listKey = GlobalKey<PagedListViewState>();
  final _search = TextEditingController();
  Timer? _debounce;
  DateTime? _dateFilter;
  int _total = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void reload() => _listKey.currentState?.reload();

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), reload);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateFilter = picked);
      reload();
    }
  }

  void _clearDate() {
    setState(() => _dateFilter = null);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search name or phone',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined, size: 15),
                      label: Text(
                        _dateFilter == null
                            ? 'Filter by date'
                            : Formatting.date(_dateFilter),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _pickDate,
                    ),
                  ),
                  if (_dateFilter != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear date filter',
                      visualDensity: VisualDensity.compact,
                      onPressed: _clearDate,
                    ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    '$_total record${_total == 1 ? '' : 's'}',
                    style: muted,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.md,
            ),
            fetch: (page) async {
              final result = await ref
                  .read(crmServiceProvider)
                  .servedCustomers(
                    search: _search.text.trim().isEmpty
                        ? null
                        : _search.text.trim(),
                    date: _dateFilter,
                    page: page,
                  );
              if (mounted) setState(() => _total = result.total);
              return result;
            },
            itemBuilder: (context, customer) =>
                _CustomerCard(customer: customer, onChanged: reload),
            emptyIcon: Icons.how_to_reg_outlined,
            emptyTitle: 'Nobody logged yet',
            emptyMessage: 'Walk-in customers you serve appear here.',
          ),
        ),
      ],
    );
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

// ─────────────────────────────────────────────────────────────
// Target tab
// ─────────────────────────────────────────────────────────────

/// Progress against the daily target, one week at a time, with the 7-day
/// breakdown the web shows and the mobile screen previously fetched
/// ([ServedWeeklySummary.daily]) without ever rendering.
class _TargetTab extends ConsumerStatefulWidget {
  const _TargetTab();

  @override
  ConsumerState<_TargetTab> createState() => _TargetTabState();
}

class _TargetTabState extends ConsumerState<_TargetTab> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = ref.watch(servedTargetProvider);
    final weekStart = _weekStart(_weekOffset);
    final weekEnd = weekStart.add(const Duration(days: 6));

    return ListView(
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous week',
              onPressed: () => setState(() => _weekOffset -= 1),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${Formatting.date(weekStart)} – ${Formatting.date(weekEnd)}',
                    style: theme.textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (_weekOffset != 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => setState(() => _weekOffset = 0),
                      child: const Text('This week'),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next week',
              onPressed: () => setState(() => _weekOffset += 1),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        target.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ErrorBanner(
            message: error is ApiException
                ? error.message
                : 'Could not load the target.',
          ),
          data: (t) {
            if (t == null) {
              final canSettings =
                  ref
                      .watch(sessionControllerProvider)
                      .session
                      ?.can(CrmPermissions.servedSettings) ??
                  false;
              return StateMessage(
                icon: Icons.flag_outlined,
                title: 'No target set yet',
                message: 'Set a daily target to track progress here.',
                actionLabel: canSettings ? 'Set target' : null,
                onAction: canSettings
                    ? () => _editTarget(context, ref)
                    : null,
              );
            }

            final report = ref.watch(_servedWeekReportProvider(_weekOffset));
            return report.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorBanner(
                message: error is ApiException
                    ? error.message
                    : 'Could not load this week.',
              ),
              data: (r) => _TargetProgress(target: t, report: r),
            );
          },
        ),
      ],
    );
  }
}

class _TargetProgress extends StatelessWidget {
  const _TargetProgress({required this.target, required this.report});

  final ServedTarget target;
  final ServedReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProgressRow(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'New customers',
                  perDay: target.newCustomersTarget,
                  achieved: report.newCustomersAchieved,
                  target: report.newCustomersTarget,
                ),
                const SizedBox(height: Spacing.md),
                _ProgressRow(
                  icon: Icons.call_outlined,
                  label: 'Customers called',
                  perDay: target.calledCustomersTarget,
                  achieved: report.callsAchieved,
                  target: report.callsTarget,
                ),
              ],
            ),
          ),
        ),
        if (report.daily.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          const SectionHeader('Daily breakdown'),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              for (final day in report.daily)
                Expanded(child: _DayCell(day: day)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.icon,
    required this.label,
    required this.perDay,
    required this.achieved,
    required this.target,
  });

  final IconData icon;
  final String label;
  final int perDay;
  final int achieved;
  final int target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = target > 0 ? (achieved / target * 100) : null;
    final color = _pctColor(context, pct);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  const SizedBox(width: 4),
                  Text(
                    '($perDay/day)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$achieved / $target',
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: LinearProgressIndicator(
            value: pct == null ? 0 : (pct / 100).clamp(0, 1).toDouble(),
            minHeight: 6,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// One day of the week strip: day name, whether the target even applies that
/// day, and the two counts — greyed out on an inactive day, as the web does.
class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});

  final ServedReportDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Opacity(
      opacity: day.isActive ? 1 : 0.4,
      child: Column(
        children: [
          Text(
            day.dayName.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          CircleAvatar(
            radius: 14,
            backgroundColor: day.isActive
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            child: Text(
              '${day.newCustomers}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${day.callsMade} calls',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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

// ─────────────────────────────────────────────────────────────
// Report tab
// ─────────────────────────────────────────────────────────────

/// A calendar month's daily achievement vs target, grouped by ISO week —
/// the mobile equivalent of the web's month-scoped report table. The web
/// also allows an arbitrary date range; a month picker is the simplification
/// made here, since every other date-scoped screen in this app already pages
/// by month rather than offering a free-form range.
class _ReportTab extends ConsumerStatefulWidget {
  const _ReportTab();

  @override
  ConsumerState<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends ConsumerState<_ReportTab> {
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = _monthAnchor(_monthOffset);
    final reportAsync = ref.watch(_servedMonthReportProvider(_monthOffset));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous month',
                onPressed: () => setState(() => _monthOffset -= 1),
              ),
              Expanded(
                child: Text(
                  _monthLabel(month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next month',
                onPressed: () => setState(() => _monthOffset += 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: reportAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => StateMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load the report',
              message: error is ApiException ? error.message : null,
              actionLabel: 'Retry',
              onAction: () =>
                  ref.invalidate(_servedMonthReportProvider(_monthOffset)),
            ),
            data: (report) => _ReportBody(report: report),
          ),
        ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final ServedReport report;

  @override
  Widget build(BuildContext context) {
    final weeks = <int, List<ServedReportDay>>{};
    for (final day in report.daily) {
      weeks.putIfAbsent(day.week, () => []).add(day);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        0,
        Spacing.md,
        Spacing.xl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _ReportSummaryCard(
                label: 'New customers',
                achieved: report.newCustomersAchieved,
                target: report.newCustomersTarget,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: _ReportSummaryCard(
                label: 'Calls made',
                achieved: report.callsAchieved,
                target: report.callsTarget,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        for (final entry in weeks.entries) ...[
          _WeekReportCard(week: entry.key, days: entry.value),
          const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({
    required this.label,
    required this.achieved,
    required this.target,
  });

  final String label;
  final int achieved;
  final int target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = target > 0 ? (achieved / target * 100).round() : null;
    final color = _pctColor(context, pct);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(Formatting.integer(achieved), style: Type.display(24)),
            Text(
              'Target: ${Formatting.integer(target)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (pct != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                '$pct%',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One ISO week's days, with a bold subtotal header — the card-list
/// restatement of the web's per-week table subtotal row.
class _WeekReportCard extends StatelessWidget {
  const _WeekReportCard({required this.week, required this.days});

  final int week;
  final List<ServedReportDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newTotal = days.fold<int>(0, (s, d) => s + d.newCustomers);
    final newTargetTotal = days.fold<int>(0, (s, d) => s + d.newTarget);
    final callsTotal = days.fold<int>(0, (s, d) => s + d.callsMade);
    final callsTargetTotal = days.fold<int>(0, (s, d) => s + d.callsTarget);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  'WEEK $week',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$newTotal/$newTargetTotal new · $callsTotal/$callsTargetTotal calls',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final (index, day) in days.indexed) ...[
            if (index > 0) const Divider(height: 1),
            _ReportDayRow(day: day),
          ],
        ],
      ),
    );
  }
}

class _ReportDayRow extends StatelessWidget {
  const _ReportDayRow({required this.day});

  final ServedReportDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Opacity(
      opacity: day.isActive ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                Formatting.date(day.date),
                style: theme.textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 32,
              child: Text(
                day.dayName.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (day.isActive) ...[
              Expanded(
                child: _MetricPair(
                  label: 'New',
                  value: day.newCustomers,
                  target: day.newTarget,
                  pct: day.newPct,
                ),
              ),
              Expanded(
                child: _MetricPair(
                  label: 'Calls',
                  value: day.callsMade,
                  target: day.callsTarget,
                  pct: day.callsPct,
                ),
              ),
            ] else
              Expanded(
                child: Text(
                  'Inactive',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({
    required this.label,
    required this.value,
    required this.target,
    required this.pct,
  });

  final String label;
  final int value;
  final int target;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = target > 0 ? _pctColor(context, pct) : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          '$value/$target',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Services tab
// ─────────────────────────────────────────────────────────────

enum _ServiceAction { edit, toggleActive, moveUp, moveDown, delete }

/// The service types walk-ins can be logged under — a short,
/// rarely-touched settings list, so this follows [MarketingServicesScreen]'s
/// row-plus-sheet shape rather than an infinite-scroll list.
class _ServicesTab extends ConsumerWidget {
  const _ServicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.servedSettings) ??
        false;
    final servicesAsync = ref.watch(servedServicesProvider);

    return CrmAsyncView(
      value: servicesAsync,
      errorTitle: 'Could not load services',
      onRetry: () => ref.invalidate(servedServicesProvider),
      builder: (items) => items.isEmpty
          ? StateMessage(
              icon: Icons.design_services_outlined,
              title: 'No services yet',
              message: 'Add the services walk-ins can be logged under.',
              actionLabel: canManage ? 'Add a service' : null,
              onAction: canManage ? () => _addService(context, ref) : null,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.md,
                Spacing.md,
                Spacing.xl,
              ),
              children: [
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
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                service.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!service.isActive) ...[
                              const SizedBox(width: Spacing.sm),
                              StatusChip('inactive', dense: true),
                            ],
                          ],
                        ),
                        subtitle: service.description == null
                            ? null
                            : Text(
                                service.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: canManage
                            ? Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: theme.colorScheme.outline,
                              )
                            : null,
                        onTap: canManage
                            ? () => _openActions(context, ref, items, index)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    List<ServedService> items,
    int index,
  ) async {
    final service = items[index];
    final action = await showCrmSheet<_ServiceAction>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return CrmSheet(
          eyebrow: 'Served customers',
          title: service.name,
          children: [
            CrmCardList(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text('Edit', style: theme.textTheme.titleSmall),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_ServiceAction.edit),
                ),
                ListTile(
                  leading: Icon(
                    service.isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(
                    service.isActive ? 'Mark inactive' : 'Mark active',
                    style: theme.textTheme.titleSmall,
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_ServiceAction.toggleActive),
                ),
                if (index > 0)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: Text('Move up', style: theme.textTheme.titleSmall),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ServiceAction.moveUp),
                  ),
                if (index < items.length - 1)
                  ListTile(
                    leading: const Icon(Icons.arrow_downward),
                    title: Text(
                      'Move down',
                      style: theme.textTheme.titleSmall,
                    ),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ServiceAction.moveDown),
                  ),
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
        await _editService(context, ref, service);
      case _ServiceAction.toggleActive:
        await _toggleActive(context, ref, service);
      case _ServiceAction.moveUp:
        await _reorder(context, ref, items, index, index - 1);
      case _ServiceAction.moveDown:
        await _reorder(context, ref, items, index, index + 1);
      case _ServiceAction.delete:
        await _deleteService(context, ref, service);
      case null:
        break;
    }
  }

  Future<void> _editService(
    BuildContext context,
    WidgetRef ref,
    ServedService service,
  ) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _ServedServiceFormSheet(service: service),
    );
    if (saved == true) ref.invalidate(servedServicesProvider);
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    ServedService service,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .updateServedService(service.id, isActive: !service.isActive);
      ref.invalidate(servedServicesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// There is no bulk reorder endpoint for served services (unlike marketing
  /// services' `/reorder`), so a move is a sequential `sort_order` rewrite of
  /// the whole list — fine for a settings list this short.
  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    List<ServedService> items,
    int from,
    int to,
  ) async {
    final reordered = [...items];
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(crmServiceProvider);
      for (final (index, item) in reordered.indexed) {
        if (item.sortOrder != index) {
          await service.updateServedService(item.id, sortOrder: index);
        }
      }
      ref.invalidate(servedServicesProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteService(
    BuildContext context,
    WidgetRef ref,
    ServedService service,
  ) async {
    final sure = await confirmCrmAction(
      context,
      title: 'Delete "${service.name}"?',
      message:
          'Walk-ins already logged under it keep the record; new ones can '
          'no longer choose it.',
      verb: 'Delete',
    );
    if (!sure || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(crmServiceProvider).deleteServedService(service.id);
      ref.invalidate(servedServicesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${service.name} deleted.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

Future<void> _addService(BuildContext context, WidgetRef ref) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => const _ServedServiceFormSheet(),
  );
  if (saved == true) ref.invalidate(servedServicesProvider);
}

class _ServedServiceFormSheet extends ConsumerStatefulWidget {
  const _ServedServiceFormSheet({this.service});

  final ServedService? service;

  @override
  ConsumerState<_ServedServiceFormSheet> createState() =>
      _ServedServiceFormSheetState();
}

class _ServedServiceFormSheetState
    extends ConsumerState<_ServedServiceFormSheet> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _description = TextEditingController(
    text: widget.service?.description ?? '',
  );
  late bool _isActive = widget.service?.isActive ?? true;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.service != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the service a name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(crmServiceProvider);
      final description = _description.text.trim();
      if (_isEdit) {
        await service.updateServedService(
          widget.service!.id,
          name: name,
          description: description.isEmpty ? null : description,
          isActive: _isActive,
        );
      } else {
        await service.createServedService(
          name: name,
          description: description.isEmpty ? null : description,
          isActive: _isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(
        context,
        _isEdit ? 'Service updated.' : 'Service added.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('name') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Served customers',
    title: _isEdit ? 'Edit service' : 'Add a service',
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
          decoration: const InputDecoration(hintText: 'e.g. Consultation'),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Description (optional)',
        child: TextField(
          controller: _description,
          enabled: !_submitting,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Shown to staff recording a walk-in',
          ),
        ),
      ),
      const SizedBox(height: Spacing.md),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Active'),
        subtitle: const Text(
          'Inactive services no longer appear on the record form.',
        ),
        value: _isActive,
        onChanged: _submitting ? null : (v) => setState(() => _isActive = v),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting
            ? 'Saving…'
            : (_isEdit ? 'Save changes' : 'Add service'),
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}
