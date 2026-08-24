import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../../providers.dart';
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
          bottom: InkTabBar(tabs: [for (final (label, _) in tabs) label]),
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

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(staffReportsDashboardProvider);
    final theme = Theme.of(context);
    final status = context.statusColors;

    return CrmAsyncView(
      value: dashboard,
      errorTitle: 'Could not load the dashboard',
      onRetry: () => ref.invalidate(staffReportsDashboardProvider),
      builder: (data) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffReportsDashboardProvider);
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
              const SectionHeader('Team this month'),
              const SizedBox(height: Spacing.sm),
              Card(
                child: Column(
                  children: [
                    for (final (i, row) in data.team!.staff.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(
                          row.userName,
                          style: theme.textTheme.titleSmall,
                        ),
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
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
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

  String _type = 'daily';
  DateTime _period = DateTime.now();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _achievements.dispose();
    _challenges.dispose();
    _plans.dispose();
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
  Widget build(BuildContext context) => CrmSheet(
    eyebrow: 'Staff report',
    title: 'Submit report',
    children: [
      if (_error != null) ...[
        ErrorBanner(message: _error!),
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
      const SizedBox(height: Spacing.lg),
      PrimaryButton(
        label: _submitting ? 'Submitting…' : 'Submit report',
        busy: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
    ],
  );
}
