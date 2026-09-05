import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
import '../common/paged_list.dart';
import '../common/pickers.dart';
import '../staff_self/attendance_screen.dart' show MonthStepper;
import 'crm_providers.dart';
import 'crm_ui.dart';
import 'marketing_services_screen.dart';

/// The calls logged against one prospect. Declared here rather than in
/// `crm_providers.dart` because nothing outside this screen reads them.
final AutoDisposeFutureProviderFamily<List<FieldFollowup>, String>
fieldVisitFollowupsProvider = FutureProvider.autoDispose
    .family<List<FieldFollowup>, String>(
      (ref, visitId) =>
          ref.watch(crmServiceProvider).fieldVisitFollowups(visitId),
    );

/// A month's canvassing totals, shown above the targets and on the Stats
/// tab. Keyed by (month, year) so the shared month stepper drives both without
/// either tab holding the fetch.
final AutoDisposeFutureProviderFamily<FieldStats, (int, int)>
fieldStatsProvider = FutureProvider.autoDispose.family<FieldStats, (int, int)>(
  (ref, period) =>
      ref.watch(crmServiceProvider).fieldStats(month: period.$1, year: period.$2),
);

/// Officer targets for one month. Named distinctly from crm_providers.dart's
/// unscoped `fieldTargetsProvider` (which this screen no longer reads) so the
/// two aren't confused — this one always carries the month the stepper is on.
final AutoDisposeFutureProviderFamily<List<FieldTarget>, (int, int)>
fieldTargetsForPeriodProvider = FutureProvider.autoDispose
    .family<List<FieldTarget>, (int, int)>(
      (ref, period) => ref
          .watch(crmServiceProvider)
          .fieldTargets(month: period.$1, year: period.$2),
    );

/// Field marketing: canvassing sessions, the businesses visited, and monthly
/// conversion targets.
///
/// A *session* is one officer's day in one area; *visits* hang off it. Logging
/// a visit therefore needs a session first, which is why the Sessions tab has
/// the create action and visits are logged from a session's detail screen.
///
/// The payoff of the whole module is [_ConvertVisitSheet]: a visit that goes
/// well becomes a billing client without anyone going back to a desk.
class FieldMarketingScreen extends ConsumerStatefulWidget {
  const FieldMarketingScreen({super.key});

  @override
  ConsumerState<FieldMarketingScreen> createState() =>
      _FieldMarketingScreenState();
}

// Order matches web's tab order (FieldMarketing.tsx): Sessions, Targets,
// Stats, All Visits, Services.
enum _Section { sessions, targets, stats, visits, services }

/// Shown in place of a tab's content when the caller lacks its `.read`
/// permission — mirrors web hiding the tab entirely, without this screen's
/// custom `TabController` needing a variable tab count.
class _NoReadAccess extends StatelessWidget {
  const _NoReadAccess();

  @override
  Widget build(BuildContext context) => const StateMessage(
    icon: Icons.lock_outline,
    title: 'Viewing only',
    message: 'Your role cannot view this tab.',
  );
}

class _FieldMarketingScreenState extends ConsumerState<FieldMarketingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)
    ..addListener(_onTab);
  _Section _section = _Section.sessions;

  // Shared across Sessions/Targets/Stats — one stepper rather than three,
  // since all three read the same officer-month data from different angles.
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _onTab() {
    final next = _Section.values[_tabs.index];
    if (next == _Section.services) {
      // `MarketingServicesScreen` owns its own masthead; embedding it inline
      // would stack a second app bar under this screen's tab bar. Pushing it
      // keeps one masthead on screen at a time and snaps the tab back once
      // the officer is done there, so it still reads as "a tab" to tap.
      final previous = _tabs.previousIndex;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const MarketingServicesScreen()))
          .then((_) {
            if (mounted) _tabs.index = previous;
          });
      return;
    }
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
    final canSeeSessions =
        session?.can(CrmPermissions.fieldSessionsRead) ?? false;
    final canSeeTargets =
        session?.can(CrmPermissions.fieldTargetsRead) ?? false;
    final canCreateSession =
        session?.can(CrmPermissions.fieldSessionsCreate) ?? false;
    // Setting a target means choosing an officer, and the officer list is
    // `GET /users` — gated on its own permission.
    final canSetTarget =
        (session?.can(CrmPermissions.fieldTargetsUpdate) ?? false) &&
        (session?.can(CrmPermissions.settingsUsers) ?? false);
    final showMonthStepper =
        _section == _Section.sessions ||
        _section == _Section.targets ||
        _section == _Section.stats;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Field marketing',
        trailing: switch (_section) {
          _Section.sessions when canCreateSession => InkActionButton(
            icon: Icons.add_location_alt_outlined,
            tooltip: 'Start a session',
            onPressed: () => _startSession(context),
          ),
          _Section.targets when canSetTarget => InkActionButton(
            icon: Icons.flag_outlined,
            tooltip: 'Set a target',
            onPressed: () => _setTarget(context, null),
          ),
          _ => null,
        },
        bottom: InkTabBar(
          tabs: const ['Sessions', 'Targets', 'Stats', 'Visits', 'Services'],
          controller: _tabs,
        ),
      ),
      body: Column(
        children: [
          if (showMonthStepper)
            MonthStepper(
              month: _month,
              onChanged: (m) => setState(() => _month = m),
            ),
          Expanded(
            child: switch (_section) {
              _Section.sessions when !canSeeSessions => const _NoReadAccess(),
              _Section.stats when !canSeeSessions => const _NoReadAccess(),
              _Section.visits when !canSeeSessions => const _NoReadAccess(),
              _Section.targets when !canSeeTargets => const _NoReadAccess(),
              _Section.sessions => _SessionsList(month: _month),
              _Section.targets => _TargetsList(month: _month),
              _Section.stats => _StatsList(month: _month),
              _Section.visits => const _VisitsList(),
              _Section.services => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setTarget(BuildContext context, FieldTarget? existing) async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _FieldTargetSheet(existing: existing),
    );
    if (saved == true) ref.invalidate(fieldTargetsForPeriodProvider);
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
  const _SessionsList({required this.month});

  /// The shared stepper's period — day-of-month is never read.
  final DateTime month;

  @override
  ConsumerState<_SessionsList> createState() => _SessionsListState();
}

class _SessionsListState extends ConsumerState<_SessionsList> {
  final _listKey = GlobalKey<PagedListViewState>();
  String? _officerId;
  String? _officerName;

  @override
  void didUpdateWidget(covariant _SessionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // PagedListView only fetches on init; a month change from the shared
    // stepper needs an explicit reload to be seen.
    if (oldWidget.month.year != widget.month.year ||
        oldWidget.month.month != widget.month.month) {
      _listKey.currentState?.reload();
    }
  }

  Future<void> _pickOfficer() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null) return;
    setState(() {
      _officerId = user.id;
      _officerName = user.name;
    });
    _listKey.currentState?.reload();
  }

  void _clearOfficer() {
    setState(() {
      _officerId = null;
      _officerName = null;
    });
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              avatar: const Icon(Icons.person_outline, size: 16),
              label: Text(_officerName ?? 'All officers'),
              onPressed: _pickOfficer,
              onDeleted: _officerId == null ? null : _clearOfficer,
            ),
          ),
        ),
        Expanded(
          child: PagedListView(
            key: _listKey,
            fetch: (page) => ref
                .read(crmServiceProvider)
                .fieldSessions(
                  month: widget.month.month,
                  year: widget.month.year,
                  officerId: _officerId,
                  page: page,
                ),
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
                        if (session.interestedCount > 0)
                          '${Formatting.integer(session.interestedCount)} interested',
                        if (session.convertedCount > 0)
                          '${Formatting.integer(session.convertedCount)} converted',
                      ].join(' · '),
                    ),
                    if (session.officerName != null) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        session.officerName!,
                        style: theme.textTheme.bodySmall,
                      ),
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
          ),
        ),
      ],
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
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _officerId;
  String? _officerName;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('interested', 'Interested'),
    ('not_interested', 'Not interested'),
    ('converted', 'Converted'),
    ('follow_up', 'Follow-up'),
  ];

  bool get _hasExtraFilters =>
      _dateFrom != null || _dateTo != null || _officerId != null;

  /// A sheet rather than more inline controls — date-from/to plus officer
  /// would crowd the status strip that already scrolls horizontally.
  Future<void> _openFilters() async {
    var from = _dateFrom;
    var to = _dateTo;
    var officerId = _officerId;
    var officerName = _officerName;

    final applied = await showCrmSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => CrmSheet(
          eyebrow: 'All visits',
          title: 'Filter visits',
          children: [
            CrmPickerField(
              label: 'From date',
              value: from == null ? 'Any date' : Formatting.date(from),
              placeholder: from == null,
              onTap: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  initialDate: from ?? DateTime.now(),
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setSheetState(() => from = picked);
              },
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'To date',
              value: to == null ? 'Any date' : Formatting.date(to),
              placeholder: to == null,
              onTap: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  initialDate: to ?? DateTime.now(),
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setSheetState(() => to = picked);
              },
            ),
            const SizedBox(height: Spacing.md),
            CrmPickerField(
              label: 'Officer',
              value: officerName ?? 'All officers',
              placeholder: officerName == null,
              onTap: () async {
                final user = await StaffUserPickerSheet.show(sheetContext);
                if (user != null) {
                  setSheetState(() {
                    officerId = user.id;
                    officerName = user.name;
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setSheetState(() {
                      from = null;
                      to = null;
                      officerId = null;
                      officerName = null;
                    }),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: PrimaryButton(
                    label: 'Apply',
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (applied != true) return;
    setState(() {
      _dateFrom = from;
      _dateTo = to;
      _officerId = officerId;
      _officerName = officerName;
    });
    _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilterStrip(
                options: _filters,
                selected: _status,
                onSelect: (v) {
                  setState(() => _status = v);
                  _listKey.currentState?.reload();
                },
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.tune,
                color: _hasExtraFilters
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Filter by date or officer',
              onPressed: _openFilters,
            ),
          ],
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
                .allFieldVisits(
                  status: _status,
                  officerId: _officerId,
                  dateFrom: _dateFrom,
                  dateTo: _dateTo,
                  page: page,
                ),
            itemBuilder: (context, visit) => Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                // The report joins the parent session, so a row here can do
                // everything the session screen can — including convert.
                onTap: visit.sessionId == null
                    ? null
                    : () => showVisitSheet(
                        context,
                        ref,
                        sessionId: visit.sessionId!,
                        visit: visit,
                        eyebrow: visit.area ?? 'Field marketing',
                        onChanged: () => _listKey.currentState?.reload(),
                      ),
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
  const _TargetsList({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = (month.month, month.year);
    final targets = ref.watch(fieldTargetsForPeriodProvider(period));
    final session = ref.watch(sessionControllerProvider).session;
    final canSetTarget =
        (session?.can(CrmPermissions.fieldTargetsUpdate) ?? false) &&
        (session?.can(CrmPermissions.settingsUsers) ?? false);

    return CrmAsyncView(
      value: targets,
      errorTitle: 'Could not load targets',
      onRetry: () => ref.invalidate(fieldTargetsForPeriodProvider(period)),
      builder: (items) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fieldStatsProvider(period));
          ref.invalidate(fieldTargetsForPeriodProvider(period));
          await ref.read(fieldTargetsForPeriodProvider(period).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _FieldStatsRail(month: month),
            if (items.isEmpty)
              const StateMessage(
                icon: Icons.flag_outlined,
                title: 'No targets set',
                message: 'Monthly conversion targets appear here once set.',
              )
            else
              CrmCardList(
                children: [
                  for (final target in items)
                    _TargetRow(
                      target: target,
                      onTap: !canSetTarget
                          ? null
                          : () async {
                              final saved = await showCrmSheet<bool>(
                                context: context,
                                builder: (_) =>
                                    _FieldTargetSheet(existing: target),
                              );
                              if (saved == true) {
                                ref.invalidate(fieldTargetsForPeriodProvider);
                              }
                            },
                    ),
                ],
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// This month's canvassing at a glance — `GET /field-stats`. Sits above the
/// targets because it is what the targets are measured against.
class _FieldStatsRail extends ConsumerWidget {
  const _FieldStatsRail({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref
        .watch(fieldStatsProvider((month.month, month.year)))
        .valueOrNull;
    if (stats == null) return const SizedBox.shrink();

    final status = context.statusColors;
    final interested = stats.byStatus['interested'] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: Reveal(
        child: StatRail(
          items: [
            StatRailItem(
              label: 'Visits',
              value: Formatting.integer(stats.totalVisits),
            ),
            StatRailItem(
              label: 'Interested',
              value: Formatting.integer(interested),
            ),
            StatRailItem(
              label: 'Converted',
              value: Formatting.integer(stats.totalConverted),
              emphasis: stats.totalConverted > 0 ? status.settled : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// `GET /field-stats` in full: totals, the status breakdown, and the
/// by-officer leaderboard — the mobile counterpart to web's Stats tab
/// (FieldMarketing.tsx:294-347). [_FieldStatsRail] above only shows the
/// totals it needs for the Targets tab; this renders everything the endpoint
/// returns.
class _StatsList extends ConsumerWidget {
  const _StatsList({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = (month.month, month.year);
    final statsAsync = ref.watch(fieldStatsProvider(period));
    final theme = Theme.of(context);

    return CrmAsyncView(
      value: statsAsync,
      errorTitle: 'Could not load stats',
      onRetry: () => ref.invalidate(fieldStatsProvider(period)),
      builder: (stats) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fieldStatsProvider(period));
          await ref.read(fieldStatsProvider(period).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            StatRail(
              items: [
                StatRailItem(
                  label: 'Visits',
                  value: Formatting.integer(stats.totalVisits),
                ),
                StatRailItem(
                  label: 'Converted',
                  value: Formatting.integer(stats.totalConverted),
                  emphasis: stats.totalConverted > 0
                      ? context.statusColors.settled
                      : null,
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Text('By status', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final (raw, label) in FieldVisitStatuses.values)
                  _StatusCountCard(
                    label: label,
                    count: stats.byStatus[raw] ?? 0,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
            Text('By officer', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            if (stats.byOfficer.isEmpty)
              const StateMessage(
                icon: Icons.leaderboard_outlined,
                title: 'No visits yet',
                message: 'Officer conversion rates appear here once logged.',
              )
            else
              CrmCardList(
                children: [
                  for (final row in stats.byOfficer)
                    ListTile(
                      title: Text(
                        row.officerName ?? row.officerId ?? '—',
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: CrmMetaLine(
                        '${Formatting.integer(row.visits)} '
                        '${row.visits == 1 ? 'visit' : 'visits'}',
                      ),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${Formatting.integer(row.won)} won',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: context.statusColors.settled,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            row.visits > 0
                                ? '${(row.won / row.visits * 100).round()}%'
                                : '—',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// One status's count in the Stats tab's breakdown — a small card rather
/// than a [StatRail] entry, since a `StatRail` row wouldn't fit four of
/// these next to the totals row above on a phone width.
class _StatusCountCard extends StatelessWidget {
  const _StatusCountCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Formatting.integer(count), style: theme.textTheme.titleLarge),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One officer's month against target: won over target as the figure, the
/// bar for the glance, visits and percentage in the metadata line.
class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, this.onTap});

  final FieldTarget target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final ratio = target.targetClients <= 0
        ? 0.0
        : (target.wonClients / target.targetClients).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      child: Padding(
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
      ),
    );
  }
}

/// `POST /field-targets` upserts on (officer, month, year), so this one sheet
/// both sets a new target and corrects an existing one.
class _FieldTargetSheet extends ConsumerStatefulWidget {
  const _FieldTargetSheet({this.existing});

  final FieldTarget? existing;

  @override
  ConsumerState<_FieldTargetSheet> createState() => _FieldTargetSheetState();
}

class _FieldTargetSheetState extends ConsumerState<_FieldTargetSheet> {
  late final TextEditingController _clients = TextEditingController(
    text: '${widget.existing?.targetClients ?? 5}',
  );

  late String? _officerId = widget.existing?.officerId;
  late String? _officerName = widget.existing?.officerName;
  late DateTime _month = DateTime(
    widget.existing?.year ?? DateTime.now().year,
    widget.existing?.month ?? DateTime.now().month,
  );

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _clients.dispose();
    super.dispose();
  }

  Future<void> _pickOfficer() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null) return;
    setState(() {
      _officerId = user.id;
      _officerName = user.name;
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pick any day in the target month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  Future<void> _submit() async {
    final officerId = _officerId;
    if (officerId == null) {
      setState(() => _error = 'Choose the officer this target is for.');
      return;
    }
    final clients = int.tryParse(_clients.text.trim()) ?? 0;
    if (clients < 1) {
      setState(() => _error = 'The target must be at least one client.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(crmServiceProvider)
          .setFieldTarget(
            officerId: officerId,
            month: _month.month,
            year: _month.year,
            targetClients: clients,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Target set.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Field marketing',
    title: widget.existing == null ? 'Set a target' : 'Edit target',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmPickerField(
        label: 'Officer',
        icon: Icons.person_outline,
        value: _officerName ?? 'Choose a colleague',
        placeholder: _officerName == null,
        onTap: _submitting ? null : _pickOfficer,
      ),
      const SizedBox(height: Spacing.md),
      CrmPickerField(
        label: 'Month',
        value: _monthLabel(_month),
        onTap: _submitting ? null : _pickMonth,
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Clients to win',
        child: TextField(
          controller: _clients,
          enabled: !_submitting,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Prospects to convert this month',
          ),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Saving…' : 'Set target',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

/// A session and the businesses visited in it, with the log-a-visit action.
class FieldSessionScreen extends ConsumerStatefulWidget {
  const FieldSessionScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<FieldSessionScreen> createState() => _FieldSessionScreenState();
}

class _FieldSessionScreenState extends ConsumerState<FieldSessionScreen> {
  void _reload() => ref.invalidate(fieldSessionProvider(widget.sessionId));

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(fieldSessionProvider(widget.sessionId));
    final theme = Theme.of(context);
    final status = context.statusColors;
    final session = ref.watch(sessionControllerProvider).session;
    final canLogVisit = session?.can(CrmPermissions.fieldVisitsCreate) ?? false;
    final canEditSession =
        session?.can(CrmPermissions.fieldSessionsUpdate) ?? false;
    final canDeleteSession =
        session?.can(CrmPermissions.fieldSessionsDelete) ?? false;
    final fieldSession = detail.valueOrNull?.session;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Field marketing',
        title: fieldSession?.area ?? 'Session',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canLogVisit)
              InkActionButton(
                icon: Icons.add_business_outlined,
                tooltip: 'Log a visit',
                onPressed: () => _logVisit(context),
              ),
            if (fieldSession != null && (canEditSession || canDeleteSession))
              Padding(
                padding: EdgeInsets.only(left: canLogVisit ? Spacing.sm : 0),
                child: InkActionButton(
                  icon: Icons.more_horiz,
                  tooltip: 'Session actions',
                  onPressed: () => _sessionActions(
                    context,
                    fieldSession,
                    canEdit: canEditSession,
                    canDelete: canDeleteSession,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: CrmAsyncView(
        value: detail,
        errorTitle: 'Could not load this session',
        onRetry: _reload,
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
                message:
                    'Each business you call on in this session is listed here.',
                actionLabel: canLogVisit ? 'Log a visit' : null,
                onAction: canLogVisit ? () => _logVisit(context) : null,
              )
            else
              CrmCardList(
                children: [
                  for (final visit in data.visits)
                    ListTile(
                      onTap: () => showVisitSheet(
                        context,
                        ref,
                        sessionId: widget.sessionId,
                        visit: visit,
                        eyebrow: data.session.area,
                        onChanged: _reload,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              visit.businessName,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (visit.isConverted) ...[
                            const SizedBox(width: Spacing.xs),
                            Icon(
                              Icons.verified_outlined,
                              size: 16,
                              color: status.settled,
                            ),
                          ],
                        ],
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
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _VisitFormSheet(sessionId: widget.sessionId),
    );
    if (saved == true) _reload();
  }

  Future<void> _sessionActions(
    BuildContext context,
    FieldSession session, {
    required bool canEdit,
    required bool canDelete,
  }) async {
    final scheme = Theme.of(context).colorScheme;

    final action = await showCrmSheet<String>(
      context: context,
      builder: (sheetContext) => CrmSheet(
        eyebrow: 'Field marketing',
        title: session.area,
        children: [
          if (canEdit)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit session'),
              subtitle: const Text(
                'Area, date, and the write-up at the end of the day',
              ),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
          if (canDelete)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete session',
                style: TextStyle(color: scheme.error),
              ),
              subtitle: const Text('The visits logged in it go too'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          const SizedBox(height: Spacing.md),
        ],
      ),
    );

    if (!context.mounted) return;
    if (action == 'edit') {
      final saved = await showCrmSheet<bool>(
        context: context,
        builder: (_) => _SessionFormSheet(session: session),
      );
      if (saved == true) _reload();
    } else if (action == 'delete') {
      final sure = await confirmCrmAction(
        context,
        title: 'Delete the ${session.area} session?',
        message:
            'Every business logged in this session goes with it. This cannot '
            'be undone.',
        verb: 'Delete',
      );
      if (!sure || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        await ref.read(crmServiceProvider).deleteFieldSession(session.id);
        messenger.showSnackBar(
          const SnackBar(content: Text('Session deleted.')),
        );
        if (navigator.canPop()) navigator.pop();
      } on ApiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Edit a session — the same fields the create sheet takes, plus the three
/// write-up boxes `updateSession` accepts and the create form leaves out.
class _SessionFormSheet extends ConsumerStatefulWidget {
  const _SessionFormSheet({required this.session});

  final FieldSession session;

  @override
  ConsumerState<_SessionFormSheet> createState() => _SessionFormSheetState();
}

class _SessionFormSheetState extends ConsumerState<_SessionFormSheet> {
  late final _area = TextEditingController(text: widget.session.area);
  late final _summary = TextEditingController(
    text: widget.session.summary ?? '',
  );
  late final _challenges = TextEditingController(
    text: widget.session.challenges ?? '',
  );
  late final _recommendations = TextEditingController(
    text: widget.session.recommendations ?? '',
  );

  late DateTime _date = widget.session.visitDate ?? DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _area.dispose();
    _summary.dispose();
    _challenges.dispose();
    _recommendations.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_area.text.trim().isEmpty) {
      setState(() => _error = 'Enter the area you canvassed.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(crmServiceProvider)
          .updateFieldSession(
            widget.session.id,
            area: _area.text.trim(),
            visitDate: _date,
            // Nullable server-side, so an emptied box clears the column
            // rather than being ignored.
            summary: _summary.text.trim(),
            challenges: _challenges.text.trim(),
            recommendations: _recommendations.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Session updated.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Field marketing',
    title: 'Edit session',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Area',
        child: TextField(
          controller: _area,
          enabled: !_submitting,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Where you canvassed'),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmPickerField(
        label: 'Date',
        value: Formatting.date(_date),
        onTap: _submitting
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Summary',
        child: TextField(
          controller: _summary,
          enabled: !_submitting,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'How the day went'),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Challenges',
        child: TextField(
          controller: _challenges,
          enabled: !_submitting,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What got in the way'),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Recommendations',
        child: TextField(
          controller: _recommendations,
          enabled: !_submitting,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What to do next time'),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Saving…' : 'Save session',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

/// Everything you can do to one logged visit, opened by tapping its row.
///
/// Convert leads the sheet: a prospect that is not yet a client is one tap
/// from becoming one, which is the reason the field module exists.
Future<void> showVisitSheet(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
  required FieldVisit visit,
  required String eyebrow,
  required VoidCallback onChanged,
}) => showCrmSheet<void>(
  context: context,
  builder: (_) => _VisitSheet(
    sessionId: sessionId,
    visit: visit,
    eyebrow: eyebrow,
    onChanged: onChanged,
  ),
);

class _VisitSheet extends ConsumerStatefulWidget {
  const _VisitSheet({
    required this.sessionId,
    required this.visit,
    required this.eyebrow,
    required this.onChanged,
  });

  final String sessionId;
  final FieldVisit visit;
  final String eyebrow;
  final VoidCallback onChanged;

  @override
  ConsumerState<_VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends ConsumerState<_VisitSheet> {
  /// Holds the converted visit the API hands back, so the sheet can say so
  /// without waiting for the list behind it to refetch.
  FieldVisit? _updated;

  FieldVisit get _visit => _updated ?? widget.visit;

  Future<void> _convert() async {
    final converted = await showCrmSheet<FieldVisit>(
      context: context,
      builder: (_) =>
          _ConvertVisitSheet(sessionId: widget.sessionId, visit: _visit),
    );
    if (converted == null || !mounted) return;
    setState(() => _updated = converted);
    widget.onChanged();
    showCrmMessage(
      context,
      converted.clientName == null
          ? '${_visit.businessName} is now a client.'
          : '${_visit.businessName} is now a client — ${converted.clientName}.',
    );
  }

  Future<void> _edit() async {
    final saved = await showCrmSheet<bool>(
      context: context,
      builder: (_) =>
          _VisitFormSheet(sessionId: widget.sessionId, visit: _visit),
    );
    if (saved == true && mounted) {
      widget.onChanged();
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final sure = await confirmCrmAction(
      context,
      title: 'Delete the ${_visit.businessName} visit?',
      message:
          'The visit and the calls logged against it are removed for good.',
      verb: 'Delete',
    );
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .deleteFieldVisit(widget.sessionId, _visit.id);
      widget.onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Visit deleted.')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logCall() async {
    final logged = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _FieldFollowupSheet(visit: _visit),
    );
    if (logged == true && mounted) {
      ref.invalidate(fieldVisitFollowupsProvider(_visit.id));
      // The outcome may have rewritten the visit's status server-side.
      widget.onChanged();
    }
  }

  Future<void> _deleteFollowup(FieldFollowup followup) async {
    final sure = await confirmCrmAction(
      context,
      title: 'Delete this logged call?',
      message: 'The call comes off the visit’s history.',
      verb: 'Delete',
    );
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(crmServiceProvider)
          .deleteFieldVisitFollowup(_visit.id, followup.id);
      ref.invalidate(fieldVisitFollowupsProvider(_visit.id));
      messenger.showSnackBar(const SnackBar(content: Text('Call removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final visit = _visit;
    final session = ref.watch(sessionControllerProvider).session;
    final canConvert = session?.can(CrmPermissions.fieldVisitsConvert) ?? false;
    final canEdit = session?.can(CrmPermissions.fieldVisitsUpdate) ?? false;
    final canDelete = session?.can(CrmPermissions.fieldVisitsDelete) ?? false;
    final canLog = session?.can(CrmPermissions.followupLog) ?? false;

    return CrmSheet(
      eyebrow: widget.eyebrow,
      title: visit.businessName,
      children: [
        if (visit.isConverted)
          _ConvertedBanner(clientName: visit.clientName)
        else if (canConvert) ...[
          PrimaryButton(
            label: 'Convert to client',
            icon: Icons.how_to_reg_outlined,
            onPressed: _convert,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Creates the client and marks this visit converted — no trip back '
            'to a desk.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        ContactRow(phone: visit.phone),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Visit'),
        const SizedBox(height: Spacing.sm),
        CrmDetailRow('Status', FieldVisitLabels.labelFor(visit.status)),
        if (visit.location != null) CrmDetailRow('Location', visit.location!),
        if (visit.phone != null) CrmDetailRow('Phone', visit.phone!),
        if (visit.services.isNotEmpty)
          CrmDetailRow('Services', visit.services.join(', ')),
        if (visit.feedback != null) CrmDetailRow('They said', visit.feedback!),
        if (visit.nextFollowupDate != null)
          CrmDetailRow('Next call', Formatting.date(visit.nextFollowupDate)),
        if (visit.clientName != null) CrmDetailRow('Client', visit.clientName!),
        const SizedBox(height: Spacing.lg),
        SectionHeader(
          'Calls logged',
          trailing: canLog
              ? TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log a call'),
                  onPressed: _logCall,
                )
              : null,
        ),
        const SizedBox(height: Spacing.sm),
        if (canLog)
          _FollowupList(visitId: visit.id, onDelete: _deleteFollowup)
        else
          Text(
            'You do not have permission to see this visit’s call history.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (canEdit || canDelete) ...[
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              if (canEdit)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                    onPressed: _edit,
                  ),
                ),
              if (canEdit && canDelete) const SizedBox(width: Spacing.sm),
              if (canDelete)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: status.overdue,
                    ),
                    onPressed: _delete,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Says plainly that the prospect is on the books now — the sheet's headline
/// once convert has run.
class _ConvertedBanner extends StatelessWidget {
  const _ConvertedBanner({this.clientName});

  final String? clientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = context.statusColors.settled;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: settled.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: settled.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, size: 20, color: settled),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              clientName == null
                  ? 'Converted — this prospect is a client.'
                  : 'Converted — now a client as $clientName.',
              style: theme.textTheme.bodyMedium?.copyWith(color: settled),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowupList extends ConsumerWidget {
  const _FollowupList({required this.visitId, required this.onDelete});

  final String visitId;
  final ValueChanged<FieldFollowup> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final followups = ref.watch(fieldVisitFollowupsProvider(visitId));

    return CrmAsyncView(
      value: followups,
      errorTitle: 'Could not load calls',
      onRetry: () => ref.invalidate(fieldVisitFollowupsProvider(visitId)),
      builder: (rows) => rows.isEmpty
          ? Text(
              'No calls logged yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : CrmCardList(
              children: [
                for (final followup in rows)
                  ListTile(
                    dense: true,
                    title: Text(
                      FieldFollowupLabels.labelFor(followup.outcome),
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CrmMetaLine(
                          [
                            if (followup.callDate != null)
                              Formatting.date(followup.callDate),
                            if (followup.userName != null) followup.userName!,
                            if (followup.nextFollowupDate != null)
                              'next ${Formatting.date(followup.nextFollowupDate)}',
                          ].join(' · '),
                        ),
                        if (followup.notes != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            followup.notes!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete this call',
                      color: context.statusColors.overdue,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDelete(followup),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Log a call on a prospect. The outcome is not just a note: `interested`,
/// `not_interested` and `converted` rewrite the visit's own status, and a next
/// date moves the visit's follow-up.
class _FieldFollowupSheet extends ConsumerStatefulWidget {
  const _FieldFollowupSheet({required this.visit});

  final FieldVisit visit;

  @override
  ConsumerState<_FieldFollowupSheet> createState() =>
      _FieldFollowupSheetState();
}

class _FieldFollowupSheetState extends ConsumerState<_FieldFollowupSheet> {
  final _notes = TextEditingController();

  String _outcome = 'answered';
  DateTime _callDate = DateTime.now();
  DateTime? _nextDate;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool forNext}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: forNext ? (_nextDate ?? now) : _callDate,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (forNext) {
        _nextDate = picked;
      } else {
        _callDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(crmServiceProvider)
          .logFieldVisitFollowup(
            widget.visit.id,
            callDate: _callDate,
            outcome: _outcome,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            nextFollowupDate: _nextDate,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, 'Call logged.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: widget.visit.businessName,
    title: 'Log a call',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Outcome',
        child: DropdownButtonFormField<String>(
          initialValue: _outcome,
          isExpanded: true,
          items: [
            for (final (value, label) in FieldFollowupOutcomes.values)
              DropdownMenuItem(value: value, child: Text(label)),
          ],
          onChanged: _submitting ? null : (v) => setState(() => _outcome = v!),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmPickerField(
        label: 'Called on',
        value: Formatting.date(_callDate),
        onTap: _submitting ? null : () => _pick(forNext: false),
      ),
      const SizedBox(height: Spacing.md),
      CrmPickerField(
        label: 'Next call (optional)',
        value: _nextDate == null ? 'Choose a date' : Formatting.date(_nextDate),
        placeholder: _nextDate == null,
        onTap: _submitting ? null : () => _pick(forNext: true),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Notes',
        child: TextField(
          controller: _notes,
          enabled: !_submitting,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What was said'),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Saving…' : 'Save call',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

/// Turn a visit into a billing client.
///
/// `convertVisit` takes either an existing `client_id` or a name to create one
/// with, so the sheet is two modes over the same button. Creating prefills from
/// the visit — the business name and the number already on the card — because
/// re-typing them on a phone in the field is exactly the friction this fixes.
class _ConvertVisitSheet extends ConsumerStatefulWidget {
  const _ConvertVisitSheet({required this.sessionId, required this.visit});

  final String sessionId;
  final FieldVisit visit;

  @override
  ConsumerState<_ConvertVisitSheet> createState() => _ConvertVisitSheetState();
}

class _ConvertVisitSheetState extends ConsumerState<_ConvertVisitSheet> {
  late final _name = TextEditingController(text: widget.visit.businessName);
  late final _phone = TextEditingController(text: widget.visit.phone ?? '');
  final _email = TextEditingController();

  bool _linkExisting = false;
  String? _clientId;
  String? _clientName;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickClient() async {
    final client = await ClientPickerSheet.show(context);
    if (client == null) return;
    setState(() {
      _clientId = client.id;
      _clientName = client.name;
    });
  }

  Future<void> _submit() async {
    if (_linkExisting && _clientId == null) {
      setState(() => _error = 'Choose the client to link this visit to.');
      return;
    }
    if (!_linkExisting && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the client’s name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final converted = await ref
          .read(crmServiceProvider)
          .convertFieldVisit(
            widget.sessionId,
            widget.visit.id,
            clientId: _linkExisting ? _clientId : null,
            clientName: _linkExisting ? null : _name.text.trim(),
            clientEmail: _linkExisting || _email.text.trim().isEmpty
                ? null
                : _email.text.trim(),
            clientPhone: _linkExisting || _phone.text.trim().isEmpty
                ? null
                : _phone.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(converted);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('client_name') ?? e.errorFor('client_id') ?? e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CrmSheet(
      eyebrow: widget.visit.businessName,
      title: 'Convert to client',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Text(
          'The visit is marked converted and the client appears in billing '
          'straight away.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              textStyle: theme.textTheme.labelMedium,
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('New client')),
              ButtonSegment(value: true, label: Text('Existing client')),
            ],
            selected: {_linkExisting},
            onSelectionChanged: _submitting
                ? null
                : (values) => setState(() => _linkExisting = values.first),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_linkExisting)
          CrmPickerField(
            label: 'Client',
            icon: Icons.person_search_outlined,
            value: _clientName ?? 'Search for a client',
            placeholder: _clientName == null,
            onTap: _submitting ? null : _pickClient,
          )
        else ...[
          CrmField(
            label: 'Client name',
            child: TextField(
              controller: _name,
              enabled: !_submitting,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'The name to bill under',
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Phone',
            child: TextField(
              controller: _phone,
              enabled: !_submitting,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: '0712 345 678'),
            ),
          ),
          const SizedBox(height: Spacing.md),
          CrmField(
            label: 'Email (optional)',
            child: TextField(
              controller: _email,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'name@business.co.tz',
              ),
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Converting…' : 'Convert to client',
          busy: _submitting,
          icon: Icons.how_to_reg_outlined,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Log a visit, or correct one already logged.
///
/// `updateVisit` validates the same fields as `storeVisit` bar the follow-up
/// date, so the two share a form; only the verbs change.
class _VisitFormSheet extends ConsumerStatefulWidget {
  const _VisitFormSheet({required this.sessionId, this.visit});

  final String sessionId;
  final FieldVisit? visit;

  @override
  ConsumerState<_VisitFormSheet> createState() => _VisitFormSheetState();
}

class _VisitFormSheetState extends ConsumerState<_VisitFormSheet> {
  late final _name = TextEditingController(
    text: widget.visit?.businessName ?? '',
  );
  late final _location = TextEditingController(
    text: widget.visit?.location ?? '',
  );
  late final _phone = TextEditingController(text: widget.visit?.phone ?? '');
  late final _feedback = TextEditingController(
    text: widget.visit?.feedback ?? '',
  );

  late String _status = widget.visit?.status ?? 'interested';
  late final Set<String> _services = {...?widget.visit?.services};
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.visit != null;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _phone.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the business name.');
      return;
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _error = 'Enter the location.');
      return;
    }
    if (_services.isEmpty) {
      setState(() => _error = 'Pick at least one service discussed.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = ref.read(crmServiceProvider);
      final phone = _phone.text.trim();
      final feedback = _feedback.text.trim();
      final visit = widget.visit;
      if (visit == null) {
        await service.logFieldVisit(
          widget.sessionId,
          businessName: _name.text.trim(),
          status: _status,
          location: _location.text.trim(),
          services: _services.toList(),
          phone: phone.isEmpty ? null : phone,
          feedback: feedback.isEmpty ? null : feedback,
        );
      } else {
        await service.updateFieldVisit(
          widget.sessionId,
          visit.id,
          businessName: _name.text.trim(),
          status: _status,
          location: _location.text.trim(),
          services: _services.toList(),
          phone: phone,
          feedback: feedback,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showCrmMessage(context, _isEdit ? 'Visit updated.' : 'Visit saved.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Field marketing',
    title: _isEdit ? 'Edit visit' : 'Log a visit',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'Business name',
        child: TextField(
          controller: _name,
          enabled: !_submitting,
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
          initialValue: _status,
          isExpanded: true,
          items: [
            for (final (value, label) in FieldVisitStatuses.values)
              DropdownMenuItem(value: value, child: Text(label)),
          ],
          onChanged: _submitting ? null : (v) => setState(() => _status = v!),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Location',
        child: TextField(
          controller: _location,
          enabled: !_submitting,
          decoration: const InputDecoration(
            hintText: 'Street, building or landmark',
          ),
        ),
      ),
      const SizedBox(height: Spacing.md),
      _ServicesDiscussedField(
        selected: _services,
        enabled: !_submitting,
        onToggle: (service, on) => setState(
          () => on ? _services.add(service) : _services.remove(service),
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
      CrmField(
        label: 'What did they say?',
        child: TextField(
          controller: _feedback,
          enabled: !_submitting,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Their words, as close as you can',
          ),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting
            ? 'Saving…'
            : (_isEdit ? 'Save changes' : 'Save visit'),
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

/// The "services discussed" picker. Backed by the tenant's live
/// `/marketing-services` list (same source `VisitForm.tsx` and
/// `WhatsappContactForm.tsx` read on the web) rather than a hardcoded set —
/// a tenant that customises or reorders their services via the web used to
/// go unseen here, silently tagging visits against a stale list.
///
/// [marketingServicesProvider] is cached (not `autoDispose`), so after the
/// first successful load this renders instantly with no spinner. Only a
/// first-ever load with no connection falls back to [FieldServices.values]
/// so a field rep on bad signal is never blocked from logging a visit.
class _ServicesDiscussedField extends ConsumerWidget {
  const _ServicesDiscussedField({
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final Set<String> selected;
  final bool enabled;
  final void Function(String service, bool on) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(marketingServicesProvider);
    final names = servicesAsync.when(
      // `.when` only reaches `loading` when nothing has ever loaded — once
      // cached, a background refresh still renders the cached `data`.
      loading: () => FieldServices.values,
      error: (error, _) => FieldServices.values,
      data: (items) => items.isEmpty
          ? FieldServices.values
          : [for (final s in items) s.name],
    );
    final session = ref.watch(sessionControllerProvider).session;
    final canManage =
        session?.can(CrmPermissions.marketingServicesRead) ?? false;

    return CrmField(
      label: 'Services discussed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final service in names)
                FilterChip(
                  label: Text(service.toUpperCase()),
                  selected: selected.contains(service),
                  showCheckmark: false,
                  onSelected: !enabled ? null : (on) => onToggle(service, on),
                ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: Spacing.xs),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MarketingServicesScreen(),
                ),
              ),
              child: Text(
                '+ Manage services',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `August 2026` — the target period, which is a month rather than a date, so
/// [Formatting.date] would print a misleading day.
String _monthLabel(DateTime month) {
  const names = [
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
  return '${names[month.month - 1]} ${month.year}';
}

/// Human labels for the raw enum values the API stores.
abstract final class FieldVisitLabels {
  static String labelFor(String value) {
    for (final (raw, label) in FieldVisitStatuses.values) {
      if (raw == value) return label;
    }
    return value;
  }
}

abstract final class FieldFollowupLabels {
  static String labelFor(String value) {
    for (final (raw, label) in FieldFollowupOutcomes.values) {
      if (raw == value) return label;
    }
    return value;
  }
}

/// A destructive action's confirmation, with the verb on the button rather
/// than "OK".
Future<bool> confirmCrmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String verb,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(verb),
        ),
      ],
    ),
  );
  return sure ?? false;
}
