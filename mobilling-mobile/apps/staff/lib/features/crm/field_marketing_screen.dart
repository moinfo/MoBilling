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

class _FieldMarketingScreenState extends ConsumerState<FieldMarketingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTab);
  _Section _section = _Section.sessions;

  void _onTab() {
    final next = _Section.values[_tabs.index];
    if (next != _section) setState(() => _section = next);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreateSession =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.fieldSessionsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Field marketing',
        trailing: _section == _Section.sessions && canCreateSession
            ? InkActionButton(
                icon: Icons.add_location_alt_outlined,
                tooltip: 'Start a session',
                onPressed: () => _startSession(context),
              )
            : null,
        bottom: InkTabBar(
          tabs: const ['Sessions', 'Visits', 'Targets'],
          controller: _tabs,
        ),
      ),
      body: switch (_section) {
        _Section.sessions => const _SessionsList(),
        _Section.visits => const _VisitsList(),
        _Section.targets => const _TargetsList(),
      },
    );
  }

  Future<void> _startSession(BuildContext context) async {
    final area = TextEditingController();
    var date = DateTime.now();
    var submitting = false;
    String? error;

    final created = await showCrmSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => CrmSheet(
          eyebrow: 'Field marketing',
          title: 'Start a session',
          children: [
            if (error != null) ...[
              ErrorBanner(message: error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Area',
              child: TextField(
                controller: area,
                enabled: !submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Where are you canvassing today?',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Date',
              value: Formatting.date(date),
              onTap: submitting
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: date,
                        firstDate: DateTime(DateTime.now().year - 1),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSheetState(() => date = picked);
                    },
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: submitting ? 'Starting…' : 'Start session',
              busy: submitting,
              onPressed: submitting
                  ? null
                  : () async {
                      if (area.text.trim().isEmpty) {
                        setSheetState(
                          () => error = 'Enter the area you are canvassing.',
                        );
                        return;
                      }
                      setSheetState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        final me = ref.read(currentUserProvider);
                        if (me == null) return;
                        await ref
                            .read(crmServiceProvider)
                            .createFieldSession(
                              officerId: me.id,
                              area: area.text.trim(),
                              visitDate: date,
                            );
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop(true);
                        }
                      } on ApiException catch (e) {
                        if (sheetContext.mounted) {
                          setSheetState(() {
                            submitting = false;
                            error = e.message;
                          });
                        }
                      }
                    },
            ),
          ],
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
      fetch: (page) => ref.read(crmServiceProvider).fieldSessions(page: page),
      itemBuilder: (context, session) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(
            session.area,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Spacing.xs),
              CrmMetaLine(
                [
                  if (session.visitDate != null)
                    Formatting.date(session.visitDate),
                  '${Formatting.integer(session.visitsCount)} '
                      '${session.visitsCount == 1 ? 'visit' : 'visits'}',
                  if (session.convertedCount > 0)
                    '${Formatting.integer(session.convertedCount)} converted',
                ].join(' · '),
              ),
              if (session.officerName != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(session.officerName!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: theme.colorScheme.outline,
          ),
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
    final status = context.statusColors;

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
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.xl,
            ),
            fetch: (page) => ref
                .read(crmServiceProvider)
                .allFieldVisits(status: _status, page: page),
            itemBuilder: (context, visit) => Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                title: Text(
                  visit.businessName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.xs),
                    CrmStatusLine(
                      status: visit.status,
                      meta: [
                        if (visit.area != null) visit.area!,
                        if (visit.visitDate != null)
                          Formatting.date(visit.visitDate),
                      ].join(' · '),
                    ),
                    if (visit.officerName != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        visit.officerName!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (visit.nextFollowupDate != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'Follow up ${Formatting.date(visit.nextFollowupDate)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: status.attention,
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: ContactRow(phone: visit.phone, compact: true),
              ),
            ),
            emptyIcon: Icons.storefront_outlined,
            emptyTitle: 'No visits logged',
            emptyMessage: 'Open a session and log the businesses you visit.',
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
          : ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                CrmCardList(
                  children: [
                    for (final target in items) _TargetRow(target: target),
                  ],
                ),
              ],
            ),
    );
  }
}

/// One officer's month against target: won over target as the figure, the
/// bar for the glance, visits and percentage in the metadata line.
class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target});

  final FieldTarget target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final ratio = target.targetClients <= 0
        ? 0.0
        : (target.wonClients / target.targetClients).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  target.officerName ?? 'Team',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '${Formatting.integer(target.wonClients)}'
                '/${Formatting.integer(target.targetClients)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: Type.figures,
                  color: ratio >= 1 ? status.settled : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: ratio >= 1 ? status.settled : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          CrmMetaLine(
            '${Formatting.integer(target.totalVisits)} '
            '${target.totalVisits == 1 ? 'visit' : 'visits'}'
            ' · ${target.progress}% of target',
          ),
        ],
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
    final status = context.statusColors;
    final canLogVisit =
        ref
            .watch(sessionControllerProvider)
            .session
            ?.can(CrmPermissions.fieldVisitsCreate) ??
        false;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Field marketing',
        title: detail.valueOrNull?.session.area ?? 'Session',
        trailing: canLogVisit
            ? InkActionButton(
                icon: Icons.add_business_outlined,
                tooltip: 'Log a visit',
                onPressed: () => _logVisit(context),
              )
            : null,
      ),
      body: CrmAsyncView(
        value: detail,
        errorTitle: 'Could not load this session',
        onRetry: () => ref.invalidate(fieldSessionProvider(widget.sessionId)),
        builder: (data) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Reveal(
              child: StatRail(
                items: [
                  StatRailItem(
                    label: 'Visits',
                    value: Formatting.integer(data.session.visitsCount),
                  ),
                  StatRailItem(
                    label: 'Interested',
                    value: Formatting.integer(data.session.interestedCount),
                  ),
                  StatRailItem(
                    label: 'Converted',
                    value: Formatting.integer(data.session.convertedCount),
                    emphasis: data.session.convertedCount > 0
                        ? status.settled
                        : null,
                  ),
                ],
              ),
            ),
            if (data.session.summary != null) ...[
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Summary'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Text(
                    data.session.summary!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            const SectionHeader('Businesses visited'),
            const SizedBox(height: Spacing.sm),
            if (data.visits.isEmpty)
              StateMessage(
                icon: Icons.storefront_outlined,
                title: 'Nothing logged yet',
                message: 'Each business you call on in this session is listed here.',
                actionLabel: canLogVisit ? 'Log a visit' : null,
                onAction: canLogVisit ? () => _logVisit(context) : null,
              )
            else
              CrmCardList(
                children: [
                  for (final visit in data.visits)
                    ListTile(
                      title: Text(
                        visit.businessName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: CrmStatusLine(
                          status: visit.status,
                          meta: [
                            if (visit.location != null) visit.location!,
                            if (visit.services.isNotEmpty)
                              visit.services.join(', '),
                          ].join(' · '),
                        ),
                      ),
                      trailing: ContactRow(phone: visit.phone, compact: true),
                    ),
                ],
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
    final services = <String>{};
    var submitting = false;
    String? error;

    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => CrmSheet(
          eyebrow: 'Field marketing',
          title: 'Log a visit',
          children: [
            if (error != null) ...[
              ErrorBanner(message: error!),
              const SizedBox(height: Spacing.md),
            ],
            CrmField(
              label: 'Business name',
              child: TextField(
                controller: name,
                enabled: !submitting,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'The business you called on',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Outcome',
              child: DropdownButtonFormField<String>(
                initialValue: status,
                items: const [
                  DropdownMenuItem(
                    value: 'interested',
                    child: Text('Interested'),
                  ),
                  DropdownMenuItem(
                    value: 'not_interested',
                    child: Text('Not interested'),
                  ),
                  DropdownMenuItem(
                    value: 'follow_up',
                    child: Text('Needs follow-up'),
                  ),
                  DropdownMenuItem(
                    value: 'converted',
                    child: Text('Converted'),
                  ),
                ],
                onChanged: submitting
                    ? null
                    : (v) => setSheetState(() => status = v!),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Location',
              child: TextField(
                controller: location,
                enabled: !submitting,
                decoration: const InputDecoration(
                  hintText: 'Street, building or landmark',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Services discussed',
              child: Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final service in FieldServices.values)
                    FilterChip(
                      label: Text(service.toUpperCase()),
                      selected: services.contains(service),
                      showCheckmark: false,
                      onSelected: submitting
                          ? null
                          : (on) => setSheetState(
                              () => on
                                  ? services.add(service)
                                  : services.remove(service),
                            ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'Phone (optional)',
              child: TextField(
                controller: phone,
                enabled: !submitting,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '0712 345 678'),
              ),
            ),
            const SizedBox(height: Spacing.md),
            CrmField(
              label: 'What did they say?',
              child: TextField(
                controller: feedback,
                enabled: !submitting,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Their words, as close as you can',
                ),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            PrimaryButton(
              label: submitting ? 'Saving…' : 'Save visit',
              busy: submitting,
              onPressed: submitting
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setSheetState(() => error = 'Enter the business name.');
                        return;
                      }
                      if (location.text.trim().isEmpty) {
                        setSheetState(() => error = 'Enter the location.');
                        return;
                      }
                      if (services.isEmpty) {
                        setSheetState(
                          () =>
                              error = 'Pick at least one service discussed.',
                        );
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
                              location: location.text.trim(),
                              services: services.toList(),
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
            ),
          ],
        ),
      ),
    );

    if (saved == true) ref.invalidate(fieldSessionProvider(widget.sessionId));
  }
}
