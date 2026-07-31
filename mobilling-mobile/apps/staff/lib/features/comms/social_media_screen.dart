import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'comms_providers.dart';
import 'comms_ui.dart';

/// Posts for a status filter; null means every status.
final AutoDisposeFutureProviderFamily<List<SocialPost>, String?>
    socialPostsProvider =
    FutureProvider.autoDispose.family<List<SocialPost>, String?>(
  (ref, status) =>
      ref.watch(commsServiceProvider).socialPosts(status: status),
);

final AutoDisposeFutureProvider<List<SocialPlatformConfig>>
    socialPlatformsProvider =
    FutureProvider.autoDispose<List<SocialPlatformConfig>>(
  (ref) => ref.watch(commsServiceProvider).socialPlatforms(),
);

/// Weekly summary, keyed by the `Y-m-d` of that week's Monday. A string key
/// rather than a DateTime because two DateTimes for the same day are not equal
/// unless every field matches, and a family key must be stable.
final AutoDisposeFutureProviderFamily<SocialWeeklySummary, String>
    socialWeeklySummaryProvider =
    FutureProvider.autoDispose.family<SocialWeeklySummary, String>(
  (ref, weekStart) => ref
      .watch(commsServiceProvider)
      .socialWeeklySummary(weekStart: DateTime.parse(weekStart)),
);

enum _SocialSection { posts, week }

/// The social-media planner: what is scheduled, what has gone out, and how the
/// week is tracking against the tenant's output target.
class SocialMediaScreen extends ConsumerStatefulWidget {
  const SocialMediaScreen({super.key});

  @override
  ConsumerState<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends ConsumerState<SocialMediaScreen> {
  _SocialSection _section = _SocialSection.posts;
  String? _status;

  static const _statusFilters = <(String?, String)>[
    (null, 'All'),
    ('planned', 'Planned'),
    ('designing', 'Designing'),
    ('content_ready', 'Ready'),
    ('partial_posted', 'Partly posted'),
    ('posted', 'Posted'),
  ];

  @override
  Widget build(BuildContext context) {
    final canCreate =
        ref.watch(commsPermissionProvider(CommsPermissions.socialCreate));

    return Scaffold(
      appBar: AppBar(title: const Text('Social media')),
      floatingActionButton:
          (_section == _SocialSection.posts && canCreate)
              ? FloatingActionButton.extended(
                  onPressed: () => _showNewPostSheet(context, _status),
                  icon: const Icon(Icons.add),
                  label: const Text('New post'),
                )
              : null,
      body: Column(
        children: [
          SectionSelector<_SocialSection>(
            sections: const [
              (_SocialSection.posts, 'Posts'),
              (_SocialSection.week, 'This week'),
            ],
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
          ),
          if (_section == _SocialSection.posts)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: Spacing.xs),
                itemCount: _statusFilters.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final (value, label) = _statusFilters[index];
                  return FilterChip(
                    label: Text(label),
                    selected: _status == value,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _status = value),
                  );
                },
              ),
            ),
          Expanded(
            child: switch (_section) {
              _SocialSection.posts => _PostsView(status: _status),
              _SocialSection.week => const _WeekView(),
            },
          ),
        ],
      ),
    );
  }
}

class _PostsView extends ConsumerWidget {
  const _PostsView({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(socialPostsProvider(status));

    return CommsAsyncView<List<SocialPost>>(
      value: posts,
      errorTitle: 'Could not load posts',
      onRetry: () => ref.invalidate(socialPostsProvider(status)),
      builder: (context, rows) => rows.isEmpty
          ? const StateMessage(
              icon: Icons.photo_library_outlined,
              title: 'Nothing scheduled',
              message: 'Posts planned for this filter will appear here.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(socialPostsProvider(status).future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                itemCount: rows.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) =>
                    _PostCard(post: rows[index], statusFilter: status),
              ),
            ),
    );
  }
}

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({required this.post, required this.statusFilter});

  final SocialPost post;
  final String? statusFilter;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  bool _busy = false;

  Future<void> _togglePlatform(SocialPostPlatform row) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(commsServiceProvider).setSocialPostPosted(
            widget.post.id,
            row.platform,
            posted: !row.posted,
          );
      // The post's own status is re-derived server-side, so refetch the list
      // rather than patching the row in place.
      ref.invalidate(socialPostsProvider(widget.statusFilter));
      showCommsMessage(
        messenger,
        row.posted
            ? 'Marked not posted on ${row.platform}.'
            : 'Marked posted on ${row.platform}.',
      );
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final theme = Theme.of(context);
    final status = context.statusColors;
    final canUpdate =
        ref.watch(commsPermissionProvider(CommsPermissions.socialUpdate));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  post.isVideo
                      ? Icons.videocam_outlined
                      : Icons.image_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(post.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Spacing.sm),
                CommsChip(
                  label: SocialLabels.postStatus(post.status),
                  color: postStatusColor(context, post.status),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                SocialLabels.postType(post.type),
                post.postFormats.map(SocialLabels.postFormat).join(', '),
                [
                  Formatting.date(post.scheduledDate),
                  if (post.scheduledTime != null) post.scheduledTime!,
                ].join(' '),
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (post.brief != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(post.brief!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (post.caption != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(post.caption!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
            ],
            if (post.hashtags != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(post.hashtags!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (post.platforms.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  for (final row in post.platforms)
                    _PlatformChip(
                      row: row,
                      // Without social.update the chip is a read-only marker.
                      onToggle: (canUpdate && !_busy)
                          ? () => _togglePlatform(row)
                          : null,
                      onOpen: row.postUrl == null
                          ? null
                          : () => launchUrl(Uri.parse(row.postUrl!),
                              mode: LaunchMode.externalApplication),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                _MiniState(
                  label: 'Design',
                  value: StatusColors.label(post.designStatus),
                  color: post.designStatus == 'done' ? status.settled : null,
                ),
                const SizedBox(width: Spacing.md),
                _MiniState(
                  label: 'Content',
                  value: StatusColors.label(post.contentStatus),
                  color: post.contentStatus == 'ready' ? status.settled : null,
                ),
                const Spacer(),
                Text('${post.postedCount}/${post.platforms.length} posted',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

/// Colour for a post's derived status. `SocialPost::syncStatus` walks
/// planned -> designing -> content_ready -> partial_posted -> posted, so this
/// reads as a progress ramp: nothing yet, in flight, needs finishing, done.
Color postStatusColor(BuildContext context, String status) {
  final colors = context.statusColors;
  return switch (status) {
    'posted' => colors.settled,
    'partial_posted' => colors.attention,
    'content_ready' || 'designing' => colors.pending,
    _ => colors.inactive,
  };
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.row, this.onToggle, this.onOpen});

  final SocialPostPlatform row;
  final VoidCallback? onToggle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final status = context.statusColors;

    return InputChip(
      label: Text(row.platform),
      avatar: Icon(
        row.posted ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: row.posted ? status.settled : status.inactive,
      ),
      onPressed: onToggle,
      onDeleted: onOpen,
      deleteIcon: onOpen == null ? null : const Icon(Icons.link, size: 16),
      tooltip: row.posted && row.postedAt != null
          ? 'Posted ${Formatting.dateTime(row.postedAt)}'
          : null,
    );
  }
}

class _MiniState extends StatelessWidget {
  const _MiniState({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text('$label ',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Weekly summary ─────────────────────────────────────────────────────────

class _WeekView extends ConsumerStatefulWidget {
  const _WeekView();

  @override
  ConsumerState<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends ConsumerState<_WeekView> {
  late DateTime _weekStart = _mondayOf(DateTime.now());

  static DateTime _mondayOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  String get _key =>
      '${_weekStart.year.toString().padLeft(4, '0')}-'
      '${_weekStart.month.toString().padLeft(2, '0')}-'
      '${_weekStart.day.toString().padLeft(2, '0')}';

  void _shift(int weeks) => setState(
      () => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ref.watch(socialWeeklySummaryProvider(_key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous week',
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(
                  'Week of ${Formatting.date(_weekStart)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next week',
                onPressed: () => _shift(1),
              ),
            ],
          ),
        ),
        Expanded(
          child: CommsAsyncView<SocialWeeklySummary>(
            value: summary,
            errorTitle: 'Could not load the weekly summary',
            onRetry: () => ref.invalidate(socialWeeklySummaryProvider(_key)),
            builder: (context, data) => RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(socialWeeklySummaryProvider(_key).future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  const SectionHeading('Target vs actual'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: Column(
                        children: [
                          _TargetBar(
                            label: 'Images',
                            achieved: data.imageAchieved,
                            target: data.target?.imageTarget,
                          ),
                          const SizedBox(height: Spacing.md),
                          _TargetBar(
                            label: 'Videos',
                            achieved: data.videoAchieved,
                            target: data.target?.videoTarget,
                          ),
                          if (data.target == null) ...[
                            const SizedBox(height: Spacing.sm),
                            Text(
                              'No weekly target has been set for this tenant.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (data.daily.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    const SectionHeading('Day by day'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.md),
                        child: Row(
                          children: [
                            for (final day in data.daily)
                              Expanded(child: _DayColumn(day: day)),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Spacing.lg),
                  const SectionHeading('Platforms'),
                  const _PlatformsCard(),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TargetBar extends StatelessWidget {
  const _TargetBar({
    required this.label,
    required this.achieved,
    required this.target,
  });

  final String label;
  final int achieved;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final goal = target ?? 0;
    final ratio = goal == 0 ? null : (achieved / goal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              goal == 0 ? '$achieved' : '$achieved / $goal',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: LinearProgressIndicator(
            value: ratio ?? 0,
            minHeight: 8,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              ratio != null && ratio >= 1 ? status.settled : status.pending,
            ),
          ),
        ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day});

  final SocialDailyBreakdown day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final done = day.images + day.videos;

    return Column(
      children: [
        Text(day.dayName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: day.isActive
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.outline,
            )),
        const SizedBox(height: Spacing.xs),
        Container(
          height: 28,
          width: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !day.isActive
                ? Colors.transparent
                : (done > 0 ? status.settled : status.inactive)
                    .withValues(alpha: 0.16),
            border: day.isActive
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text('$done', style: theme.textTheme.labelMedium),
        ),
        const SizedBox(height: Spacing.xs),
        Text('${day.total}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _PlatformsCard extends ConsumerWidget {
  const _PlatformsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final platforms = ref.watch(socialPlatformsProvider);

    return Card(
      child: platforms.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Spacing.md),
          child: Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(commsErrorText(error), style: theme.textTheme.bodySmall),
        ),
        data: (rows) => rows.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Text('No platforms are configured.'),
              )
            : Column(
                children: [
                  for (final (i, p) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(p.label),
                      subtitle: Text(p.isActive ? p.name : '${p.name} · off'),
                      trailing: p.profileUrl == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.open_in_new, size: 18),
                              tooltip: 'Open profile',
                              onPressed: () => launchUrl(
                                Uri.parse(p.profileUrl!),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ─── New post ───────────────────────────────────────────────────────────────

void _showNewPostSheet(BuildContext context, String? statusFilter) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _NewPostSheet(statusFilter: statusFilter),
  );
}

/// Plans a post. Artwork is not uploaded here — the API attaches designs by
/// URL on a separate endpoint, so the phone plans the post and the designer
/// fills in the file on the web app.
class _NewPostSheet extends ConsumerStatefulWidget {
  const _NewPostSheet({required this.statusFilter});

  final String? statusFilter;

  @override
  ConsumerState<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends ConsumerState<_NewPostSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _brief = TextEditingController();
  final _hashtags = TextEditingController();

  String _type = 'general';
  String _mediaType = 'image';
  final Set<String> _formats = {'feed_post'};
  DateTime _date = DateTime.now();
  TimeOfDay? _time;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _brief.dispose();
    _hashtags.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(commsServiceProvider).createSocialPost(
            title: _title.text.trim(),
            type: _type,
            scheduledDate: _date,
            postFormats: _formats.toList(),
            mediaType: _mediaType,
            scheduledTime: _time == null
                ? null
                : '${_time!.hour.toString().padLeft(2, '0')}:'
                    '${_time!.minute.toString().padLeft(2, '0')}',
            brief: _brief.text.trim(),
            hashtags: _hashtags.text.trim(),
          );
      // Both the filtered list the user is on and the unfiltered one may be
      // showing; the new post is 'planned', so refresh whichever is mounted.
      ref.invalidate(socialPostsProvider(widget.statusFilter));
      ref.invalidate(socialPostsProvider(null));
      showCommsMessage(messenger, 'Post planned.');
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New post', style: theme.textTheme.titleMedium),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _title,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'A title is required.'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in SocialLabels.postTypes.entries)
                    DropdownMenuItem<String>(
                        value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: Spacing.md),
              Text('Format', style: theme.textTheme.labelMedium),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.sm,
                children: [
                  for (final entry in SocialLabels.postFormats.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _formats.contains(entry.key),
                      showCheckmark: false,
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _formats.add(entry.key);
                        } else if (_formats.length > 1) {
                          // The API defaults an empty list back to feed_post;
                          // keeping one selected makes that explicit.
                          _formats.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<String>(value: 'image', label: Text('Image')),
                  ButtonSegment<String>(value: 'video', label: Text('Video')),
                ],
                selected: {_mediaType},
                onSelectionChanged: (values) =>
                    setState(() => _mediaType = values.first),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickDate,
                      child: Text(Formatting.date(_date)),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickTime,
                      child: Text(_time == null
                          ? 'Time…'
                          : '${_time!.hour.toString().padLeft(2, '0')}:'
                              '${_time!.minute.toString().padLeft(2, '0')}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              TextFormField(
                controller: _brief,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Brief',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _hashtags,
                decoration: const InputDecoration(
                  labelText: 'Hashtags',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Plan post'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
