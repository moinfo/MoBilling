import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import 'config/app_config.dart';
import 'config/debug_hooks.dart';
import 'features/push/push_deep_link.dart';
import 'features/push/push_registration.dart';
import 'navigation/shell.dart';
import 'router.dart';

/// Every provider here carries an explicit type annotation; see the client
/// app's providers.dart for why.
final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (ref) => kDebugMode ? DebugTokenStore() : TokenStore(),
);

/// Where the API client reports a 401 and the session controller listens.
///
/// The two genuinely depend on each other — the client needs the session's
/// 401 policy, the session needs the client to talk to the server — and an
/// earlier version closed that loop with `ref.read(sessionControllerProvider)`
/// inside the client's callback. Riverpod rejects that at the moment the
/// callback fires (CircularDependencyError), so every 401 surfaced as
/// "Could not reach the server" instead of running the expiry policy. This
/// hub is the dependency both sides share instead: neither provider watches
/// the other.
class UnauthenticatedHub {
  UnauthenticatedHandler? handler;

  Future<void> call(RequestOptions request) =>
      handler?.call(request) ?? Future<void>.value();
}

final Provider<UnauthenticatedHub> unauthenticatedHubProvider =
    Provider<UnauthenticatedHub>((ref) => UnauthenticatedHub());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  final hub = ref.watch(unauthenticatedHubProvider);

  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenReader: tokens.read,
    onUnauthenticated: hub.call,
  );
});

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

/// iOS has no `GoogleService-Info.plist` / `DefaultFirebaseOptions` entry yet
/// (APNs setup is deferred) — [NoopPushRegistration] there until it does.
final Provider<PushRegistration> pushRegistrationProvider =
    Provider<PushRegistration>(
  (ref) =>
      Platform.isAndroid ? FirebasePushRegistration() : const NoopPushRegistration(),
);

final ChangeNotifierProvider<SessionController> sessionControllerProvider =
    ChangeNotifierProvider<SessionController>((ref) {
  final controller = SessionController(
    authService: ref.watch(authServiceProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    pushRegistration: ref.watch(pushRegistrationProvider),
  );
  ref.watch(unauthenticatedHubProvider).handler =
      controller.handleUnauthenticated;
  return controller;
});

/// Subscribes to tapped-notification events exactly once for the life of the
/// app. A `Provider`'s create callback only runs the first time something
/// watches it, so this doubles as a "run this side effect once" seam —
/// [StaffApp] watches it right alongside `routerProvider` rather than firing
/// it from `main()`, where the router doesn't exist yet.
final Provider<void> pushDeepLinkWiringProvider = Provider<void>((ref) {
  if (Platform.isAndroid) {
    wirePushDeepLinks(
      ref.watch(routerProvider),
      () => ref.read(sessionControllerProvider).session.shell,
    );
  }
});

/// Which bottom tab the staff shell is showing.
///
/// Lifted out of the home screen's State so the persistent bottom bar in
/// [AppChrome] can drive it from anywhere in the app.
final StateProvider<int> staffTabProvider = StateProvider<int>((ref) => 0);

final Provider<SessionStatus> sessionStatusProvider = Provider<SessionStatus>(
  (ref) => ref.watch(sessionControllerProvider).status,
);

final Provider<AuthUser?> currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(sessionControllerProvider).user,
);

final Provider<StaffService> staffServiceProvider = Provider<StaffService>(
  (ref) => StaffService(ref.watch(apiClientProvider)),
);

final AutoDisposeFutureProvider<StaffDashboard> dashboardProvider =
    FutureProvider.autoDispose<StaffDashboard>(
  (ref) => ref.watch(staffServiceProvider).dashboard(),
);

/// Ticket queue, keyed by status filter (null = all).
final AutoDisposeFutureProviderFamily<List<StaffTicket>, String?>
    ticketsProvider =
    FutureProvider.autoDispose.family<List<StaffTicket>, String?>(
  (ref, status) => ref.watch(staffServiceProvider).tickets(status: status),
);

final AutoDisposeFutureProviderFamily<StaffTicket, String> ticketProvider =
    FutureProvider.autoDispose.family<StaffTicket, String>(
  (ref, id) => ref.watch(staffServiceProvider).ticket(id),
);
