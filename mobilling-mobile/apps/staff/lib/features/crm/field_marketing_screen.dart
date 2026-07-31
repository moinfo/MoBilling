import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import 'crm_providers.dart';
import 'crm_ui.dart';

/// Field marketing: canvassing sessions, the businesses visited, and monthly
/// conversion targets.
///
/// A *session* is one officer's day in one area; *visits* hang off it. Logging
/// a visit therefore needs a session first, which is why the Sessions tab has
/// the create action and visits are logged from a session's detail screen.
class FieldMarketingScreen extends ConsumerStatefulWidget {
  const FieldMarketingScreen({super.key});

  @override
  ConsumerState<FieldMarketingScreen> createState() =>
      _FieldMarketingScreenState();
}

enum _Section { sessions, visits, targets }

class _FieldMarketingScreenState extends ConsumerState<FieldMarketingScreen> {
  _Section _section = _Section.sessions;

  @override
  Widget build(BuildContext context) {
    final canCreateSession = ref.watch(sessionControllerProvider).session?.can(
              CrmPermissions.fieldSessionsCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(title: const Text('Field marketing')),
      floatingActionButton:
          _section == _Section.sessions && canCreateSession
              ? FloatingActionButton.extended(
                  onPressed: () => _startSession(context),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('New session'),
                )
              : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.xs),
            child: SegmentedButton<_Section>(
              segments: const [
                ButtonSegment(
                    value: _Section.sessions, label: Text('Sessions')),
                ButtonSegment(value: _Section.visits, label: Text('Visits')),
                ButtonSegment(value: _Section.targets, label: Text('Targets')),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: switch (_section) {
              _Section.sessions => const _SessionsList(),
              _Section.visits => const _VisitsList(),
              _Section.targets => const _TargetsList(),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _startSession(BuildContext context) async {
    final area = TextEditingController();
    var date = DateTime.now();

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Start a session',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: area,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Area',
                  helperText: 'Where are you canvassing today?',
                ),
              ),
              const SizedBox(height: Spacing.md),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: date,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setSheetState(() => date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  child: Text(Formatting.date(date)),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: () async {
                  if (area.text.trim().isEmpty) return;
                  try {
                    await ref.read(crmServiceProvider).createFieldSession(
                          area: area.text.trim(),
                          visitDate: date,
                        );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop(true);
                    }
                  } on ApiException catch (e) {
                    if (sheetContext.mounted) {
                      showCrmMessage(sheetContext, e.message);
                    }
                  }
                },
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );

    if (created == true) setState(() {});
  }
}

class _SessionsList extends ConsumerStatefulWidget {
  const _SessionsList();

  @override
  ConsumerState<_SessionsList> createState() => _SessionsListState();
}

class _SessionsListState extends ConsumerState<_SessionsList> {
  final _listKey = GlobalKey<PagedListViewState>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PagedListView(
      key: _listKey,
      fetch: (page) =>
          ref.read(crmServiceProvider).fieldSessions(page: page),
      itemBuilder: (context, session) => Card(
        child: ListTile(
          title: Text(session.area),
          subtitle: Text(
            [
              if (session.visitDate != null)
                Formatting.date(session.visitDate),
              if (session.officerName != null) session.officerName!,
              '${session.visitsCount} visit${session.visitsCount == 1 ? '' : 's'}',
              if (session.convertedCount > 0)
                '${session.convertedCount} converted',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/field-marketing/${session.id}'),
        ),
      ),
      emptyIcon: Icons.place_outlined,
      emptyTitle: 'No sessions yet',
      emptyMessage: 'Start a session to log the businesses you visit.',
    );
  }
}

class _VisitsList extends ConsumerStatefulWidget {
  const _VisitsList();

  @override
  ConsumerState<_VisitsList> createState() => _VisitsListState();
}

class _VisitsListState extends ConsumerState<_VisitsList> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _status;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('interested', 'Interested'),
    ('not_interested', 'Not interested'),
    ('converted', 'Converted'),
    ('follow_up', 'Follow-up'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        FilterStrip(
          options: _filters,
          selected: _status,
          onSelect: (v) {
            setState(() => _status = v);
            _listKey.currentState?.reload();
          },
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref
                .read(crmServiceProvider)
                .allFieldVisits(status: _status, page: page),
            itemBuilder: (context, visit) => Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(visit.businessName,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        StatusChip(visit.status, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (visit.area != null) visit.area!,
                        if (visit.visitDate != null)
                          Formatting.date(visit.visitDate),
                        if (visit.officerName != null) visit.officerName!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (visit.nextFollowupDate != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'Follow up ${Formatting.date(visit.nextFollowupDate)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.statusColors.attention),
                      ),
                    ],
                    if (visit.phone != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ContactRow(phone: visit.phone, compact: true),
                      ),
                  ],
                ),
              ),
            ),
            emptyIcon: Icons.storefront_outlined,
            emptyTitle: 'No visits logged',
          ),
        ),
      ],
    );
  }
}

class _TargetsList extends ConsumerWidget {
  const _TargetsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(fieldTargetsProvider);
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: targets,
      errorTitle: 'Could not load targets',
      onRetry: () => ref.invalidate(fieldTargetsProvider),
      builder: (items) => items.isEmpty
          ? const StateMessage(
              icon: Icons.flag_outlined,
              title: 'No targets set',
              message: 'Monthly conversion targets appear here once set.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(Spacing.md),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Spacing.sm),
              itemBuilder: (context, index) {
                final target = items[index];
                final ratio = target.targetClients <= 0
                    ? 0.0
                    : (target.wonClients / target.targetClients).clamp(0.0, 1.0);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(target.officerName ?? 'Team',
                                  style: theme.textTheme.titleSmall),
                            ),
                            Text('${target.wonClients}/${target.targetClients}',
                                style: theme.textTheme.labelLarge),
                          ],
                        ),
                        const SizedBox(height: Spacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 8,
                            color: ratio >= 1
                                ? context.statusColors.settled
                                : null,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          '${target.totalVisits} visit${target.totalVisits == 1 ? '' : 's'} · ${target.progress}% of target',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// A session and the businesses visited in it, with the log-a-visit action.
class FieldSessionScreen extends ConsumerStatefulWidget {
  const FieldSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<FieldSessionScreen> createState() => _FieldSessionScreenState();
}

class _FieldSessionScreenState extends ConsumerState<FieldSessionScreen> {
  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(fieldSessionProvider(widget.sessionId));
    final theme = Theme.of(context);
    final canLogVisit = ref.watch(sessionControllerProvider).session?.can(
              CrmPermissions.fieldVisitsCreate,
            ) ??
        false;

    return Scaffold(
      appBar: AppBar(
          title: Text(detail.valueOrNull?.session.area ?? 'Session')),
      floatingActionButton: !canLogVisit
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _logVisit(context),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Log visit'),
            ),
      body: CrmAsyncView(
        value: detail,
        errorTitle: 'Could not load this session',
        onRetry: () => ref.invalidate(fieldSessionProvider(widget.sessionId)),
        builder: (data) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                      label: 'Visits', value: '${data.session.visitsCount}'),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: StatTile(
                      label: 'Interested',
                      value: '${data.session.interestedCount}'),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: StatTile(
                    label: 'Converted',
                    value: '${data.session.convertedCount}',
                    emphasis: data.session.convertedCount > 0
                        ? context.statusColors.settled
                        : null,
                  ),
                ),
              ],
            ),
            if (data.session.summary != null) ...[
              const SizedBox(height: Spacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Summary', style: theme.textTheme.titleSmall),
                      const SizedBox(height: Spacing.xs),
                      Text(data.session.summary!,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            Text('Businesses visited', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (data.visits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(
                  child: Text('Nothing logged yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              )
            else
              for (final visit in data.visits)
                Card(
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  child: ListTile(
                    title: Text(visit.businessName),
                    subtitle: Text(
                      [
                        if (visit.location != null) visit.location!,
                        if (visit.services.isNotEmpty)
                          visit.services.join(', '),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusChip(visit.status, dense: true),
                        if (visit.phone != null)
                          ContactRow(phone: visit.phone, compact: true),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _logVisit(BuildContext context) async {
    final name = TextEditingController();
    final location = TextEditingController();
    final phone = TextEditingController();
    final feedback = TextEditingController();
    var status = 'interested';
    var submitting = false;
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Log a visit',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: Spacing.md),
                if (error != null) ...[
                  ErrorBanner(message: error!),
                  const SizedBox(height: Spacing.sm),
                ],
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Business name'),
                ),
                const SizedBox(height: Spacing.md),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Outcome'),
                  items: const [
                    DropdownMenuItem(
                        value: 'interested', child: Text('Interested')),
                    DropdownMenuItem(
                        value: 'not_interested',
                        child: Text('Not interested')),
                    DropdownMenuItem(
                        value: 'follow_up', child: Text('Needs follow-up')),
                    DropdownMenuItem(
                        value: 'converted', child: Text('Converted')),
                  ],
                  onChanged: (v) => setSheetState(() => status = v!),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: location,
                  decoration:
                      const InputDecoration(labelText: 'Location (optional)'),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: feedback,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'What did they say?'),
                ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (name.text.trim().isEmpty) {
                            setSheetState(
                                () => error = 'Enter the business name.');
                            return;
                          }
                          setSheetState(() {
                            submitting = true;
                            error = null;
                          });
                          try {
                            await ref
                                .read(crmServiceProvider)
                                .logFieldVisit(
                                  widget.sessionId,
                                  businessName: name.text.trim(),
                                  status: status,
                                  location: location.text.trim().isEmpty
                                      ? null
                                      : location.text.trim(),
                                  phone: phone.text.trim().isEmpty
                                      ? null
                                      : phone.text.trim(),
                                  feedback: feedback.text.trim().isEmpty
                                      ? null
                                      : feedback.text.trim(),
                                );
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop(true);
                            }
                          } on ApiException catch (e) {
                            setSheetState(() {
                              submitting = false;
                              error = e.message;
                            });
                          }
                        },
                  child: Text(submitting ? 'Saving…' : 'Save visit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) ref.invalidate(fieldSessionProvider(widget.sessionId));
  }
}
