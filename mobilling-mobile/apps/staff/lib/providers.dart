import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobilling_api/mobilling_api.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import 'config/app_config.dart';

/// Wiring mirrors the client app; see its providers.dart for the notes on the
/// deliberate ApiClient <-> SessionController cycle and why every provider in
/// it carries an explicit type annotation.
final Provider<TokenStore> tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStoreProvider);

  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenReader: tokens.read,
    onUnauthenticated: (request) =>
        ref.read(sessionControllerProvider).handleUnauthenticated(request),
  );
});

final Provider<AuthService> authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);

final ChangeNotifierProvider<SessionController> sessionControllerProvider =
    ChangeNotifierProvider<SessionController>(
  (ref) => SessionController(
    authService: ref.watch(authServiceProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  ),
);

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
