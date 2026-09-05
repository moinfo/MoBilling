import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_ui/mobilling_ui.dart';

import 'notification_providers.dart';

/// The masthead bell — an [InkActionButton] with an unread badge, matching
/// web's `NotificationBell`. Placed on the dashboard tab's masthead
/// specifically (the one screen every staff/admin session always has), not
/// wired into every screen's own `trailing` — this app has no single chrome
/// layer that owns every masthead, and duplicating it screen by screen would
/// drift out of sync.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkActionButton(
          icon: Icons.notifications_outlined,
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
        ),
        if (unread > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: InkPanel.ground, width: 1.5),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
