import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_auth/mobilling_auth.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/admin/admin_screens.dart';
import 'features/billing_catalog/catalog_screens.dart';
import 'features/billing_catalog/document_detail_screen.dart';
import 'features/billing_catalog/documents_by_type_screen.dart';
import 'features/billing_money/next_bills_screen.dart';
import 'features/billing_money/pay_bill_screen.dart';
import 'features/billing_money/payments_out_screen.dart';
import 'features/billing_money/record_payment_screen.dart';
import 'features/clients/client_detail_screen.dart';
import 'features/finance/expenses_screen.dart';
import 'features/finance/petty_cash_screen.dart';
import 'features/finance/statutory_screens.dart';
import 'features/comms/broadcast_screen.dart';
import 'features/comms/social_media_screen.dart';
import 'features/comms/sms_screen.dart';
import 'features/comms/whatsapp_screen.dart';
import 'features/crm/appointments_screen.dart';
import 'features/crm/collection_screen.dart';
import 'features/crm/field_marketing_screen.dart';
import 'features/crm/followups_screen.dart';
import 'features/crm/satisfaction_calls_screen.dart';
import 'features/crm/served_customers_screen.dart';
import 'features/home/home_screen.dart';
import 'features/reports/reports_screens.dart';
import 'features/staff_self/attendance_screen.dart';
import 'features/staff_self/staff_reports_screen.dart';
import 'features/staff_self/targets_and_systems_screens.dart';
import 'features/support_admin/announcements_screen.dart';
import 'features/support_admin/canned_replies_screen.dart';
import 'features/support_admin/hosting_accounts_screen.dart';
import 'features/support_admin/knowledgebase_screen.dart';
import 'features/support_admin/staff_domains_screen.dart';
import 'features/tickets/ticket_detail_screen.dart';
import 'providers.dart';

abstract final class Routes {
  static const splash = '/';
  static const login = '/login';
  static const home = '/home';

  static String clientPath(String id) => '/clients/$id';
  static String ticketPath(String id) => '/tickets/$id';
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionControllerProvider);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) {
      final status = session.status;
      final location = state.matchedLocation;

      return switch (status) {
        SessionStatus.unknown ||
        SessionStatus.restoring =>
          location == Routes.splash ? null : Routes.splash,
        SessionStatus.signedOut =>
          location == Routes.login ? null : Routes.login,
        // As in the client app, `expired` stays in place so the re-auth sheet
        // can overlay the current screen.
        SessionStatus.authenticated || SessionStatus.expired =>
          (location == Routes.login || location == Routes.splash)
              ? Routes.home
              : null,
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
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/clients/:id',
        builder: (context, state) => ClientDetailScreen(
          clientId: state.pathParameters['id']!,
          clientName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/tickets/:id',
        builder: (context, state) => TicketDetailScreen(
          ticketId: state.pathParameters['id']!,
        ),
      ),

      // Money movement. '/payments/record' must precede any '/payments/:id'
      // route added later — go_router matches in declaration order.
      GoRoute(
        path: '/payments/record',
        builder: (context, state) => const RecordPaymentScreen(),
      ),
      GoRoute(
        path: '/payments-out',
        builder: (context, state) => const PaymentsOutScreen(),
      ),
      GoRoute(
        path: '/payments-out/new',
        builder: (context, state) => const PayBillScreen(),
      ),
      GoRoute(
        path: '/next-bills',
        builder: (context, state) => const NextBillsScreen(),
      ),

      // Tenant administration
      GoRoute(
        path: '/subscription',
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/automation',
        builder: (context, state) => const AutomationScreen(),
      ),
      GoRoute(
        path: '/team',
        builder: (context, state) => const TeamScreen(),
      ),
      GoRoute(
        path: '/roles',
        builder: (context, state) => const RolesScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      // Reports — hub plus one screen driven by the slug.
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsHubScreen(),
      ),
      GoRoute(
        path: '/reports/:slug',
        builder: (context, state) => ReportScreen(
          slug: state.pathParameters['slug']!,
        ),
      ),

      // My working life
      GoRoute(
        path: '/attendance',
        builder: (context, state) => const AttendanceScreen(),
      ),
      GoRoute(
        path: '/staff-reports',
        builder: (context, state) => const StaffReportsScreen(),
      ),
      GoRoute(
        path: '/staff-targets',
        builder: (context, state) => const StaffTargetsScreen(),
      ),
      GoRoute(
        path: '/my-verifications',
        builder: (context, state) => const MyVerificationsScreen(),
      ),
      GoRoute(
        path: '/system-records',
        builder: (context, state) => const SystemRecordsScreen(),
      ),

      // Outgoing money
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpensesScreen(),
      ),
      GoRoute(
        path: '/expense-categories',
        builder: (context, state) => const ExpenseCategoriesScreen(),
      ),
      GoRoute(
        path: '/petty-cash',
        builder: (context, state) => const PettyCashScreen(),
      ),
      GoRoute(
        path: '/statutory',
        builder: (context, state) => const StatutoryScreen(),
      ),
      GoRoute(
        path: '/statutory-schedule',
        builder: (context, state) => const StatutoryScheduleScreen(),
      ),
      GoRoute(
        path: '/bills',
        builder: (context, state) => const BillsScreen(),
      ),
      GoRoute(
        path: '/bill-categories',
        builder: (context, state) => const BillCategoriesScreen(),
      ),

      // Documents + catalog
      GoRoute(
        path: '/documents/:id',
        builder: (context, state) => DocumentDetailScreen(
          documentId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/quotations',
        builder: (context, state) =>
            const DocumentsByTypeScreen(kind: DocumentKind.quotation),
      ),
      GoRoute(
        path: '/proformas',
        builder: (context, state) =>
            const DocumentsByTypeScreen(kind: DocumentKind.proforma),
      ),
      GoRoute(
        path: '/credit-notes',
        builder: (context, state) =>
            const DocumentsByTypeScreen(kind: DocumentKind.creditNote),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductsScreen(),
      ),
      GoRoute(
        path: '/product-addons',
        builder: (context, state) => const ProductAddonsScreen(),
      ),
      GoRoute(
        path: '/config-options',
        builder: (context, state) => const ConfigOptionsScreen(),
      ),
      GoRoute(
        path: '/coupons',
        builder: (context, state) => const CouponsScreen(),
      ),
      GoRoute(
        path: '/subscriptions',
        builder: (context, state) => const StaffSubscriptionsScreen(),
      ),

      // Support content + service administration
      GoRoute(
        path: '/canned-replies',
        builder: (context, state) => const CannedRepliesScreen(),
      ),
      GoRoute(
        path: '/announcements',
        builder: (context, state) => const AnnouncementsScreen(),
      ),
      GoRoute(
        path: '/knowledgebase',
        builder: (context, state) => const KnowledgebaseScreen(),
      ),
      GoRoute(
        path: '/hosting',
        builder: (context, state) => const HostingAccountsScreen(),
      ),
      GoRoute(
        path: '/domains',
        builder: (context, state) => const StaffDomainsScreen(),
      ),

      // Field work / CRM
      GoRoute(
        path: '/collection',
        builder: (context, state) => const CollectionScreen(),
      ),
      GoRoute(
        path: '/followups',
        builder: (context, state) => const FollowupsScreen(),
      ),
      GoRoute(
        path: '/satisfaction-calls',
        builder: (context, state) => const SatisfactionCallsScreen(),
      ),
      GoRoute(
        path: '/appointments',
        builder: (context, state) => const AppointmentsScreen(),
      ),
      GoRoute(
        path: '/served-customers',
        builder: (context, state) => const ServedCustomersScreen(),
      ),
      GoRoute(
        path: '/field-marketing',
        builder: (context, state) => const FieldMarketingScreen(),
      ),
      GoRoute(
        path: '/field-marketing/:id',
        builder: (context, state) => FieldSessionScreen(
          sessionId: state.pathParameters['id']!,
        ),
      ),

      // Communications
      GoRoute(path: '/sms', builder: (context, state) => const SmsScreen()),
      GoRoute(
        path: '/broadcast',
        builder: (context, state) => const BroadcastScreen(),
      ),
      GoRoute(
        path: '/whatsapp',
        builder: (context, state) => const WhatsappScreen(),
      ),
      GoRoute(
        path: '/social-media',
        builder: (context, state) => const SocialMediaScreen(),
      ),
    ],
  );
});
