import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/pickers.dart';
import 'comms_providers.dart';
import 'comms_ui.dart';

/// Posts for a status filter; null means every status.
final AutoDisposeFutureProviderFamily<List<SocialPost>, String?>
socialPostsProvider = FutureProvider.autoDispose
    .family<List<SocialPost>, String?>(
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
socialWeeklySummaryProvider = FutureProvider.autoDispose
    .family<SocialWeeklySummary, String>(
      (ref, weekStart) => ref
          .watch(commsServiceProvider)
          .socialWeeklySummary(weekStart: DateTime.parse(weekStart)),
    );

/// Filter combination for the client design orders queue. A record rather
/// than three separate families because the three filters are queried
/// together server-side and Dart records are structurally equal, which is
/// what a [FutureProviderFamily] key needs.
typedef DesignOrderFilter = ({
  String? status,
  String? designType,
  String? designerId,
});

final AutoDisposeFutureProviderFamily<
  List<ClientDesignOrder>,
  DesignOrderFilter
>
socialDesignOrdersProvider = FutureProvider.autoDispose
    .family<List<ClientDesignOrder>, DesignOrderFilter>(
      (ref, filter) => ref
          .watch(commsServiceProvider)
          .socialDesignOrders(
            status: filter.status,
            designType: filter.designType,
            designerId: filter.designerId,
          ),
    );

enum _SocialSection { posts, workflow, designs, settings, week }

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

  /// The add button in the app bar, one per section that has something to
  /// create — a plan post, a design order, a platform. Others show none.
  Widget? _trailingAction() {
    switch (_section) {
      case _SocialSection.posts:
        final canCreate = ref.watch(
          commsPermissionProvider(CommsPermissions.socialCreate),
        );
        return canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New post',
                onPressed: () => _showNewPostSheet(context, _status),
              )
            : null;
      case _SocialSection.designs:
        final canCreate = ref.watch(
          commsPermissionProvider(CommsPermissions.socialCreate),
        );
        return canCreate
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'New order',
                onPressed: () => showDesignOrderFormSheet(context),
              )
            : null;
      case _SocialSection.settings:
        final canManage = ref.watch(
          commsPermissionProvider(CommsPermissions.socialTargets),
        );
        return canManage
            ? InkActionButton(
                icon: Icons.add_rounded,
                tooltip: 'Add platform',
                onPressed: () => showPlatformFormSheet(context, null),
              )
            : null;
      case _SocialSection.workflow:
      case _SocialSection.week:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Engagement',
        title: 'Social media',
        trailing: _trailingAction(),
      ),
      body: Column(
        children: [
          SectionSelector<_SocialSection>(
            sections: [
              if (ref.watch(commsPermissionProvider(CommsPermissions.socialBoard)))
                (_SocialSection.posts, 'Posts'),
              if (ref.watch(
                commsPermissionProvider(CommsPermissions.socialDesignWork),
              ))
                (_SocialSection.workflow, 'Workflow'),
              if (ref.watch(
                commsPermissionProvider(CommsPermissions.socialClientDesigns),
              ))
                (_SocialSection.designs, 'Designs'),
              if (ref.watch(
                commsPermissionProvider(CommsPermissions.socialSettings),
              ))
                (_SocialSection.settings, 'Settings'),
              // Not one of the web's tabs — a mobile-only week-vs-target view,
              // visible to anyone who can see this screen at all.
              (_SocialSection.week, 'Week'),
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
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                itemCount: _statusFilters.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final (value, label) = _statusFilters[index];
                  return ChoiceChip(
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
              _SocialSection.workflow => const _WorkflowView(),
              _SocialSection.designs => const _DesignOrdersView(),
              _SocialSection.settings => const _SettingsView(),
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
      await ref
          .read(commsServiceProvider)
          .setSocialPostPosted(
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
    final canUpdate = ref.watch(
      commsPermissionProvider(CommsPermissions.socialUpdate),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showPostDetailSheet(
          context,
          post,
          statusFilter: widget.statusFilter,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      post.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      post.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  CommsChip(
                    label: SocialLabels.postStatus(post.status),
                    color: postStatusColor(context, post.status),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              CommsMeta(
                [
                  SocialLabels.postType(post.type),
                  post.postFormats.map(SocialLabels.postFormat).join(', '),
                  [
                    Formatting.date(post.scheduledDate),
                    if (post.scheduledTime != null) post.scheduledTime!,
                  ].join(' '),
                ].join(' · '),
              ),
              if (post.brief != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  post.brief!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (post.caption != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  post.caption!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (post.hashtags != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  post.hashtags!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
                            : () => launchUrl(
                                Uri.parse(row.postUrl!),
                                mode: LaunchMode.externalApplication,
                              ),
                      ),
                  ],
                ),
              ],
              const Divider(height: Spacing.lg),
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
                    color: post.contentStatus == 'ready'
                        ? status.settled
                        : null,
                  ),
                  const Spacer(),
                  Text(
                    '${post.postedCount}/${post.platforms.length} POSTED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
      label: Text(row.platform.toUpperCase()),
      avatar: Icon(
        row.posted ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 16,
        color: row.posted ? status.settled : status.inactive,
      ),
      onPressed: onToggle,
      onDeleted: onOpen,
      deleteIcon: onOpen == null ? null : const Icon(Icons.link, size: 16),
      deleteButtonTooltipMessage: 'Open post',
      tooltip: row.posted && row.postedAt != null
          ? 'Posted ${Formatting.dateTime(row.postedAt)}'
          : null,
    );
  }
}

/// `DESIGN  DONE` — an eyebrow and its state, both in the utility face.
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
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: Spacing.xs + 2),
        Text(
          value.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: color ?? theme.colorScheme.onSurface,
          ),
        ),
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

  void _shift(int weeks) =>
      setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));

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
                child: Column(
                  children: [
                    Text(
                      'WEEK OF',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      Formatting.date(_weekStart),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
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
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
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
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: Type.figures,
              ),
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
        Text(
          day.dayName.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: day.isActive
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Container(
          height: 28,
          width: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: !day.isActive
                ? Colors.transparent
                : (done > 0 ? status.settled : status.inactive).withValues(
                    alpha: 0.16,
                  ),
            border: day.isActive
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text('$done', style: theme.textTheme.labelMedium),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          '${day.total}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
            ? Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Text(
                  'No platforms are configured.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : Column(
                children: [
                  for (final (i, p) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(p.label, style: theme.textTheme.titleSmall),
                      subtitle: CommsMeta(
                        p.isActive ? p.name : '${p.name} · off',
                      ),
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

// ─── Shared sheet helpers ───────────────────────────────────────────────────
//
// Every create/edit sheet below (new post, design orders, platforms) shares
// this scaffold and confirm dialog rather than each rebuilding it, matching
// the one `_NewPostSheet` already established for this screen.

/// The scrolling shell every comms sheet in this screen uses: capped height,
/// the shared header, and room for the keyboard.
class _SocialSheetScaffold extends StatelessWidget {
  const _SocialSheetScaffold({
    required this.title,
    required this.children,
    this.eyebrow,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        Spacing.lg + sheetBottomInset(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CommsSheetHeader(eyebrow: eyebrow, title: title),
          const SizedBox(height: Spacing.lg),
          ...children,
        ],
      ),
    ),
  );
}

/// A compact in-context save action — for the several independent sections
/// of the post detail sheet, where [PrimaryButton]'s full-width gradient CTA
/// would read as one action when there are really four.
class _SectionSaveButton extends StatelessWidget {
  const _SectionSaveButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.tonal(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

/// A destructive confirmation with the verb on the button, matching
/// `servers_screen.dart`'s delete dialog.
Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The 14 Mantine colour names the web app stores on a platform, mapped to a
/// Material [Color] so the same row reads the same on both clients.
const Map<String, Color> _platformColors = {
  'blue': Color(0xFF228BE6),
  'cyan': Color(0xFF15AABF),
  'teal': Color(0xFF12B886),
  'green': Color(0xFF40C057),
  'lime': Color(0xFF82C91E),
  'yellow': Color(0xFFFAB005),
  'orange': Color(0xFFFD7E14),
  'red': Color(0xFFFA5252),
  'pink': Color(0xFFE64980),
  'grape': Color(0xFFBE4BDB),
  'violet': Color(0xFF7950F2),
  'indigo': Color(0xFF4C6EF5),
  'dark': Color(0xFF343A40),
  'gray': Color(0xFF868E96),
};

Color platformColor(String? name) =>
    _platformColors[name] ?? _platformColors['gray']!;

/// Icon slugs the web platform-settings form offers, each paired with a
/// stand-in Material icon — this Flutter app has no brand-mark icon package,
/// so the exact Tabler glyph web stores (`brand-instagram`, …) renders here as
/// a generic pictogram; the [label] on the row still names the platform.
const List<(String value, String label, IconData icon)> platformIconOptions = [
  ('brand-instagram', 'Instagram', Icons.camera_alt_outlined),
  ('brand-facebook', 'Facebook', Icons.facebook_outlined),
  ('brand-threads', 'Threads', Icons.forum_outlined),
  ('brand-x', 'X (Twitter)', Icons.alternate_email),
  ('brand-tiktok', 'TikTok', Icons.music_note_outlined),
  ('brand-linkedin', 'LinkedIn', Icons.business_center_outlined),
  ('brand-youtube', 'YouTube', Icons.smart_display_outlined),
  ('brand-whatsapp', 'WhatsApp', Icons.chat_outlined),
  ('brand-telegram', 'Telegram', Icons.send_outlined),
  ('brand-snapchat', 'Snapchat', Icons.camera_outlined),
  ('brand-pinterest', 'Pinterest', Icons.push_pin_outlined),
  ('brand-twitter', 'Twitter', Icons.alternate_email),
  ('globe', 'Globe / Other', Icons.public),
];

IconData platformIconFor(String? slug) => platformIconOptions
    .firstWhere((o) => o.$1 == slug, orElse: () => platformIconOptions.last)
    .$3;

// ─── New post ───────────────────────────────────────────────────────────────

void _showNewPostSheet(BuildContext context, String? statusFilter) {
  showModalBottomSheet<SocialPost>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (context) => _NewPostSheet(statusFilter: statusFilter),
  );
}

/// Opens the same plan form pre-filled for an existing post, returning the
/// saved post so a caller (the detail sheet) can refresh in place without
/// closing itself too.
Future<SocialPost?> showPostFormSheet(
  BuildContext context, {
  required SocialPost existing,
  String? statusFilter,
}) {
  return showModalBottomSheet<SocialPost>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (context) =>
        _NewPostSheet(statusFilter: statusFilter, existing: existing),
  );
}

/// Plans — or edits the plan of — a post. Artwork is not uploaded here — the
/// API attaches designs by URL on a separate endpoint, so the phone plans the
/// post and the designer fills in the file on the web app.
class _NewPostSheet extends ConsumerStatefulWidget {
  const _NewPostSheet({required this.statusFilter, this.existing});

  final String? statusFilter;
  final SocialPost? existing;

  @override
  ConsumerState<_NewPostSheet> createState() => _NewPostSheetState();
}

class _NewPostSheetState extends ConsumerState<_NewPostSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _brief;
  late final TextEditingController _hashtags;

  late String _type;
  late String _mediaType;
  late Set<String> _formats;
  late DateTime _date;
  TimeOfDay? _time;
  bool _saving = false;
  String? _formError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _brief = TextEditingController(text: existing?.brief ?? '');
    _hashtags = TextEditingController(text: existing?.hashtags ?? '');
    _type = existing?.type ?? 'general';
    _mediaType = existing?.mediaType ?? 'image';
    _formats = existing == null || existing.postFormats.isEmpty
        ? {'feed_post'}
        : existing.postFormats.toSet();
    _date = existing?.scheduledDate ?? DateTime.now();
    _time = _parseTimeOfDay(existing?.scheduledTime);
  }

  static TimeOfDay? _parseTimeOfDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _title.dispose();
    _brief.dispose();
    _hashtags.dispose();
    super.dispose();
  }

  String get _timeLabel => _time == null
      ? 'Time…'
      : '${_time!.hour.toString().padLeft(2, '0')}:'
            '${_time!.minute.toString().padLeft(2, '0')}';

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
    setState(() {
      _saving = true;
      _formError = null;
    });
    final scheduledTime = _time == null
        ? null
        : '${_time!.hour.toString().padLeft(2, '0')}:'
              '${_time!.minute.toString().padLeft(2, '0')}';
    try {
      final service = ref.read(commsServiceProvider);
      final existing = widget.existing;
      final saved = existing == null
          ? await service.createSocialPost(
              title: _title.text.trim(),
              type: _type,
              scheduledDate: _date,
              postFormats: _formats.toList(),
              mediaType: _mediaType,
              scheduledTime: scheduledTime,
              brief: _brief.text.trim(),
              hashtags: _hashtags.text.trim(),
            )
          : await service.updateSocialPost(
              existing.id,
              title: _title.text.trim(),
              type: _type,
              postFormats: _formats.toList(),
              mediaType: _mediaType,
              scheduledDate: _date,
              // Every field on this endpoint is `sometimes`, so a cleared
              // time here simply leaves the stored one untouched rather than
              // clearing it — there is no null-clear on this route.
              scheduledTime: scheduledTime,
              brief: _brief.text.trim(),
              hashtags: _hashtags.text.trim(),
            );
      // Both the filtered list the user is on and the unfiltered one may be
      // showing; refresh whichever is mounted.
      ref.invalidate(socialPostsProvider(widget.statusFilter));
      ref.invalidate(socialPostsProvider(null));
      showCommsMessage(messenger, _isEdit ? 'Post updated.' : 'Post planned.');
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg + sheetBottomInset(context),
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommsSheetHeader(
                eyebrow: 'Social media',
                title: _isEdit ? 'Edit post' : 'New post',
              ),
              const SizedBox(height: Spacing.lg),
              if (_formError != null) ...[
                ErrorBanner(message: _formError!),
                const SizedBox(height: Spacing.md),
              ],
              const CommsFieldLabel('Title'),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _title,
                maxLength: 255,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: 'What the post is about',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a title for the post.'
                    : null,
              ),
              const SizedBox(height: Spacing.md),
              const CommsFieldLabel('Type'),
              const SizedBox(height: Spacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                items: [
                  for (final entry in SocialLabels.postTypes.entries)
                    DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: Spacing.md),
              const CommsFieldLabel('Format'),
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
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
              const CommsFieldLabel('Media'),
              const SizedBox(height: Spacing.sm),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  segments: const [
                    ButtonSegment<String>(value: 'image', label: Text('Image')),
                    ButtonSegment<String>(value: 'video', label: Text('Video')),
                  ],
                  selected: {_mediaType},
                  onSelectionChanged: (values) =>
                      setState(() => _mediaType = values.first),
                ),
              ),
              const SizedBox(height: Spacing.md),
              const CommsFieldLabel('When'),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(
                        Formatting.date(_date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickTime,
                      icon: const Icon(Icons.schedule_outlined, size: 18),
                      label: Text(
                        _timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              const CommsFieldLabel('Brief'),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _brief,
                minLines: 3,
                maxLines: 6,
                enabled: !_saving,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: 'What the designer needs to know',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: Spacing.md),
              const CommsFieldLabel('Hashtags'),
              const SizedBox(height: Spacing.sm),
              TextFormField(
                controller: _hashtags,
                enabled: !_saving,
                decoration: const InputDecoration(hintText: '#tag #another'),
              ),
              const SizedBox(height: Spacing.lg),
              PrimaryButton(
                label: _saving
                    ? 'Saving…'
                    : (_isEdit ? 'Save changes' : 'Plan post'),
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Post detail ────────────────────────────────────────────────────────────

void showPostDetailSheet(
  BuildContext context,
  SocialPost post, {
  String? statusFilter,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (_) => _PostDetailSheet(post: post, statusFilter: statusFilter),
  );
}

/// The post's full detail: the plan (edited through [_NewPostSheet]) plus the
/// design/content/posting sections web keeps as tabs on `PostDetailModal` —
/// here as one scrolling sheet with each section owning its own save action.
class _PostDetailSheet extends ConsumerStatefulWidget {
  const _PostDetailSheet({required this.post, this.statusFilter});

  final SocialPost post;
  final String? statusFilter;

  @override
  ConsumerState<_PostDetailSheet> createState() => _PostDetailSheetState();
}

class _PostDetailSheetState extends ConsumerState<_PostDetailSheet> {
  late SocialPost _post;
  late final TextEditingController _designUrl;
  late final TextEditingController _designNotes;
  late final TextEditingController _caption;
  late final TextEditingController _hashtags;
  late final Map<String, TextEditingController> _platformUrls;

  bool _savingDesign = false;
  bool _savingContent = false;
  final Set<String> _togglingPlatforms = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _designUrl = TextEditingController(text: _post.designFileUrl ?? '');
    _designNotes = TextEditingController(text: _post.designNotes ?? '');
    _caption = TextEditingController(text: _post.caption ?? '');
    _hashtags = TextEditingController(text: _post.hashtags ?? '');
    _platformUrls = {
      for (final row in _post.platforms)
        row.platform: TextEditingController(text: row.postUrl ?? ''),
    };
  }

  @override
  void dispose() {
    _designUrl.dispose();
    _designNotes.dispose();
    _caption.dispose();
    _hashtags.dispose();
    for (final controller in _platformUrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _refreshLists() {
    ref.invalidate(socialPostsProvider(widget.statusFilter));
    ref.invalidate(socialPostsProvider(null));
  }

  Future<void> _editPlan() async {
    final saved = await showPostFormSheet(
      context,
      existing: _post,
      statusFilter: widget.statusFilter,
    );
    if (saved != null && mounted) setState(() => _post = saved);
  }

  Future<void> _saveDesign(String status) async {
    setState(() => _savingDesign = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(commsServiceProvider)
          .updatePostDesign(
            _post.id,
            designStatus: status,
            designNotes: _designNotes.text.trim(),
            designFileUrl: _designUrl.text.trim(),
          );
      if (!mounted) return;
      setState(() => _post = updated);
      _refreshLists();
      showCommsMessage(messenger, 'Design updated.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _savingDesign = false);
    }
  }

  Future<void> _saveContent() async {
    setState(() => _savingContent = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(commsServiceProvider)
          .updatePostContent(
            _post.id,
            contentStatus: 'ready',
            caption: _caption.text.trim(),
            hashtags: _hashtags.text.trim(),
          );
      if (!mounted) return;
      setState(() => _post = updated);
      _refreshLists();
      showCommsMessage(messenger, 'Content updated.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _savingContent = false);
    }
  }

  Future<void> _togglePlatform(SocialPostPlatform row) async {
    setState(() => _togglingPlatforms.add(row.platform));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(commsServiceProvider)
          .setSocialPostPosted(
            _post.id,
            row.platform,
            posted: !row.posted,
            postUrl: _platformUrls[row.platform]?.text.trim(),
          );
      if (!mounted) return;
      setState(() => _post = updated);
      _refreshLists();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => _togglingPlatforms.remove(row.platform));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Delete "${_post.title}"?',
      message: 'This removes the plan and every posting record with it.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commsServiceProvider).deleteSocialPost(_post.id);
      _refreshLists();
      showCommsMessage(messenger, 'Post deleted.');
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = context.statusColors;
    final post = _post;
    final canUpdate = ref.watch(
      commsPermissionProvider(CommsPermissions.socialUpdate),
    );
    final canDelete = ref.watch(
      commsPermissionProvider(CommsPermissions.socialDelete),
    );

    return _SocialSheetScaffold(
      eyebrow: 'Social media',
      title: post.title,
      children: [
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            for (final fmt in post.postFormats)
              CommsChip(
                label: SocialLabels.postFormat(fmt),
                color: theme.colorScheme.primary,
              ),
            CommsChip(
              label: post.isVideo ? 'Video' : 'Image',
              color: post.isVideo
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.primary,
            ),
            CommsChip(
              label: SocialLabels.postStatus(post.status),
              color: postStatusColor(context, post.status),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          children: [
            Expanded(
              child: CommsMeta(
                [
                  Formatting.date(post.scheduledDate),
                  if (post.scheduledTime != null) post.scheduledTime!,
                ].join(' · '),
              ),
            ),
            if (canUpdate)
              TextButton.icon(
                onPressed: _editPlan,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit plan'),
              ),
          ],
        ),
        const Divider(height: Spacing.xl),

        const SectionHeading('Design'),
        Row(
          children: [
            CommsChip(
              label: StatusColors.label(post.designStatus),
              color: post.designStatus == 'done'
                  ? status.settled
                  : post.designStatus == 'in_progress'
                  ? status.pending
                  : status.inactive,
            ),
            const Spacer(),
            if (post.designFileUrl != null)
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(post.designFileUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View file'),
              ),
          ],
        ),
        if (canUpdate) ...[
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _designUrl,
            enabled: !_savingDesign,
            decoration: const InputDecoration(
              hintText: 'Drive / Canva / Figma URL',
              prefixIcon: Icon(Icons.link, size: 18),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _designNotes,
            enabled: !_savingDesign,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Design notes…'),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _SectionSaveButton(
                label: 'In progress',
                busy: _savingDesign,
                onPressed: () => _saveDesign('in_progress'),
              ),
              _SectionSaveButton(
                label: 'Mark done',
                busy: _savingDesign,
                onPressed: () => _saveDesign('done'),
              ),
            ],
          ),
        ] else if (post.designNotes != null) ...[
          const SizedBox(height: Spacing.xs),
          Text(post.designNotes!, style: theme.textTheme.bodySmall),
        ],
        const Divider(height: Spacing.xl),

        const SectionHeading('Content'),
        CommsChip(
          label: post.contentStatus == 'ready' ? 'Ready' : 'Pending',
          color: post.contentStatus == 'ready'
              ? status.settled
              : status.inactive,
        ),
        const SizedBox(height: Spacing.sm),
        if (canUpdate) ...[
          TextField(
            controller: _caption,
            enabled: !_savingContent,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Write caption…'),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _hashtags,
            enabled: !_savingContent,
            decoration: const InputDecoration(hintText: '#tag #another'),
          ),
          const SizedBox(height: Spacing.sm),
          _SectionSaveButton(
            label: 'Mark ready',
            busy: _savingContent,
            onPressed: _saveContent,
          ),
        ] else ...[
          if (post.caption != null)
            Text(post.caption!, style: theme.textTheme.bodyMedium),
          if (post.hashtags != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              post.hashtags!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          if (post.caption == null && post.hashtags == null)
            Text(
              'No content yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
        const Divider(height: Spacing.xl),

        const SectionHeading('Posting'),
        for (final row in post.platforms)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  row.posted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: row.posted ? status.settled : status.inactive,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.platform.toUpperCase(),
                        style: theme.textTheme.labelMedium,
                      ),
                      if (row.posted && row.postedAt != null)
                        CommsMeta(
                          'Posted ${Formatting.dateTime(row.postedAt)}',
                        ),
                    ],
                  ),
                ),
                if (canUpdate) ...[
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _platformUrls[row.platform],
                      enabled: !_togglingPlatforms.contains(row.platform),
                      style: theme.textTheme.bodySmall,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Post URL',
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Switch(
                    value: row.posted,
                    onChanged: _togglingPlatforms.contains(row.platform)
                        ? null
                        : (_) => _togglePlatform(row),
                  ),
                ] else if (row.postUrl != null)
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(row.postUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('View'),
                  ),
              ],
            ),
          ),

        if (canDelete) ...[
          const Divider(height: Spacing.xl),
          OutlinedButton.icon(
            onPressed: _deleting ? null : _delete,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: _deleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline, size: 18),
            label: Text(_deleting ? 'Deleting…' : 'Delete post'),
          ),
        ],
      ],
    );
  }
}

// ─── Workflow tab ───────────────────────────────────────────────────────────

/// A Design → Content → Posting board grouped by [SocialPost.designStatus],
/// mirroring web's Workflow tab — stacked as sections rather than the three
/// side-by-side Kanban columns web draws, which do not fit a phone's width.
/// Each section is gated on the same permission its web column checks.
class _WorkflowView extends ConsumerWidget {
  const _WorkflowView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(socialPostsProvider(null));
    final canDesign = ref.watch(
      commsPermissionProvider(CommsPermissions.socialDesignWork),
    );
    final canContent = ref.watch(
      commsPermissionProvider(CommsPermissions.socialContent),
    );
    final canQa = ref.watch(commsPermissionProvider(CommsPermissions.socialQa));

    return CommsAsyncView<List<SocialPost>>(
      value: posts,
      errorTitle: 'Could not load the workflow board',
      onRetry: () => ref.invalidate(socialPostsProvider(null)),
      builder: (context, rows) {
        if (!canDesign && !canContent && !canQa) {
          return const StateMessage(
            icon: Icons.lock_outline,
            title: 'Not available',
            message: 'None of the workflow columns are open to this account.',
          );
        }

        final theme = Theme.of(context);
        final designing = rows.where((p) => p.designStatus != 'done').toList();
        final content = rows
            .where((p) => p.designStatus == 'done' && p.status != 'posted')
            .toList();
        final posting = [...rows]
          ..sort((a, b) {
            final aDate = a.scheduledDate;
            final bDate = b.scheduledDate;
            if (aDate == null || bDate == null) return 0;
            return aDate.compareTo(bDate);
          });

        return RefreshIndicator(
          onRefresh: () => ref.refresh(socialPostsProvider(null).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (canDesign) ...[
                _WorkflowSection(
                  label: 'Design',
                  color: theme.colorScheme.primary,
                  posts: designing,
                  emptyMessage: 'All designed.',
                ),
                const SizedBox(height: Spacing.lg),
              ],
              if (canContent) ...[
                _WorkflowSection(
                  label: 'Content',
                  color: theme.colorScheme.tertiary,
                  posts: content,
                  emptyMessage: 'All captioned.',
                ),
                const SizedBox(height: Spacing.lg),
              ],
              if (canQa)
                _WorkflowSection(
                  label: 'Posting',
                  color: theme.colorScheme.secondary,
                  posts: posting,
                  emptyMessage: 'No posts this week.',
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkflowSection extends StatelessWidget {
  const _WorkflowSection({
    required this.label,
    required this.color,
    required this.posts,
    required this.emptyMessage,
  });

  final String label;
  final Color color;
  final List<SocialPost> posts;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CommsChip(label: label, color: color, dense: false),
            const SizedBox(width: Spacing.sm),
            Text(
              '${posts.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Text(
              emptyMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final post in posts)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: _WorkflowPostCard(post: post),
            ),
      ],
    );
  }
}

class _WorkflowPostCard extends StatelessWidget {
  const _WorkflowPostCard({required this.post});

  final SocialPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showPostDetailSheet(context, post),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              CommsMeta(
                [
                  post.postFormats.map(SocialLabels.postFormat).join(', '),
                  [
                    Formatting.date(post.scheduledDate),
                    if (post.scheduledTime != null) post.scheduledTime!,
                  ].join(' '),
                ].join(' · '),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '${post.postedCount}/${post.platforms.length} posted',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  CommsChip(
                    label: SocialLabels.postStatus(post.status),
                    color: postStatusColor(context, post.status),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Client design orders tab ───────────────────────────────────────────────
//
// A separate work queue from the post planner above: a client's ask for a
// logo, flyer, banner etc., tracked through to delivery — see
// `ClientDesignOrder`'s own doc comment for why the two never intersect.

/// Colour for a design order's own status enum, distinct from
/// [postStatusColor]'s post-planner one — the two enums don't share values.
Color designOrderStatusColor(BuildContext context, String status) {
  final colors = context.statusColors;
  return switch (status) {
    'done' || 'delivered' => colors.settled,
    'needs_revision' => colors.attention,
    'in_progress' => colors.pending,
    _ => colors.inactive,
  };
}

class _DesignOrdersView extends ConsumerStatefulWidget {
  const _DesignOrdersView();

  @override
  ConsumerState<_DesignOrdersView> createState() => _DesignOrdersViewState();
}

class _DesignOrdersViewState extends ConsumerState<_DesignOrdersView> {
  String? _status;
  String? _designType;
  String? _designerId;
  String? _designerName;

  DesignOrderFilter get _filter =>
      (status: _status, designType: _designType, designerId: _designerId);

  bool get _hasFilters =>
      _status != null || _designType != null || _designerId != null;

  void _clearFilters() => setState(() {
    _status = null;
    _designType = null;
    _designerId = null;
    _designerName = null;
  });

  Future<void> _pickDesigner() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null) return;
    setState(() {
      _designerId = user.id;
      _designerName = user.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = _filter;
    final orders = ref.watch(socialDesignOrdersProvider(filter));
    final canCreate = ref.watch(
      commsPermissionProvider(CommsPermissions.socialCreate),
    );

    return CommsAsyncView<List<ClientDesignOrder>>(
      value: orders,
      errorTitle: 'Could not load design orders',
      onRetry: () => ref.invalidate(socialDesignOrdersProvider(filter)),
      builder: (context, rows) {
        final overdue = rows.where((o) => o.isOverdue).length;

        return RefreshIndicator(
          onRefresh: () =>
              ref.refresh(socialDesignOrdersProvider(filter).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (overdue > 0) ...[
                _OverdueBanner(count: overdue),
                const SizedBox(height: Spacing.md),
              ],
              // Counted from the already-filtered [rows], same as web — pick
              // a status and the other chips read zero, because the query
              // itself narrowed to that one status.
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  for (final entry in DesignOrderLabels.statuses.entries)
                    _StatusFilterChip(
                      label: entry.value,
                      count: rows.where((o) => o.status == entry.key).length,
                      selected: _status == entry.key,
                      color: designOrderStatusColor(context, entry.key),
                      onTap: () => setState(
                        () => _status = _status == entry.key ? null : entry.key,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _designType,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Design type',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All types'),
                  ),
                  for (final entry in DesignOrderLabels.types.entries)
                    DropdownMenuItem<String?>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() => _designType = value),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDesigner,
                      icon: const Icon(Icons.person_search_outlined, size: 16),
                      label: Text(
                        _designerName ?? 'All designers',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(width: Spacing.sm),
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Spacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${rows.length} order${rows.length == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              if (rows.isEmpty)
                SizedBox(
                  height: 240,
                  child: StateMessage(
                    icon: Icons.design_services_outlined,
                    title: 'No design orders',
                    message:
                        'A client\'s ask for a logo, flyer or banner shows '
                        'up here once one is created.',
                    actionLabel: canCreate ? 'New order' : null,
                    onAction: canCreate
                        ? () => showDesignOrderFormSheet(context)
                        : null,
                  ),
                )
              else
                for (final order in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: _DesignOrderCard(order: order),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = context.statusColors.overdue;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: overdue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: overdue.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: overdue),
          const SizedBox(width: Spacing.sm),
          Text(
            '$count order${count == 1 ? '' : 's'} overdue',
            style: theme.textTheme.bodySmall?.copyWith(
              color: overdue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A clickable status pill with its count, doubling as the filter control —
/// tapping the already-selected one clears the filter, matching web's badges.
class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(Radii.sm),
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm + 2,
        vertical: Spacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: selected ? 0.9 : 0.14),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: color.withValues(alpha: selected ? 0.9 : 0.35),
        ),
      ),
      child: Text(
        '${label.toUpperCase()}: $count',
        style: Type.mono(
          11,
          tracking: 0.04,
          color: selected ? Colors.white : color,
        ),
      ),
    ),
  );
}

class _DesignOrderCard extends ConsumerWidget {
  const _DesignOrderCard({required this.order});

  final ClientDesignOrder order;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Delete "${order.title}"?',
      message: 'This removes the order permanently.',
    );
    if (!confirmed || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commsServiceProvider).deleteDesignOrder(order.id);
      ref.invalidate(socialDesignOrdersProvider);
      showCommsMessage(messenger, 'Order deleted.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overdue = context.statusColors.overdue;
    final canUpdate = ref.watch(
      commsPermissionProvider(CommsPermissions.socialUpdate),
    );
    final canDelete = ref.watch(
      commsPermissionProvider(CommsPermissions.socialDelete),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDesignOrderDetailSheet(context, order),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      order.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (order.isOverdue) ...[
                    const SizedBox(width: Spacing.xs),
                    Icon(Icons.warning_amber_rounded, size: 16, color: overdue),
                  ],
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: [
                  CommsChip(
                    label: DesignOrderLabels.type(order.designType),
                    color: theme.colorScheme.primary,
                  ),
                  CommsChip(
                    label: DesignOrderLabels.status(order.status),
                    color: designOrderStatusColor(context, order.status),
                  ),
                  if (order.revisionCount > 0)
                    CommsChip(
                      label:
                          '${order.revisionCount} revision'
                          '${order.revisionCount == 1 ? '' : 's'}',
                      color: context.statusColors.attention,
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              CommsMeta(
                [
                  if (order.clientName != null) 'Client: ${order.clientName}',
                  if (order.designerName != null)
                    'Designer: ${order.designerName}',
                  if (order.dueDate != null)
                    'Due ${Formatting.date(order.dueDate)}',
                ].join(' · '),
                maxLines: 2,
              ),
              if (order.price != null) ...[
                const SizedBox(height: Spacing.xs),
                Money(order.price, scale: MoneyScale.dense),
              ],
              if (order.status == 'needs_revision' &&
                  order.revisionNotes != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  order.revisionNotes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.statusColors.attention,
                  ),
                ),
              ],
              if (canUpdate || canDelete || order.fileUrl != null) ...[
                const SizedBox(height: Spacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (order.fileUrl != null)
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: context.statusColors.settled,
                      ),
                    if (canUpdate)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            showDesignOrderFormSheet(context, existing: order),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        visualDensity: VisualDensity.compact,
                        color: theme.colorScheme.error,
                        onPressed: () => _delete(context, ref),
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

void showDesignOrderDetailSheet(BuildContext context, ClientDesignOrder order) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (_) => _DesignOrderDetailSheet(order: order),
  );
}

class _DesignOrderDetailSheet extends ConsumerStatefulWidget {
  const _DesignOrderDetailSheet({required this.order});

  final ClientDesignOrder order;

  @override
  ConsumerState<_DesignOrderDetailSheet> createState() =>
      _DesignOrderDetailSheetState();
}

class _DesignOrderDetailSheetState
    extends ConsumerState<_DesignOrderDetailSheet> {
  late ClientDesignOrder _order;
  late final TextEditingController _fileUrl;
  late final TextEditingController _revisionNotes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _fileUrl = TextEditingController(text: _order.fileUrl ?? '');
    _revisionNotes = TextEditingController();
  }

  @override
  void dispose() {
    _fileUrl.dispose();
    _revisionNotes.dispose();
    super.dispose();
  }

  /// Setting [status] to `needs_revision` bumps `revision_count` server-side
  /// on its own — nothing extra to send for that beyond the status itself.
  Future<void> _setStatus(String status) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(commsServiceProvider)
          .updateDesignOrder(
            _order.id,
            status: status,
            fileUrl: _fileUrl.text.trim().isEmpty ? null : _fileUrl.text.trim(),
            revisionNotes:
                status == 'needs_revision' &&
                    _revisionNotes.text.trim().isNotEmpty
                ? _revisionNotes.text.trim()
                : null,
          );
      if (!mounted) return;
      setState(() => _order = updated);
      ref.invalidate(socialDesignOrdersProvider);
      showCommsMessage(messenger, 'Order updated.');
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final canUpdate = ref.watch(
      commsPermissionProvider(CommsPermissions.socialUpdate),
    );

    return _SocialSheetScaffold(
      eyebrow: 'Client design order',
      title: order.title,
      children: [
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: [
            CommsChip(
              label: DesignOrderLabels.status(order.status),
              color: designOrderStatusColor(context, order.status),
            ),
            CommsChip(
              label: DesignOrderLabels.type(order.designType),
              color: theme.colorScheme.primary,
            ),
            if (order.isOverdue)
              CommsChip(label: 'Overdue', color: context.statusColors.overdue),
            if (order.revisionCount > 0)
              CommsChip(
                label: '${order.revisionCount} revisions',
                color: context.statusColors.attention,
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        if (order.clientName != null)
          DetailRow(label: 'Client', value: order.clientName!),
        if (order.designerName != null)
          DetailRow(label: 'Designer', value: order.designerName!),
        if (order.dueDate != null)
          DetailRow(label: 'Due', value: Formatting.date(order.dueDate)),
        if (order.price != null)
          DetailRow(label: 'Price', value: Formatting.parts(order.price).plain),
        if (order.description != null) ...[
          const SizedBox(height: Spacing.sm),
          const SectionHeading('Brief'),
          Text(order.description!, style: theme.textTheme.bodyMedium),
        ],
        if (order.revisionNotes != null) ...[
          const SizedBox(height: Spacing.sm),
          const SectionHeading('Revision request'),
          Container(
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              color: context.statusColors.attention.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(order.revisionNotes!, style: theme.textTheme.bodySmall),
          ),
        ],
        if (order.referenceUrl != null) ...[
          const SizedBox(height: Spacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(order.referenceUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('View reference'),
            ),
          ),
        ],
        if (canUpdate) ...[
          const Divider(height: Spacing.xl),
          const SectionHeading('Update status'),
          TextField(
            controller: _fileUrl,
            enabled: !_saving,
            decoration: const InputDecoration(
              hintText: 'Design file URL (Drive, Canva…)',
              prefixIcon: Icon(Icons.link, size: 18),
            ),
          ),
          if (order.status == 'in_progress' ||
              order.status == 'needs_revision') ...[
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _revisionNotes,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Revision notes, if requesting changes…',
              ),
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              if (order.status == 'pending')
                _SectionSaveButton(
                  label: 'Start working',
                  busy: _saving,
                  onPressed: () => _setStatus('in_progress'),
                ),
              if (order.status == 'in_progress' ||
                  order.status == 'needs_revision') ...[
                _SectionSaveButton(
                  label: 'Mark done',
                  busy: _saving,
                  onPressed: () => _setStatus('done'),
                ),
                _SectionSaveButton(
                  label: 'Request revision',
                  busy: _saving,
                  onPressed: () => _setStatus('needs_revision'),
                ),
              ],
              if (order.status == 'done')
                _SectionSaveButton(
                  label: 'Mark delivered',
                  busy: _saving,
                  onPressed: () => _setStatus('delivered'),
                ),
              if (order.status == 'delivered')
                _SectionSaveButton(
                  label: 'Re-open',
                  busy: _saving,
                  onPressed: () => _setStatus('in_progress'),
                ),
            ],
          ),
        ] else if (order.fileUrl != null) ...[
          const SizedBox(height: Spacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(order.fileUrl!),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download design file'),
            ),
          ),
        ],
      ],
    );
  }
}

void showDesignOrderFormSheet(
  BuildContext context, {
  ClientDesignOrder? existing,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (_) => _DesignOrderFormSheet(existing: existing),
  );
}

class _DesignOrderFormSheet extends ConsumerStatefulWidget {
  const _DesignOrderFormSheet({this.existing});

  final ClientDesignOrder? existing;

  @override
  ConsumerState<_DesignOrderFormSheet> createState() =>
      _DesignOrderFormSheetState();
}

class _DesignOrderFormSheetState extends ConsumerState<_DesignOrderFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _referenceUrl;
  late final TextEditingController _price;
  late String _designType;
  String? _clientId;
  String? _clientName;
  String? _designerId;
  String? _designerName;
  DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _referenceUrl = TextEditingController(text: existing?.referenceUrl ?? '');
    _price = TextEditingController(text: _priceText(existing?.price));
    _designType = existing?.designType ?? DesignOrderLabels.types.keys.first;
    _clientId = existing?.clientId;
    _clientName = existing?.clientName;
    _designerId = existing?.designerId;
    _designerName = existing?.designerName;
    _dueDate = existing?.dueDate;
  }

  static String _priceText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _referenceUrl.dispose();
    _price.dispose();
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

  Future<void> _pickDesigner() async {
    final user = await StaffUserPickerSheet.show(context);
    if (user == null) return;
    setState(() {
      _designerId = user.id;
      _designerName = user.name;
    });
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final price = double.tryParse(_price.text.trim());
    try {
      final service = ref.read(commsServiceProvider);
      final existing = widget.existing;
      if (existing == null) {
        await service.createDesignOrder(
          title: title,
          designType: _designType,
          clientId: _clientId,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          referenceUrl: _referenceUrl.text.trim().isEmpty
              ? null
              : _referenceUrl.text.trim(),
          designerId: _designerId,
          dueDate: _dueDate,
          price: price,
        );
      } else {
        await service.updateDesignOrder(
          existing.id,
          title: title,
          designType: _designType,
          clientId: _clientId,
          description: _description.text.trim(),
          referenceUrl: _referenceUrl.text.trim(),
          designerId: _designerId,
          dueDate: _dueDate,
          price: price,
        );
      }
      ref.invalidate(socialDesignOrdersProvider);
      showCommsMessage(
        messenger,
        _isEdit ? 'Order updated.' : 'Order created.',
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.errorFor('title') ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SocialSheetScaffold(
      eyebrow: 'Client designs',
      title: _isEdit ? 'Edit design order' : 'New design order',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        const CommsFieldLabel('Order title'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _title,
          enabled: !_saving,
          decoration: const InputDecoration(hintText: 'Logo for ABC Company'),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Design type'),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _designType,
          isExpanded: true,
          items: [
            for (final entry in DesignOrderLabels.types.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _designType = value);
          },
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Client (optional)'),
        const SizedBox(height: Spacing.sm),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickClient,
          icon: const Icon(Icons.person_search_outlined, size: 18),
          label: Text(
            _clientName ?? 'Search for a client',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Brief / requirements'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _description,
          enabled: !_saving,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'What the client needs, brand colours, style…',
          ),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Reference URL'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _referenceUrl,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://drive.google.com/…',
            prefixIcon: Icon(Icons.link, size: 18),
          ),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Assigned designer (optional)'),
        const SizedBox(height: Spacing.sm),
        OutlinedButton.icon(
          onPressed: _saving ? null : _pickDesigner,
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: Text(
            _designerName ?? 'Choose a designer',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CommsFieldLabel('Due date'),
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDueDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _dueDate == null ? 'Optional' : Formatting.date(_dueDate),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CommsFieldLabel('Price (TZS)'),
                  const SizedBox(height: Spacing.sm),
                  TextField(
                    controller: _price,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(hintText: '0'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _saving
              ? 'Saving…'
              : (_isEdit ? 'Update order' : 'Create order'),
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ─── Settings: platform CRUD ────────────────────────────────────────────────

Future<void> showPlatformFormSheet(
  BuildContext context,
  SocialPlatformConfig? existing,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: commsSheetShape,
    builder: (_) => _PlatformFormSheet(existing: existing),
  );
}

class _SettingsView extends ConsumerWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platforms = ref.watch(socialPlatformsProvider);
    final canManage = ref.watch(
      commsPermissionProvider(CommsPermissions.socialTargets),
    );

    return CommsAsyncView<List<SocialPlatformConfig>>(
      value: platforms,
      errorTitle: 'Could not load platforms',
      onRetry: () => ref.invalidate(socialPlatformsProvider),
      builder: (context, rows) {
        final theme = Theme.of(context);
        final sorted = [...rows]
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        return RefreshIndicator(
          onRefresh: () => ref.refresh(socialPlatformsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              const SectionHeading('Social media platforms'),
              Text(
                'Active platforms are seeded on every new post.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (sorted.isEmpty)
                SizedBox(
                  height: 200,
                  child: StateMessage(
                    icon: Icons.hub_outlined,
                    title: 'No platforms configured',
                    message: canManage
                        ? 'Add the platforms your posts go out on.'
                        : 'Ask an admin to configure the platforms.',
                    actionLabel: canManage ? 'Add platform' : null,
                    onAction: canManage
                        ? () => showPlatformFormSheet(context, null)
                        : null,
                  ),
                )
              else
                for (final platform in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: _PlatformRow(
                      platform: platform,
                      canManage: canManage,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({required this.platform, required this.canManage});

  final SocialPlatformConfig platform;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = platformColor(platform.color);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: platform.isActive ? 1 : 0.6,
        child: ListTile(
          onTap: canManage
              ? () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  shape: commsSheetShape,
                  builder: (_) => _PlatformActionsSheet(platform: platform),
                )
              : null,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.16),
            foregroundColor: color,
            child: Icon(platformIconFor(platform.icon), size: 18),
          ),
          title: Text(platform.label, style: theme.textTheme.titleSmall),
          subtitle: Text(
            platform.isActive ? platform.name : '${platform.name} · inactive',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: platform.profileUrl == null
              ? (canManage ? const Icon(Icons.chevron_right) : null)
              : IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  tooltip: 'Open profile',
                  onPressed: () => launchUrl(
                    Uri.parse(platform.profileUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PlatformActionsSheet extends ConsumerStatefulWidget {
  const _PlatformActionsSheet({required this.platform});

  final SocialPlatformConfig platform;

  @override
  ConsumerState<_PlatformActionsSheet> createState() =>
      _PlatformActionsSheetState();
}

class _PlatformActionsSheetState extends ConsumerState<_PlatformActionsSheet> {
  bool _busy = false;

  SocialPlatformConfig get platform => widget.platform;

  Future<void> _toggleActive() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(commsServiceProvider)
          .updateSocialPlatform(platform.id, isActive: !platform.isActive);
      ref.invalidate(socialPlatformsProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    await showPlatformFormSheet(context, platform);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDelete(
      context,
      title: 'Delete ${platform.label}?',
      message:
          'Existing posts keep their history for this platform; new posts '
          'stop seeding a row for it.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commsServiceProvider).deleteSocialPlatform(platform.id);
      ref.invalidate(socialPlatformsProvider);
      showCommsMessage(messenger, 'Platform removed.');
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      showCommsMessage(messenger, e.message, isError: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PLATFORM',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    platform.label,
                    style: Type.display(22, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
            const Divider(height: Spacing.lg),
            ListTile(
              leading: Icon(
                platform.isActive
                    ? Icons.toggle_off_outlined
                    : Icons.toggle_on_outlined,
              ),
              title: Text(platform.isActive ? 'Deactivate' : 'Activate'),
              enabled: !_busy,
              onTap: _toggleActive,
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit platform'),
              enabled: !_busy,
              onTap: _edit,
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(
                'Delete platform',
                style: TextStyle(color: scheme.error),
              ),
              enabled: !_busy,
              onTap: _delete,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformFormSheet extends ConsumerStatefulWidget {
  const _PlatformFormSheet({this.existing});

  final SocialPlatformConfig? existing;

  @override
  ConsumerState<_PlatformFormSheet> createState() => _PlatformFormSheetState();
}

class _PlatformFormSheetState extends ConsumerState<_PlatformFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _label;
  late final TextEditingController _profileUrl;
  late final TextEditingController _sortOrder;
  late String _icon;
  late String _color;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _label = TextEditingController(text: existing?.label ?? '');
    _profileUrl = TextEditingController(text: existing?.profileUrl ?? '');
    _sortOrder = TextEditingController(text: '${existing?.sortOrder ?? 0}');
    _icon = existing?.icon ?? platformIconOptions.first.$1;
    _color = existing?.color ?? 'blue';
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _profileUrl.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final label = _label.text.trim();
    if (!_isEdit && name.isEmpty) {
      setState(() => _error = 'A name (slug) is required.');
      return;
    }
    if (label.isEmpty) {
      setState(() => _error = 'A label is required.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final sortOrder = int.tryParse(_sortOrder.text.trim()) ?? 0;
    try {
      final service = ref.read(commsServiceProvider);
      final existing = widget.existing;
      if (existing == null) {
        await service.createSocialPlatform(
          name: name,
          label: label,
          color: _color,
          icon: _icon,
          profileUrl: _profileUrl.text.trim().isEmpty
              ? null
              : _profileUrl.text.trim(),
          isActive: _isActive,
          sortOrder: sortOrder,
        );
      } else {
        await service.updateSocialPlatform(
          existing.id,
          label: label,
          color: _color,
          icon: _icon,
          profileUrl: _profileUrl.text.trim(),
          isActive: _isActive,
          sortOrder: sortOrder,
        );
      }
      ref.invalidate(socialPlatformsProvider);
      showCommsMessage(
        messenger,
        _isEdit ? 'Platform updated.' : 'Platform added.',
      );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.errorFor('name') ?? e.errorFor('label') ?? e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SocialSheetScaffold(
      eyebrow: 'Platforms',
      title: _isEdit ? 'Edit ${widget.existing!.label}' : 'Add platform',
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: Spacing.md),
        ],
        Center(
          child: CircleAvatar(
            radius: 30,
            backgroundColor: platformColor(_color).withValues(alpha: 0.16),
            foregroundColor: platformColor(_color),
            child: Icon(platformIconFor(_icon), size: 28),
          ),
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Icon'),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _icon,
          isExpanded: true,
          items: [
            for (final option in platformIconOptions)
              DropdownMenuItem(
                value: option.$1,
                child: Row(
                  children: [
                    Icon(option.$3, size: 16),
                    const SizedBox(width: Spacing.sm),
                    Text(option.$2),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _icon = value);
          },
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Label'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _label,
          enabled: !_saving,
          decoration: const InputDecoration(hintText: 'Instagram'),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: Spacing.md),
          const CommsFieldLabel('Name (slug)'),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _name,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'instagram',
              helperText:
                  'Lowercase, no spaces — used internally, and immutable '
                  'once set',
            ),
          ),
        ],
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Colour'),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final entry in _platformColors.entries)
              GestureDetector(
                onTap: () => setState(() => _color = entry.key),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: _color == entry.key
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 2.5,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        const CommsFieldLabel('Profile URL'),
        const SizedBox(height: Spacing.sm),
        TextField(
          controller: _profileUrl,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://instagram.com/…',
            prefixIcon: Icon(Icons.link, size: 18),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sortOrder,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Sort order'),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _isActive = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        PrimaryButton(
          label: _saving
              ? 'Saving…'
              : (_isEdit ? 'Save changes' : 'Add platform'),
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
