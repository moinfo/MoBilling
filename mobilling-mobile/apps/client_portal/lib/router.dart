import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/billing/invoice_detail_screen.dart';
import 'features/billing/payments_tab.dart';
import 'features/billing/statement_tab.dart';
import 'features/home/home_screen.dart';
import 'package:mobilling_api/mobilling_api.dart' show CatalogProduct;

import 'features/account/credit_screen.dart';
import 'features/account/portal_users_screen.dart';
import 'features/account/profile_screen.dart';
import 'features/services/domain_detail_screen.dart';
import 'features/services/hosting_detail_screen.dart';
import 'features/store/configure_order_screen.dart';
import 'features/store/domain_search_screen.dart';
import 'features/store/store_screen.dart';
import 'features/support/kb_article_screen.dart';
import 'features/support/new_ticket_screen.dart';
import 'features/support/ticket_detail_screen.dart';
import 'providers.dart';

abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const newTicket = '/tickets/new';
  static const payments = '/payments';
  static const statement = '/statement';
  static const store = '/store';
  static const configureOrder = '/store/configure';
  static const domainSearch = '/store/domain';
  static const profile = '/profile';
  static const portalUsers = '/users';
  static const credit = '/credit';

  static String invoicePath(String id) => '/invoices/$id';
  static String ticketPath(String id) => '/tickets/$id';
  static String kbPath(String slug) => '/kb/$slug';
  static String hostingPath(String id) => '/hosting/$id';
  static String domainPath(String id) => '/domains/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  // The session controller is a ChangeNotifier, so go_router can listen to it
  // directly and re-run [redirect] on every status change. Routing therefore
  // follows authentication automatically, and no screen needs its own guard.
  final session = ref.watch(sessionControllerProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) {
      final status = session.status;
      final location = state.matchedLocation;
      final onAuthScreen =
          location == Routes.login || location == Routes.register;

      return switch (status) {
        // Still reading the keystore — hold on the splash.
        SessionStatus.unknown ||
        SessionStatus.restoring =>
          location == Routes.splash ? null : Routes.splash,

        SessionStatus.signedOut => onAuthScreen ? null : Routes.login,

        // `expired` deliberately does NOT redirect. The 401 policy keeps the
        // user's screen intact and lets the shell overlay a re-authentication
        // prompt, so partly-entered work survives. Bouncing to /login here
        // would defeat the whole policy.
        SessionStatus.authenticated || SessionStatus.expired =>
          (onAuthScreen || location == Routes.splash) ? Routes.home : null,
      };
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) {
          // Carried over from the login screen when the backend answered 449,
          // so the user does not retype an address we already verified.
          final args = state.extra;
          return RegisterScreen(
            email: args is RegisterArgs ? args.email : null,
            clientName: args is RegisterArgs ? args.clientName : null,
          );
        },
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/invoices/:id',
        builder: (context, state) => InvoiceDetailScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      // 'new' must precede ':id' — go_router matches in declaration order.
      GoRoute(
        path: Routes.newTicket,
        builder: (context, state) => const NewTicketScreen(),
      ),
      GoRoute(
        path: '/tickets/:id',
        builder: (context, state) => TicketDetailScreen(
          ticketId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/kb/:slug',
        builder: (context, state) => KbArticleScreen(
          slug: state.pathParameters['slug']!,
        ),
      ),
      GoRoute(
        path: Routes.payments,
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Payment history')),
          body: const PaymentsTab(),
        ),
      ),
      GoRoute(
        path: Routes.statement,
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Account statement')),
          body: const StatementTab(),
        ),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.portalUsers,
        builder: (context, state) => const PortalUsersScreen(),
      ),
      GoRoute(
        path: Routes.credit,
        builder: (context, state) => const CreditScreen(),
      ),
      GoRoute(
        path: Routes.store,
        builder: (context, state) => const StoreScreen(),
      ),
      GoRoute(
        path: Routes.configureOrder,
        builder: (context, state) => ConfigureOrderScreen(
          product: state.extra as CatalogProduct,
        ),
      ),
      GoRoute(
        path: Routes.domainSearch,
        builder: (context, state) => const DomainSearchScreen(),
      ),
      GoRoute(
        path: '/hosting/:id',
        builder: (context, state) => HostingDetailScreen(
          accountId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/domains/:id',
        builder: (context, state) => DomainDetailScreen(
          domainId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

/// Hand-off from sign-in to the OTP/registration screen.
class RegisterArgs {
  const RegisterArgs({required this.email, this.clientName});

  final String email;

  /// The company name the backend matched, shown as reassurance that the code
  /// went to the right account.
  final String? clientName;
}
