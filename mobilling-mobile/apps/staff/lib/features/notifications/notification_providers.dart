import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';

import '../../providers.dart';

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>(
      (ref) => NotificationService(ref.watch(apiClientProvider)),
    );

/// Bumped after mark-read/mark-all-read so both the badge and the list
/// refetch together — the same pattern `broadcastsRefreshProvider` uses.
final StateProvider<int> notificationsRefreshProvider = StateProvider<int>(
  (ref) => 0,
);

/// Polls every 30 seconds, matching the web bell's `refetchInterval` — a
/// push can land while the app is open with no local-notification banner to
/// announce it (see PUSH_SETUP.md's "foreground display" gap), so the badge
/// is the only way an already-open session finds out.
final AutoDisposeStreamProvider<int> unreadNotificationCountProvider =
    StreamProvider.autoDispose<int>((ref) async* {
      ref.watch(notificationsRefreshProvider);
      final service = ref.watch(notificationServiceProvider);

      Future<int> fetch() async {
        try {
          return await service.unreadCount();
        } on ApiException {
          return 0;
        }
      }

      yield await fetch();
      yield* Stream.periodic(
        const Duration(seconds: 30),
      ).asyncMap((_) => fetch());
    });
