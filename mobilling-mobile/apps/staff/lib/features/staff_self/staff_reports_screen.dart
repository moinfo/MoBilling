import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers.dart';
import '../common/share_pdf.dart' show sharePdf;
import '../crm/crm_ui.dart'
    show
        CrmAsyncView,
        CrmField,
        CrmPickerField,
        CrmSheet,
        FilterStrip,
        RatingStars,
        showCrmSheet;
import 'attendance_screen.dart' show MonthStepper, PenaltyLedgerView;
import 'staff_self_providers.dart';

// ---------------------------------------------------------------------------
// Local providers — settings, holidays, supervisor assignments and the
// per-employee matrix report. Kept here rather than in
// `staff_self_providers.dart` since only this screen uses them.
// ---------------------------------------------------------------------------

/// GET /staff-reports/settings — needs `staff_reports.submit` to read; any
/// submitter may see the cadence they are held to.
final AutoDisposeFutureProvider<StaffReportSettings>
staffReportSettingsProvider = FutureProvider.autoDispose<StaffReportSettings>(
  (ref) => ref.watch(staffSelfServiceProvider).staffReportSettings(),
);

/// GET /staff-reports/holidays. Needs `staff_reports.submit`.
final AutoDisposeFutureProvider<List<StaffReportHoliday>>
staffReportHolidaysProvider =
    FutureProvider.autoDispose<List<StaffReportHoliday>>(
      (ref) => ref.watch(staffSelfServiceProvider).staffReportHolidays(),
    );

/// GET /staff-reports/supervisors, as [SupervisorAssignment] rows. Needs
/// `staff_reports.review`.
final AutoDisposeFutureProvider<List<SupervisorAssignment>>
supervisorAssignmentsProvider =
    FutureProvider.autoDispose<List<SupervisorAssignment>>(
      (ref) => ref.watch(staffSelfServiceProvider).supervisorAssignments(),
    );

/// The key the matrix report is fetched by: whose month, and which one.
typedef _MatrixKey = ({String userId, int year, int month});

/// GET /staff-reports/report. Needs `staff_reports.review`.
final AutoDisposeFutureProviderFamily<StaffReportMatrix, _MatrixKey>
_staffReportMatrixProvider = FutureProvider.autoDispose
    .family<StaffReportMatrix, _MatrixKey>(
      (ref, key) => ref
          .watch(staffSelfServiceProvider)
          .staffReportMatrix(
            userId: key.userId,
            month: key.month,
            year: key.year,
          ),
    );

/// Periodic staff reports — what you did, what blocked you, what's next, and
/// the supervisor's sign-off on it.
///
/// The API decides whose reports come back: your own, plus subordinates' if
/// you review, plus everyone's if you manage. Nothing here filters by user.
class StaffReportsScreen extends ConsumerWidget {
  const StaffReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).session;
    final canSubmit =
        session?.can(StaffSelfPermissions.staffReportsSubmit) ?? false;
    final canReview =
        session?.can(StaffSelfPermissions.staffReportsReview) ?? false;

    final tabs = <(String, Widget)>[
      ('Reports', _ReportsTab(canSubmit: canSubmit, canReview: canReview)),
      ('Dashboard', const _DashboardTab()),
      if (canReview) ('Deductions', const _DeductionsTab()),
      if (canReview) ('Settings', const _SettingsTab()),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: ShellTopBar(
          eyebrow: 'HR',
          title: 'Staff reports',
          trailing: canSubmit
              ? InkActionButton(
                  icon: Icons.edit_note_outlined,
                  tooltip: 'Submit report',
                  onPressed: () => _submitReport(context, ref),
                )
              : null,
          bottom: InkTabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) label],
          ),
        ),
        body: TabBarView(children: [for (final (_, body) in tabs) body]),
      ),
    );
  }
}

Future<void> _submitReport(BuildContext context, WidgetRef ref) async {
  final saved = await showCrmSheet<bool>(
    context: context,
    builder: (_) => const _SubmitReportSheet(),
  );
  if (saved == true) {
    ref
      ..invalidate(staffReportsProvider)
      ..invalidate(staffReportsDashboardProvider)
      ..invalidate(dashboardProvider);
  }
}

// ---------------------------------------------------------------------------
// Reports — the list, and every action on one
// ---------------------------------------------------------------------------

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab({required this.canSubmit, required this.canReview});

  final bool canSubmit;
  final bool canReview;

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  String? _type;

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('daily', 'Daily'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
  ];

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(staffReportsProvider(_type));
    final myId = ref.watch(currentUserProvider)?.id;

    return Column(
      children: [
        FilterStrip(
          options: _filters,
          selected: _type,
          onSelect: (v) => setState(() => _type = v),
        ),
        Expanded(
          child: CrmAsyncView(
            value: reports,
            errorTitle: 'Could not load reports',
            onRetry: () => ref.invalidate(staffReportsProvider(_type)),
            builder: (items) => items.isEmpty
                ? StateMessage(
                    icon: Icons.assignment_outlined,
                    title: 'No reports yet',
                    message: widget.canSubmit
                        ? 'Your first report starts the record.'
                        : 'Reports shared with you appear here.',
                    actionLabel: widget.canSubmit ? 'Submit a report' : null,
                    onAction: widget.canSubmit
                        ? () => _submitReport(context, ref)
                        : null,
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(staffReportsProvider(_type));
                      await ref.read(staffReportsProvider(_type).future);
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: Spacing.sm),
                      itemBuilder: (context, index) => _ReportCard(
                        report: items[index],
                        canReview: widget.canReview,
                        isMine:
                            items[index].userId != null &&
                            items[index].userId == myId,
                        onChanged: _refresh,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _refresh() => ref
    ..invalidate(staffReportsProvider(_type))
    ..invalidate(staffReportsDashboardProvider)
    ..invalidate(dashboardProvider);
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({
    required this.report,
    required this.canReview,
    required this.isMine,
    required this.onChanged,
  });

  final StaffReport report;

  /// Holds `staff_reports.review` — the permission the review route wants.
  final bool canReview;

  /// The author, so only they see edit and delete (the API enforces it too).
  final bool isMine;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    // The controller refuses both once a report has been reviewed.
    final editable = isMine && !report.isReviewed;

    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(report.periodLabel, style: theme.textTheme.titleSmall),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              StatusChip(report.isReviewed ? 'active' : 'pending', dense: true),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  [
                    if (report.userName != null) report.userName!,
                    report.reportType,
                    if (report.isLate) 'late',
                  ].join(' · ').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: report.isLate
                        ? status.attention
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: report.rating == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 16, color: status.attention),
                  const SizedBox(width: 2),
                  Text('${report.rating}', style: theme.textTheme.labelMedium),
                ],
              ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.achievements != null)
            _Section('Achievements', report.achievements!),
          if (report.challenges != null)
            _Section('Challenges', report.challenges!),
          if (report.plans != null) _Section('Plans', report.plans!),
          if (report.notes != null) _Section('Notes', report.notes!),
          if (report.reviewNotes != null) ...[
            const Divider(height: Spacing.lg),
            _Section(
              'Review by ${report.reviewerName ?? 'supervisor'}',
              report.reviewNotes!,
            ),
          ],
          if (report.replies.isNotEmpty) ...[
            const Divider(height: Spacing.lg),
            Text(
              'DISCUSSION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            for (final reply in report.replies)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reply.userName ?? 'Someone'} · ${Formatting.date(reply.createdAt)}'
                          .toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: reply.isReviewer
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(reply.message, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Spacing.xs),
          // Each button is the exact permission its route asks for; a staff
          // member without `staff_reports.review` never sees the sign-off.
          Wrap(
            spacing: Spacing.sm,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.reply_outlined, size: 16),
                label: const Text('Reply'),
                onPressed: () => _reply(context, ref),
              ),
              if (canReview)
                TextButton.icon(
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: Text(report.isReviewed ? 'Re-review' : 'Review'),
                  onPressed: () => _review(context, ref),
                ),
              if (editable)
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  onPressed: () => _edit(context, ref),
                ),
              if (editable)
                TextButton.icon(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: scheme.error,
                  ),
                  label: Text('Delete', style: TextStyle(color: scheme.error)),
                  onPressed: () => _delete(context, ref),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reply(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reply'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Your message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Send reply'),
          ),
        ],
      ),
    );
    if (message == null || message.isEmpty) return;

    try {
      await ref
          .read(staffSelfServiceProvider)
          .replyToStaffReport(report.id, message);
      onChanged();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final done = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _ReviewSheet(report: report),
    );
    if (done == true) onChanged();
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final done = await showCrmSheet<bool>(
      context: context,
      builder: (_) => _EditReportSheet(report: report),
    );
    if (done == true) onChanged();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          'Your ${report.reportType} report for ${report.periodLabel} will be '
          'withdrawn. A report can only be deleted on the day it covers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(staffSelfServiceProvider).deleteStaffReport(report.id);
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Report deleted.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, this.body);

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review — POST /staff-reports/{id}/review
// ---------------------------------------------------------------------------

/// The supervisor's sign-off: a rating out of five and a note, both optional
/// on the API, and the act of submitting is what marks the report reviewed
/// and notifies its author.
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.report});

  final StaffReport report;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late final TextEditingController _notes;
  late int? _rating;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rating = widget.report.rating;
    _notes = TextEditingController(text: widget.report.reviewNotes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(staffSelfServiceProvider)
          .reviewStaffReport(
            widget.report.id,
            rating: _rating,
            reviewNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reviewed — the author has been notified.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.errorFor('rating') ?? e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;

    return CrmSheet(
      eyebrow: '${report.userName ?? 'Report'} · ${report.periodLabel}',
      title: 'Review this report',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        if (report.achievements != null) ...[
          _Section('Achievements', report.achievements!),
          const SizedBox(height: Spacing.sm),
        ],
        CrmField(
          label: 'Rating',
          child: Row(
            children: [
              RatingStars(
                rating: _rating,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _rating = value),
              ),
              const Spacer(),
              if (_rating != null)
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _rating = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Review notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional — what to keep doing, what to change',
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Saving…' : 'Sign off',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'The author is notified, and the report is locked from further '
          'edits.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit — PUT /staff-reports/{id}
// ---------------------------------------------------------------------------

class _EditReportSheet extends ConsumerStatefulWidget {
  const _EditReportSheet({required this.report});

  final StaffReport report;

  @override
  ConsumerState<_EditReportSheet> createState() => _EditReportSheetState();
}

class _EditReportSheetState extends ConsumerState<_EditReportSheet> {
  late final TextEditingController _achievements;
  late final TextEditingController _challenges;
  late final TextEditingController _plans;
  late final TextEditingController _notes;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _achievements = TextEditingController(
      text: widget.report.achievements ?? '',
    );
    _challenges = TextEditingController(text: widget.report.challenges ?? '');
    _plans = TextEditingController(text: widget.report.plans ?? '');
    _notes = TextEditingController(text: widget.report.notes ?? '');
  }

  @override
  void dispose() {
    _achievements.dispose();
    _challenges.dispose();
    _plans.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // The route replaces all four fields, so all four go up every time.
      await ref
          .read(staffSelfServiceProvider)
          .updateStaffReport(
            widget.report.id,
            achievements: _trimmed(_achievements),
            challenges: _trimmed(_challenges),
            plans: _trimmed(_plans),
            notes: _trimmed(_notes),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report updated.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: '${widget.report.reportType} · ${widget.report.periodLabel}',
    title: 'Edit my report',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmField(
        label: 'What did you achieve?',
        child: TextField(
          controller: _achievements,
          enabled: !_submitting,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What got done this period',
          ),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Challenges',
        child: TextField(
          controller: _challenges,
          enabled: !_submitting,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Optional — what got in the way',
          ),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Plans',
        child: TextField(
          controller: _plans,
          enabled: !_submitting,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Optional — what comes next',
          ),
        ),
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Notes',
        child: TextField(
          controller: _notes,
          enabled: !_submitting,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Optional'),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Saving…' : 'Save changes',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Dashboard — GET /staff-reports/dashboard
// ---------------------------------------------------------------------------

class _DashboardTab extends ConsumerStatefulWidget {
  const _DashboardTab();

  @override
  ConsumerState<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends ConsumerState<_DashboardTab> {
  final _teamSearch = TextEditingController();
  String? _teamFilter;

  static const _teamFilters = <(String?, String)>[
    (null, 'All'),
    ('behind', 'Behind'),
    ('late', 'Late'),
  ];

  @override
  void dispose() {
    _teamSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(staffReportsDashboardProvider);
    final settings = ref.watch(staffReportSettingsProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: dashboard,
      errorTitle: 'Could not load the dashboard',
      onRetry: () => ref.invalidate(staffReportsDashboardProvider),
      builder: (data) => RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(staffReportsDashboardProvider)
            ..invalidate(staffReportSettingsProvider);
          await ref.read(staffReportsDashboardProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            if (data.team != null && data.team!.pendingReview > 0) ...[
              Reveal(
                child: Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.pending_actions_outlined,
                      color: status.attention,
                    ),
                    title: Text(
                      '${Formatting.integer(data.team!.pendingReview)} report'
                      '${data.team!.pendingReview == 1 ? '' : 's'} awaiting '
                      'your review',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      'TEAM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    // Reviewing happens on the list, which is tab one.
                    onTap: () => DefaultTabController.of(context).animateTo(0),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            const SectionHeader('My month'),
            const SizedBox(height: Spacing.sm),
            if (data.thisMonth.isEmpty)
              const Card(
                child: StateMessage(
                  icon: Icons.insights_outlined,
                  title: 'Nothing yet',
                  message: 'Your cadence appears once you submit a report.',
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final (i, type)
                        in StaffReportsDashboard.types.indexed) ...[
                      if (data.thisMonth[type] != null) ...[
                        if (i > 0) const Divider(height: 1),
                        _CadenceTile(
                          type: type,
                          cadence: data.thisMonth[type]!,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            if (data.recentReviews.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Recently reviewed'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Column(
                  children: [
                    for (final (i, report) in data.recentReviews.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(
                          report.periodLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          [
                            report.reportType,
                            if (report.reviewerName != null)
                              'by ${report.reviewerName}',
                            Formatting.date(report.reviewedAt),
                          ].join(' · ').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: report.rating == null
                            ? null
                            : RatingStars(rating: report.rating, compact: true),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (data.team != null && data.team!.staff.isNotEmpty) ...[
              const SizedBox(height: Spacing.lg),
              SectionHeader(
                'Team this month',
                trailing: Text(
                  Formatting.integer(data.team!.staff.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _teamSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search the team by name',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
              FilterStrip(
                options: _teamFilters,
                selected: _teamFilter,
                onSelect: (v) => setState(() => _teamFilter = v),
              ),
              const SizedBox(height: Spacing.sm),
              _TeamSection(
                staff: data.team!.staff,
                search: _teamSearch.text,
                filter: _teamFilter,
              ),
            ],
            if (settings.valueOrNull != null) ...[
              const SizedBox(height: Spacing.lg),
              _DeadlinesCard(settings: settings.value!),
              if (settings.value!.penaltiesEnabled) ...[
                const SizedBox(height: Spacing.lg),
                _RulesCard(settings: settings.value!),
              ],
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// "Team this month", filtered by name and by whether a row is behind its
/// target or carries a late submission — the reviewer's drill-down into one
/// person's detail is the matrix report ([_MatrixReportScreen]).
class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.staff,
    required this.search,
    required this.filter,
  });

  final List<StaffReportTeamRow> staff;
  final String search;

  /// null | 'behind' | 'late'.
  final String? filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final query = search.trim().toLowerCase();

    final rows = staff.where((row) {
      if (query.isNotEmpty && !row.userName.toLowerCase().contains(query)) {
        return false;
      }
      if (filter == 'behind' && row.submitted >= row.target) return false;
      if (filter == 'late' && row.late <= 0) return false;
      return true;
    }).toList();

    if (rows.isEmpty) {
      return const Card(
        child: StateMessage(
          icon: Icons.search_off_outlined,
          title: 'No matches',
          message: 'No one on the team matches that search and filter.',
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text(row.userName, style: theme.textTheme.titleSmall),
              subtitle: Text(
                '${Formatting.integer(row.submitted)} of '
                '${Formatting.integer(row.target)} SUBMITTED'
                '${row.late > 0 ? ' · ${Formatting.integer(row.late)} LATE' : ''}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: row.late > 0
                      ? status.attention
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _MatrixReportScreen(
                    userId: row.userId,
                    userName: row.userName,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// When each cadence is due — read-only, open to anyone who submits reports.
class _DeadlinesCard extends StatelessWidget {
  const _DeadlinesCard({required this.settings});

  final StaffReportSettings settings;

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayNames[settings.weeklyDeadlineDay] ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Submission deadlines'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              _InfoRow(
                label: 'Daily',
                value: settings.dailyDeadlineTime == null
                    ? '—'
                    : 'By ${settings.dailyDeadlineTime}',
              ),
              const Divider(height: 1),
              _InfoRow(
                label: 'Weekly',
                value: settings.weeklyDeadlineTime == null
                    ? '—'
                    : 'By $weekday ${settings.weeklyDeadlineTime}',
              ),
              const Divider(height: 1),
              _InfoRow(
                label: 'Monthly',
                value: settings.monthlyDeadlineTime == null
                    ? '—'
                    : 'By the ${_ordinal(settings.monthlyDeadlineDay)} at '
                          '${settings.monthlyDeadlineTime}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The penalty amounts, when the tenant has them switched on — only the ones
/// actually configured, since a null or zero amount means that fault carries
/// no charge.
class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.settings});

  final StaffReportSettings settings;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double?)>[
      ('Missing daily report', settings.penaltyMissingDaily),
      ('Late submission', settings.penaltyLate),
      ('Missing weekly report', settings.penaltyMissingWeekly),
      ('Missing monthly report', settings.penaltyMissingMonthly),
    ].where((r) => r.$2 != null && r.$2! != 0).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Rules & deductions'),
        const SizedBox(height: Spacing.sm),
        Card(
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  dense: true,
                  title: Text(row.$1),
                  trailing: Money(row.$2, scale: MoneyScale.dense),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A label/value row for the two read-only info cards above.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(label, style: theme.textTheme.titleSmall),
      trailing: Text(value, style: theme.textTheme.bodyMedium),
    );
  }
}

/// One cadence — daily, weekly or monthly — as a bar against its target, with
/// the shortfall the server computed rather than one worked out here.
class _CadenceTile extends StatelessWidget {
  const _CadenceTile({required this.type, required this.cadence});

  final String type;
  final StaffReportCadence cadence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = context.statusColors;
    final behind = cadence.missing > 0;

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type[0].toUpperCase() + type.substring(1),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${Formatting.integer(cadence.submitted)}'
                ' / ${Formatting.integer(cadence.target)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: Type.figures,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: cadence.progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                behind ? status.attention : status.settled,
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            [
              '${Formatting.integer(cadence.reviewed)} reviewed',
              if (cadence.late > 0) '${Formatting.integer(cadence.late)} late',
              if (behind)
                '${Formatting.integer(cadence.missing)} missing so far',
            ].join(' · ').toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: behind ? status.attention : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deductions — late-report charges (staff_reports.review)
// ---------------------------------------------------------------------------

class _DeductionsTab extends ConsumerStatefulWidget {
  const _DeductionsTab();

  @override
  ConsumerState<_DeductionsTab> createState() => _DeductionsTabState();
}

class _DeductionsTabState extends ConsumerState<_DeductionsTab> {
  DateTime _month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final key = monthKeyOf(_month);
    final ledger = ref.watch(staffReportPenaltiesProvider(key));

    return Column(
      children: [
        MonthStepper(
          month: _month,
          onChanged: (m) => setState(() => _month = m),
        ),
        if (ledger.valueOrNull != null && !ledger.value!.isEmpty)
          _ByTypeBreakdown(ledger: ledger.value!),
        Expanded(
          child: PenaltyLedgerView(
            value: ledger,
            emptyMessage: 'No late-report deductions this month.',
            onRetry: () => ref.invalidate(staffReportPenaltiesProvider(key)),
            onRefresh: () async {
              ref.invalidate(staffReportPenaltiesProvider(key));
              await ref.read(staffReportPenaltiesProvider(key).future);
            },
            onWaive: (entry, reason) async {
              final message = await ref
                  .read(staffSelfServiceProvider)
                  .waiveStaffReportPenalty(entry.id, reason: reason);
              ref.invalidate(staffReportPenaltiesProvider(key));
              return message;
            },
            onUnwaive: (entry) async {
              final message = await ref
                  .read(staffSelfServiceProvider)
                  .unwaiveStaffReportPenalty(entry.id);
              ref.invalidate(staffReportPenaltiesProvider(key));
              return message;
            },
          ),
        ),
      ],
    );
  }
}

/// The single grand total [PenaltyLedgerView] shows, split by report type —
/// daily/weekly/monthly each carry their own late-submission and
/// missing-report charges, and a reviewer wants to see which cadence is
/// actually costing money. Unwaived charges only, matching the ledger's own
/// total.
class _ByTypeBreakdown extends StatelessWidget {
  const _ByTypeBreakdown({required this.ledger});

  final PenaltyLedger ledger;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final totals = <String, double>{'daily': 0, 'weekly': 0, 'monthly': 0};
    for (final group in ledger.staff) {
      for (final entry in group.items) {
        if (entry.waived) continue;
        final type = entry.reportType;
        if (type != null && totals.containsKey(type)) {
          totals[type] = totals[type]! + entry.amount;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.sm, Spacing.md, 0),
      child: StatRail(
        items: [
          for (final type in const ['daily', 'weekly', 'monthly'])
            StatRailItem(
              label: type[0].toUpperCase() + type.substring(1),
              value: Formatting.currency(totals[type]),
              emphasis: (totals[type] ?? 0) > 0 ? status.overdue : null,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings — cadence, deadlines, penalties, holidays, supervisors
// (staff_reports.review to write; the cadence form is read by anyone who
// submits, so the read-only info lives on the dashboard instead)
// ---------------------------------------------------------------------------

const _weekdayNames = <int, String>{
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String _hhmm(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

TimeOfDay? _parseHHmm(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  bool _seeded = false;

  final _dailyTarget = TextEditingController();
  final _weeklyTarget = TextEditingController();
  final _monthlyTarget = TextEditingController();
  final _monthlyDeadlineDay = TextEditingController();
  TimeOfDay _dailyDeadline = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _weeklyDeadline = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _monthlyDeadline = const TimeOfDay(hour: 17, minute: 0);
  int _weeklyDeadlineDay = 5;
  bool _penaltiesEnabled = false;
  Set<int> _workingDays = {1, 2, 3, 4, 5};
  final _penaltyMissingDaily = TextEditingController();
  final _penaltyLate = TextEditingController();
  final _penaltyMissingWeekly = TextEditingController();
  final _penaltyMissingMonthly = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _dailyTarget.dispose();
    _weeklyTarget.dispose();
    _monthlyTarget.dispose();
    _monthlyDeadlineDay.dispose();
    _penaltyMissingDaily.dispose();
    _penaltyLate.dispose();
    _penaltyMissingWeekly.dispose();
    _penaltyMissingMonthly.dispose();
    super.dispose();
  }

  void _seed(StaffReportSettings s) {
    if (_seeded) return;
    _seeded = true;
    _dailyTarget.text = s.dailyTarget.toString();
    _weeklyTarget.text = s.weeklyTarget.toString();
    _monthlyTarget.text = s.monthlyTarget.toString();
    _monthlyDeadlineDay.text = s.monthlyDeadlineDay.toString();
    _dailyDeadline = _parseHHmm(s.dailyDeadlineTime) ?? _dailyDeadline;
    _weeklyDeadline = _parseHHmm(s.weeklyDeadlineTime) ?? _weeklyDeadline;
    _monthlyDeadline = _parseHHmm(s.monthlyDeadlineTime) ?? _monthlyDeadline;
    _weeklyDeadlineDay = s.weeklyDeadlineDay;
    _penaltiesEnabled = s.penaltiesEnabled;
    _workingDays = s.workingDays.toSet();
    _penaltyMissingDaily.text = _moneyText(s.penaltyMissingDaily);
    _penaltyLate.text = _moneyText(s.penaltyLate);
    _penaltyMissingWeekly.text = _moneyText(s.penaltyMissingWeekly);
    _penaltyMissingMonthly.text = _moneyText(s.penaltyMissingMonthly);
  }

  static String _moneyText(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(staffReportSettingsProvider);

    return CrmAsyncView(
      value: settings,
      errorTitle: 'Could not load staff-report settings',
      onRetry: () => ref.invalidate(staffReportSettingsProvider),
      builder: (data) {
        _seed(data);
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffReportSettingsProvider);
            await ref.read(staffReportSettingsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              const SectionHeader('Cadence & deadlines'),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: CrmField(
                      label: 'Daily target',
                      child: TextField(
                        controller: _dailyTarget,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: CrmField(
                      label: 'Weekly target',
                      child: TextField(
                        controller: _weeklyTarget,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: CrmField(
                      label: 'Monthly target',
                      child: TextField(
                        controller: _monthlyTarget,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              CrmPickerField(
                label: 'Daily deadline',
                icon: Icons.schedule_outlined,
                value: _hhmm(_dailyDeadline),
                onTap: () => _pickTime(
                  initial: _dailyDeadline,
                  onPicked: (t) => setState(() => _dailyDeadline = t),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CrmField(
                      label: 'Weekly deadline day',
                      child: DropdownButtonFormField<int>(
                        initialValue: _weeklyDeadlineDay,
                        items: [
                          for (final entry in _weekdayNames.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (v) =>
                            setState(() => _weeklyDeadlineDay = v ?? 5),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: CrmPickerField(
                      label: 'Weekly deadline time',
                      icon: Icons.schedule_outlined,
                      value: _hhmm(_weeklyDeadline),
                      onTap: () => _pickTime(
                        initial: _weeklyDeadline,
                        onPicked: (t) => setState(() => _weeklyDeadline = t),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CrmField(
                      label: 'Monthly deadline day',
                      child: TextField(
                        controller: _monthlyDeadlineDay,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: '1–28'),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: CrmPickerField(
                      label: 'Monthly deadline time',
                      icon: Icons.schedule_outlined,
                      value: _hhmm(_monthlyDeadline),
                      onTap: () => _pickTime(
                        initial: _monthlyDeadline,
                        onPicked: (t) => setState(() => _monthlyDeadline = t),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Card(
                child: SwitchListTile(
                  title: const Text('Deduct pay for report faults'),
                  subtitle: const Text(
                    'Missing or late daily/weekly/monthly reports',
                  ),
                  value: _penaltiesEnabled,
                  onChanged: (v) => setState(() => _penaltiesEnabled = v),
                ),
              ),
              if (_penaltiesEnabled) ...[
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Missing daily report',
                  child: TextField(
                    controller: _penaltyMissingDaily,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: 'TZS '),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Late submission',
                  child: TextField(
                    controller: _penaltyLate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: 'TZS '),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Missing weekly report',
                  child: TextField(
                    controller: _penaltyMissingWeekly,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: 'TZS '),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                CrmField(
                  label: 'Missing monthly report',
                  child: TextField(
                    controller: _penaltyMissingMonthly,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: 'TZS '),
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              CrmField(
                label: 'Working days',
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text(_weekdayNames[day]!.substring(0, 3)),
                        selected: _workingDays.contains(day),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _workingDays.add(day);
                          } else {
                            _workingDays.remove(day);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.lg),
              PrimaryButton(
                label: _saving ? 'Saving…' : 'Save cadence',
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
              const SizedBox(height: Spacing.xl),
              const SectionHeader('Holidays'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Holidays'),
                  subtitle: const Text('Days that carry no report requirement'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _HolidaysScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              const SectionHeader('Supervisors'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.supervisor_account_outlined),
                  title: const Text('Supervisor assignments'),
                  subtitle: const Text('Who reviews whose reports'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const _SupervisorsScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xl),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final dailyTarget = int.tryParse(_dailyTarget.text.trim()) ?? 1;
    final weeklyTarget = int.tryParse(_weeklyTarget.text.trim()) ?? 1;
    final monthlyTarget = int.tryParse(_monthlyTarget.text.trim()) ?? 1;
    final monthlyDeadlineDay =
        int.tryParse(_monthlyDeadlineDay.text.trim()) ?? 28;

    setState(() => _saving = true);
    try {
      await ref
          .read(staffSelfServiceProvider)
          .updateStaffReportSettings(
            dailyTarget: dailyTarget,
            weeklyTarget: weeklyTarget,
            monthlyTarget: monthlyTarget,
            dailyDeadlineTime: _hhmm(_dailyDeadline),
            weeklyDeadlineDay: _weeklyDeadlineDay,
            weeklyDeadlineTime: _hhmm(_weeklyDeadline),
            monthlyDeadlineDay: monthlyDeadlineDay,
            monthlyDeadlineTime: _hhmm(_monthlyDeadline),
            penaltiesEnabled: _penaltiesEnabled,
            penaltyMissingDaily: _penaltiesEnabled
                ? double.tryParse(_penaltyMissingDaily.text.trim())
                : null,
            penaltyLate: _penaltiesEnabled
                ? double.tryParse(_penaltyLate.text.trim())
                : null,
            penaltyMissingWeekly: _penaltiesEnabled
                ? double.tryParse(_penaltyMissingWeekly.text.trim())
                : null,
            penaltyMissingMonthly: _penaltiesEnabled
                ? double.tryParse(_penaltyMissingMonthly.text.trim())
                : null,
            workingDays: _workingDays.toList()..sort(),
          );
      ref
        ..invalidate(staffReportSettingsProvider)
        ..invalidate(staffReportsDashboardProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Holidays — GET/POST /staff-reports/holidays, DELETE .../{id}
// ---------------------------------------------------------------------------

class _HolidaysScreen extends ConsumerWidget {
  const _HolidaysScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidays = ref.watch(staffReportHolidaysProvider);

    return Scaffold(
      appBar: ShellTopBar(eyebrow: 'Staff reports', title: 'Holidays'),
      body: CrmAsyncView(
        value: holidays,
        errorTitle: 'Could not load holidays',
        onRetry: () => ref.invalidate(staffReportHolidaysProvider),
        builder: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffReportHolidaysProvider);
            await ref.read(staffReportHolidaysProvider.future);
          },
          child: items.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: const StateMessage(
                        icon: Icons.event_available_outlined,
                        title: 'No holidays set',
                        message:
                            'Add a date that carries no report '
                            'requirement.',
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) => Card(
                    child: ListTile(
                      title: Text(Formatting.date(items[index].date)),
                      subtitle: items[index].name == null
                          ? null
                          : Text(items[index].name!),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _delete(context, ref, items[index]),
                      ),
                    ),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add holiday'),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showCrmSheet<bool>(
      context: context,
      builder: (_) => const _AddHolidaySheet(),
    );
    if (result == true) ref.invalidate(staffReportHolidaysProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StaffReportHoliday holiday,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this holiday?'),
        content: Text(
          '${Formatting.date(holiday.date)} will require reports again, and '
          'any same-day missing-report deductions already reconciled for it '
          'will not be reinstated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(staffSelfServiceProvider)
          .deleteStaffReportHoliday(holiday.id);
      ref.invalidate(staffReportHolidaysProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Holiday removed.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _AddHolidaySheet extends ConsumerStatefulWidget {
  const _AddHolidaySheet();

  @override
  ConsumerState<_AddHolidaySheet> createState() => _AddHolidaySheetState();
}

class _AddHolidaySheetState extends ConsumerState<_AddHolidaySheet> {
  DateTime _date = DateTime.now();
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(staffSelfServiceProvider)
          .setStaffReportHoliday(
            date: _date,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Staff reports',
    title: 'Add a holiday',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
        const SizedBox(height: Spacing.md),
      ],
      CrmPickerField(
        label: 'Date',
        value: Formatting.date(_date),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(DateTime.now().year - 1),
            lastDate: DateTime(DateTime.now().year + 2),
          );
          if (picked != null) setState(() => _date = picked);
        },
      ),
      const SizedBox(height: Spacing.md),
      CrmField(
        label: 'Name',
        child: TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Optional'),
        ),
      ),
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _saving ? 'Saving…' : 'Add holiday',
        busy: _saving,
        onPressed: _saving ? null : _submit,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Supervisors — GET /staff-reports/supervisors, PUT .../supervisors/{userId}
// ---------------------------------------------------------------------------

class _SupervisorsScreen extends ConsumerWidget {
  const _SupervisorsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(supervisorAssignmentsProvider);

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Staff reports',
        title: 'Supervisor assignments',
      ),
      body: CrmAsyncView(
        value: assignments,
        errorTitle: 'Could not load the team',
        onRetry: () => ref.invalidate(supervisorAssignmentsProvider),
        builder: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(supervisorAssignmentsProvider);
            await ref.read(supervisorAssignmentsProvider.future);
          },
          child: items.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: const StateMessage(
                        icon: Icons.groups_outlined,
                        title: 'No active staff',
                        message: 'Nobody to assign a supervisor to yet.',
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: Spacing.sm),
                  itemBuilder: (context, index) {
                    final row = items[index];
                    return Card(
                      child: ListTile(
                        title: Text(row.name),
                        subtitle: Text(
                          row.supervisorName ?? 'None',
                          style: TextStyle(
                            color: row.supervisorName == null
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _assign(context, ref, row, items),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    SupervisorAssignment row,
    List<SupervisorAssignment> all,
  ) async {
    final choice = await showCrmSheet<String>(
      context: context,
      builder: (_) => _SupervisorPickerSheet(
        options: all.where((o) => o.id != row.id).toList(),
      ),
    );
    if (choice == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(staffSelfServiceProvider)
          .setSupervisor(row.id, supervisorId: choice.isEmpty ? null : choice);
      ref.invalidate(supervisorAssignmentsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${row.name}\'s supervisor updated.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Picks a supervisor for one employee from the rest of the team. Returns the
/// chosen id, `''` for "no supervisor", or null when dismissed.
class _SupervisorPickerSheet extends StatefulWidget {
  const _SupervisorPickerSheet({required this.options});

  final List<SupervisorAssignment> options;

  @override
  State<_SupervisorPickerSheet> createState() => _SupervisorPickerSheetState();
}

class _SupervisorPickerSheetState extends State<_SupervisorPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.options
        .where((o) => query.isEmpty || o.name.toLowerCase().contains(query))
        .toList();

    return CrmSheet(
      eyebrow: 'Staff reports',
      title: 'Choose a supervisor',
      children: [
        TextField(
          controller: _search,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Search by name',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: Spacing.md),
        ListTile(
          leading: const Icon(Icons.block),
          title: const Text('No supervisor'),
          onTap: () => Navigator.of(context).pop(''),
        ),
        const Divider(height: 1),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.lg),
            child: StateMessage(
              icon: Icons.search_off_outlined,
              title: 'No matches',
              message: 'Try a different spelling.',
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => ListTile(
                title: Text(matches[index].name),
                onTap: () => Navigator.of(context).pop(matches[index].id),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Matrix report — GET /staff-reports/report, .../report/export
// ---------------------------------------------------------------------------

String _matrixChipStatus(String status) => switch (status) {
  'submitted' => 'active',
  'late' => 'partial',
  'missing' => 'overdue',
  'not_due' || 'pending' => 'pending',
  _ => status,
};

class _MatrixReportScreen extends ConsumerStatefulWidget {
  const _MatrixReportScreen({required this.userId, required this.userName});

  final String userId;
  final String userName;

  @override
  ConsumerState<_MatrixReportScreen> createState() =>
      _MatrixReportScreenState();
}

class _MatrixReportScreenState extends ConsumerState<_MatrixReportScreen> {
  DateTime _month = DateTime.now();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final key = (userId: widget.userId, year: _month.year, month: _month.month);
    final matrix = ref.watch(_staffReportMatrixProvider(key));

    return Scaffold(
      appBar: ShellTopBar(eyebrow: 'Staff reports', title: widget.userName),
      body: Column(
        children: [
          MonthStepper(
            month: _month,
            onChanged: (m) => setState(() => _month = m),
          ),
          Expanded(
            child: CrmAsyncView(
              value: matrix,
              errorTitle: 'Could not load the report',
              onRetry: () => ref.invalidate(_staffReportMatrixProvider(key)),
              builder: (data) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(_staffReportMatrixProvider(key));
                  await ref.read(_staffReportMatrixProvider(key).future);
                },
                child: _MatrixBody(
                  data: data,
                  exporting: _exporting,
                  onExport: _export,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    final monthKey =
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    final filename =
        'staff-report-${widget.userName.replaceAll(' ', '_')}-$monthKey.$format';

    Future<Uint8List> fetch() => ref
        .read(staffSelfServiceProvider)
        .staffReportMatrixExport(
          userId: widget.userId,
          month: _month.month,
          year: _month.year,
          format: format,
        );

    if (format == 'pdf') {
      await sharePdf(context, fetch: fetch, filename: filename);
    } else {
      await _shareCsv(context, fetch: fetch, filename: filename);
    }
    if (mounted) setState(() => _exporting = false);
  }
}

/// Daily, weekly and (singular) monthly sections, plus the totals footer and
/// the two export buttons — the printable matrix, on screen.
class _MatrixBody extends StatelessWidget {
  const _MatrixBody({
    required this.data,
    required this.exporting,
    required this.onExport,
  });

  final StaffReportMatrix data;
  final bool exporting;
  final void Function(String format) onExport;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    final totals = data.totals;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        Reveal(
          child: StatRail(
            items: [
              StatRailItem(
                label: 'Daily',
                value: '${totals.dailyWritten}/${totals.dailyExpected}',
              ),
              StatRailItem(
                label: 'Weekly',
                value: '${totals.weeklyCovered}/${totals.weeklyExpected}',
              ),
              StatRailItem(
                label: 'Late',
                value: Formatting.integer(totals.late),
                emphasis: totals.late > 0 ? status.attention : null,
              ),
              StatRailItem(
                label: 'Docked',
                value: Formatting.currency(totals.deductionTotal),
                emphasis: totals.deductionTotal > 0 ? status.overdue : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Export PDF'),
                onPressed: exporting ? null : () => onExport('pdf'),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Export CSV'),
                onPressed: exporting ? null : () => onExport('csv'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        SectionHeader('Daily · ${data.monthLabel}'),
        const SizedBox(height: Spacing.sm),
        if (data.daily.isEmpty)
          const Card(
            child: StateMessage(
              icon: Icons.event_busy_outlined,
              title: 'Nothing yet',
              message: 'No daily cadence configured for this month.',
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, day) in data.daily.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _MatrixDayTile(day: day),
                ],
              ],
            ),
          ),
        const SizedBox(height: Spacing.lg),
        const SectionHeader('Weekly'),
        const SizedBox(height: Spacing.sm),
        if (data.weekly.isEmpty)
          const Card(
            child: StateMessage(
              icon: Icons.event_busy_outlined,
              title: 'Nothing yet',
              message: 'No weekly cadence configured for this month.',
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, week) in data.weekly.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _MatrixWeekTile(week: week),
                ],
              ],
            ),
          ),
        if (data.monthly != null) ...[
          const SizedBox(height: Spacing.lg),
          const SectionHeader('Monthly'),
          const SizedBox(height: Spacing.sm),
          Card(child: _MatrixMonthTile(month: data.monthly!)),
        ],
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

class _MatrixDayTile extends StatelessWidget {
  const _MatrixDayTile({required this.day});

  final StaffReportMatrixDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(
        '${day.dateKey} · ${day.weekday}',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(_matrixChipStatus(day.status), dense: true),
            if (day.submittedAt != null) ...[
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  Formatting.date(day.submittedAt).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: day.deduction > 0
          ? Money(day.deduction, scale: MoneyScale.dense, color: status.overdue)
          : null,
    );
  }
}

class _MatrixWeekTile extends StatelessWidget {
  const _MatrixWeekTile({required this.week});

  final StaffReportMatrixWeek week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(week.weekLabel, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(_matrixChipStatus(week.status), dense: true),
            if (week.submittedAt != null) ...[
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  Formatting.date(week.submittedAt).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: week.deduction > 0
          ? Money(
              week.deduction,
              scale: MoneyScale.dense,
              color: status.overdue,
            )
          : null,
    );
  }
}

class _MatrixMonthTile extends StatelessWidget {
  const _MatrixMonthTile({required this.month});

  final StaffReportMatrixMonth month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;

    return ListTile(
      dense: true,
      title: Text(month.label, style: theme.textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            StatusChip(_matrixChipStatus(month.status), dense: true),
            if (month.submittedAt != null) ...[
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  Formatting.date(month.submittedAt).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: month.deduction > 0
          ? Money(
              month.deduction,
              scale: MoneyScale.dense,
              color: status.overdue,
            )
          : null,
    );
  }
}

/// Download CSV bytes and hand them to the platform share sheet — the CSV
/// counterpart of `share_pdf.dart`'s [sharePdf], which only ever sets a PDF
/// mime type.
Future<void> _shareCsv(
  BuildContext context, {
  required Future<Uint8List> Function() fetch,
  required String filename,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Preparing CSV…'),
      duration: Duration(seconds: 8),
    ),
  );

  try {
    final bytes = await fetch();
    if (bytes.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('That came back empty. Try again in a moment.'),
        ),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    messenger.hideCurrentSnackBar();
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/csv'),
    ], subject: filename);
  } on ApiException catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ---------------------------------------------------------------------------
// Submit — POST /staff-reports
// ---------------------------------------------------------------------------

class _SubmitReportSheet extends ConsumerStatefulWidget {
  const _SubmitReportSheet();

  @override
  ConsumerState<_SubmitReportSheet> createState() => _SubmitReportSheetState();
}

class _SubmitReportSheetState extends ConsumerState<_SubmitReportSheet> {
  final _achievements = TextEditingController();
  final _challenges = TextEditingController();
  final _plans = TextEditingController();
  final _notes = TextEditingController();

  String _type = 'daily';
  DateTime _period = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _achievements.dispose();
    _challenges.dispose();
    _plans.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_achievements.text.trim().isEmpty) {
      setState(() => _error = 'Describe what you achieved.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(staffSelfServiceProvider)
          .submitStaffReport(
            reportType: _type,
            periodDate: _period,
            achievements: _achievements.text.trim(),
            challenges: _challenges.text.trim().isEmpty
                ? null
                : _challenges.text.trim(),
            plans: _plans.text.trim().isEmpty ? null : _plans.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            e.errorFor('period_date') ??
            e.errorFor('achievements') ??
            e.message,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(staffReportSettingsProvider).valueOrNull;
    final pastDeadline = settings != null && _deadlinePassed(settings, _type);

    return CrmSheet(
      eyebrow: 'Staff report',
      title: 'Submit report',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        if (pastDeadline) ...[
          _DeadlineWarningBanner(
            message: "Past today's $_type deadline — this may be marked late.",
          ),
          const SizedBox(height: Spacing.md),
        ],
        CrmField(
          label: 'Period',
          child: DropdownButtonFormField<String>(
            initialValue: _type,
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('Daily')),
              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
            ],
            onChanged: _submitting ? null : (v) => setState(() => _type = v!),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmPickerField(
          label: 'Period date',
          value: Formatting.date(_period),
          onTap: _submitting
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _period,
                    firstDate: DateTime(DateTime.now().year - 1),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _period = picked);
                },
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'What did you achieve?',
          child: TextField(
            controller: _achievements,
            enabled: !_submitting,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What got done this period',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Challenges',
          child: TextField(
            controller: _challenges,
            enabled: !_submitting,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional — what got in the way',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Plans',
          child: TextField(
            controller: _plans,
            enabled: !_submitting,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Optional — what comes next',
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        CrmField(
          label: 'Notes',
          child: TextField(
            controller: _notes,
            enabled: !_submitting,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _submitting ? 'Submitting…' : 'Submit report',
          busy: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}

/// Whether today's deadline for [type] (daily/weekly/monthly) has already
/// passed, per [settings]. Advisory only — the server is the authority on
/// `is_late`, so this never blocks submission.
bool _deadlinePassed(StaffReportSettings settings, String type) {
  final now = DateTime.now();
  switch (type) {
    case 'daily':
      final deadline = _parseHHmm(settings.dailyDeadlineTime);
      return deadline != null && _afterToday(now, deadline);
    case 'weekly':
      final deadline = _parseHHmm(settings.weeklyDeadlineTime);
      if (deadline == null) return false;
      if (now.weekday > settings.weeklyDeadlineDay) return true;
      if (now.weekday < settings.weeklyDeadlineDay) return false;
      return _afterToday(now, deadline);
    case 'monthly':
      final deadline = _parseHHmm(settings.monthlyDeadlineTime);
      if (deadline == null) return false;
      if (now.day > settings.monthlyDeadlineDay) return true;
      if (now.day < settings.monthlyDeadlineDay) return false;
      return _afterToday(now, deadline);
    default:
      return false;
  }
}

bool _afterToday(DateTime now, TimeOfDay deadline) =>
    now.hour > deadline.hour ||
    (now.hour == deadline.hour && now.minute > deadline.minute);

/// A quiet amber banner for an advisory notice — unlike [ErrorBanner], this
/// never blocks the action below it from proceeding.
class _DeadlineWarningBanner extends StatelessWidget {
  const _DeadlineWarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: status.attention.withValues(alpha: 0.12),
        borderRadius: Radii.card,
        border: Border.all(color: status.attention.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: status.attention, size: 20),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: status.attention)),
          ),
        ],
      ),
    );
  }
}
