import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import '../common/paged_list.dart';
import '../crm/crm_ui.dart' show CrmMetaLine;
import 'notification_providers.dart';

/// The in-app notification centre — mirrors web's bell dropdown as a full
/// screen, since a phone has no room for a 380px popover.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final _listKey = GlobalKey<PagedListViewState>();
  bool _markingAll = false;

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(notificationServiceProvider).markAllAsRead();
      ref.read(notificationsRefreshProvider.notifier).state++;
      _listKey.currentState?.reload();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.isRead) {
      // Optimistic — the list re-fetches regardless of outcome, so a failed
      // mark-read here just means it still shows unread next reload rather
      // than blocking navigation.
      unawaited(ref.read(notificationServiceProvider).markAsRead(n.id));
      ref.read(notificationsRefreshProvider.notifier).state++;
    }
    final target = n.target;
    if (target != null && mounted) context.push(target);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: ShellTopBar(
        eyebrow: 'Account',
        title: 'Notifications',
        trailing: unread == 0
            ? null
            : InkActionButton(
                icon: Icons.done_all_rounded,
                tooltip: 'Mark all read',
                onPressed: _markingAll ? null : _markAllRead,
              ),
      ),
      body: PagedListView<AppNotification>(
        key: _listKey,
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          Spacing.xl,
        ),
        fetch: (page) =>
            ref.read(notificationServiceProvider).notifications(page: page),
        itemBuilder: (context, n) => _NotificationTile(n: n, onTap: _open),
        emptyIcon: Icons.notifications_none_outlined,
        emptyTitle: 'Nothing yet',
        emptyMessage: 'Notifications about your work show up here.',
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});

  final AppNotification n;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      color: n.isRead ? null : scheme.primary.withValues(alpha: 0.06),
      child: ListTile(
        leading: n.isRead
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
        title: Text(
          n.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (n.message.isNotEmpty)
                Text(
                  n.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 2),
              CrmMetaLine(_timeAgo(n.createdAt)),
            ],
          ),
        ),
        onTap: () => onTap(n),
      ),
    );
  }
}

/// A short relative time — "just now", "5m ago", "3h ago", "2d ago", then a
/// plain date once it's old enough that "ago" stops being useful.
String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.day.toString().padLeft(2, '0')}/'
      '${time.month.toString().padLeft(2, '0')}/'
      '${time.year}';
}
