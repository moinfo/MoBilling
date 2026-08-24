import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobilling_api/mobilling_api.dart'
    show CatalogProduct, DocumentType, StaffClient, UnpaidInvoice;
import 'package:mobilling_auth/mobilling_auth.dart';

import 'config/debug_hooks.dart';

import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/admin/admin_screens.dart';
import 'features/admin/security_screen.dart';
import 'features/billing_catalog/catalog_screens.dart';
import 'features/billing_catalog/document_detail_screen.dart';
import 'features/billing_catalog/document_form_screen.dart';
import 'features/billing_catalog/documents_by_type_screen.dart';
import 'features/billing_money/next_bills_screen.dart';
import 'features/billing_money/pay_bill_screen.dart';
import 'features/billing_money/payments_out_screen.dart';
import 'features/billing_money/record_payment_screen.dart';
import 'features/clients/client_detail_screen.dart';
import 'features/clients/client_form_screen.dart';
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
import 'features/documents/documents_tab.dart' show UnpaidInvoicesScreen;
import 'features/home/home_screen.dart';
import 'features/hr/leave_screen.dart';
import 'features/hr/payroll_screen.dart';
import 'features/ops/add_order_screen.dart';
import 'features/ops/discover_hosting_screen.dart';
import 'features/ops/portal_users_directory_screen.dart';
import 'features/ops/sessions_screen.dart';
import 'features/portal/account/credit_screen.dart';
import 'features/portal/account/portal_users_screen.dart';
import 'features/portal/account/profile_screen.dart';
import 'features/portal/billing/invoice_detail_screen.dart';
import 'features/portal/billing/payments_tab.dart';
import 'features/portal/billing/statement_tab.dart';
import 'features/portal/portal_home_screen.dart';
import 'features/portal/portal_routes.dart';
import 'features/portal/register_screen.dart';
import 'features/portal/services/domain_detail_screen.dart';
import 'features/portal/services/hosting_detail_screen.dart';
import 'features/portal/services/reseller_screen.dart';
import 'features/portal/store/configure_order_screen.dart';
import 'features/portal/store/domain_search_screen.dart';
import 'features/portal/store/order_flow.dart';
import 'features/portal/store/store_screen.dart';
import 'features/portal/support/kb_article_screen.dart';
import 'features/portal/support/new_ticket_screen.dart';
import 'features/portal/support/ticket_detail_screen.dart' as portal_ticket;
import 'features/platform/platform_screens.dart';
import 'features/platform/platform_shell.dart';
import 'features/platform/tenants_screens.dart';
import 'navigation/admin_menu.dart';
import 'navigation/shell.dart';
import 'features/reports/reports_screens.dart';
import 'features/staff_self/attendance_screen.dart';
import 'features/staff_self/staff_reports_screen.dart';
import 'features/staff_self/targets_and_systems_screens.dart';
import 'features/support_admin/announcements_screen.dart';
import 'features/support_admin/canned_replies_screen.dart';
import 'features/support_admin/hosting_accounts_screen.dart';
import 'features/support_admin/knowledgebase_screen.dart';
import 'features/support_admin/manage_services_screen.dart';
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
  // `.notifier`, not the provider itself: watching a ChangeNotifierProvider
  // rebuilds this provider on every notifyListeners(), which replaced the
  // whole GoRouter (and its navigation stack) on each status change. With a
  // state that keeps the splash mounted (`offline`) that became a loop —
  // remount → restore() → notify → new router → remount — hammering
  // /auth/me 60 times a second. `refreshListenable` below is the one
  // intended reaction to session changes.
  final session = ref.watch(sessionControllerProvider.notifier);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: session,
    redirect: (context, state) {
      final status = session.status;
      final location = state.matchedLocation;

      // Where this user belongs, decided once from the login response.
      final home = switch (session.session.shell) {
        AppShell.portal => PortalRoutes.home,
        AppShell.staff => Routes.home,
        AppShell.admin => AdminRoutes.home,
      };

      return switch (status) {
        // `offline` stays on the splash too: it shows the retry / sign-out
        // choice, since we hold a token but don't know whose it is.
        SessionStatus.unknown ||
        SessionStatus.restoring ||
        SessionStatus.offline =>
          location == Routes.splash ? null : Routes.splash,

        // Registration is reachable while signed out — it is how a client
        // with no portal account gets one.
        // `locked` shares the sign-in screen: it shows the biometric button
        // and still accepts a password, which replaces the locked session.
        SessionStatus.signedOut || SessionStatus.locked =>
          (location == Routes.login || location == PortalRoutes.register)
              ? null
              : Routes.login,

        // `expired` deliberately stays put so the re-auth sheet can overlay
        // the current screen rather than discarding half-typed work.
        SessionStatus.authenticated || SessionStatus.expired =>
          (location == Routes.login ||
                  location == Routes.splash ||
                  location == PortalRoutes.register)
              ? (_debugStartRoute() ?? home)
              // A client must not wander into a staff route and vice versa:
              // the API would 403, but bouncing to their own home is clearer
              // than a screen full of errors.
              : _isForeignShell(location, session.session.shell)
              ? home
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

      // ── Platform super-admin shell ─────────────────────────────────────
      GoRoute(
        path: AdminRoutes.home,
        builder: (context, state) => const PlatformHomeScreen(),
      ),
      GoRoute(
        path: AdminRoutes.tenants,
        builder: (context, state) => const TenantsScreen(),
      ),
      // Static admin paths precede '/admin/tenants/:id' below.
      GoRoute(
        path: AdminRoutes.plans,
        builder: (context, state) => const PlatformPlansScreen(),
      ),
      GoRoute(
        path: AdminRoutes.currencies,
        builder: (context, state) => const CurrenciesScreen(),
      ),
      GoRoute(
        path: AdminRoutes.smsPackages,
        builder: (context, state) => const SmsPackagesScreen(),
      ),
      GoRoute(
        path: AdminRoutes.smsPurchases,
        builder: (context, state) => const SmsPurchasesScreen(),
      ),
      GoRoute(
        path: AdminRoutes.permissions,
        builder: (context, state) => const PlatformPermissionsScreen(),
      ),
      GoRoute(
        path: AdminRoutes.roleTemplates,
        builder: (context, state) => const RoleTemplatesScreen(),
      ),
      GoRoute(
        path: AdminRoutes.settings,
        builder: (context, state) => const PlatformSettingsScreen(),
      ),
      GoRoute(
        path: '/admin/tenants/:id/email',
        builder: (context, state) =>
            TenantEmailSettingsScreen(tenantId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/tenants/:id/sms',
        builder: (context, state) =>
            TenantSmsSettingsScreen(tenantId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/tenants/:id/templates',
        builder: (context, state) =>
            TenantTemplatesScreen(tenantId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin/tenants/:id',
        builder: (context, state) =>
            TenantDetailScreen(tenantId: state.pathParameters['id']!),
      ),

      // ── Client portal shell ────────────────────────────────────────────
      // Everything under /portal is the client-facing app. Namespaced so a
      // client route can never collide with a staff one of the same name.
      GoRoute(
        path: PortalRoutes.home,
        builder: (context, state) => const PortalHomeScreen(),
      ),
      GoRoute(
        path: PortalRoutes.register,
        builder: (context, state) {
          final args = state.extra;
          return RegisterScreen(
            email: args is RegisterArgs ? args.email : null,
            clientName: args is RegisterArgs ? args.clientName : null,
          );
        },
      ),
      GoRoute(
        path: '/portal/invoices/:id',
        builder: (context, state) =>
            PortalInvoiceDetailScreen(documentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: PortalRoutes.payments,
        builder: (context, state) => const PortalPaymentsTab(),
      ),
      GoRoute(
        path: PortalRoutes.statement,
        builder: (context, state) => const StatementTab(),
      ),
      // 'new' precedes ':id' — go_router matches in declaration order.
      GoRoute(
        path: PortalRoutes.newTicket,
        builder: (context, state) => const NewTicketScreen(),
      ),
      GoRoute(
        path: '/portal/tickets/:id',
        builder: (context, state) => portal_ticket.TicketDetailScreen(
          ticketId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/portal/kb/:slug',
        builder: (context, state) =>
            KbArticleScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/portal/hosting/:id',
        builder: (context, state) =>
            PortalHostingDetailScreen(accountId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/portal/domains/:id',
        builder: (context, state) =>
            PortalDomainDetailScreen(domainId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: PortalRoutes.store,
        builder: (context, state) => const StoreScreen(),
      ),
      GoRoute(
        path: PortalRoutes.configureOrder,
        builder: (context, state) => ConfigureOrderScreen(
          product: state.extra! as CatalogProduct,
          flow: OrderFlow.portal(ref),
        ),
      ),
      GoRoute(
        path: PortalRoutes.domainSearch,
        builder: (context, state) => const DomainSearchScreen(),
      ),
      GoRoute(
        path: PortalRoutes.profile,
        builder: (context, state) => const PortalProfileScreen(),
      ),
      GoRoute(
        path: PortalRoutes.portalUsers,
        builder: (context, state) => const PortalUsersScreen(),
      ),
      GoRoute(
        path: PortalRoutes.credit,
        builder: (context, state) => const CreditScreen(),
      ),
      GoRoute(
        path: PortalRoutes.reseller,
        builder: (context, state) => const PortalResellerScreen(),
      ),
      // '/clients/new' precedes '/clients/:id', which would otherwise take
      // 'new' for an id. The screens reach these by push (the edit form needs
      // the whole record to round-trip every column, and `extra` does not
      // survive a cold deep link); these exist so a link can still land.
      GoRoute(
        path: '/clients/new',
        builder: (context, state) => const ClientFormScreen(),
      ),
      GoRoute(
        path: '/clients/:id/edit',
        builder: (context, state) =>
            ClientFormScreen(existing: state.extra as StaffClient?),
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
        builder: (context, state) =>
            TicketDetailScreen(ticketId: state.pathParameters['id']!),
      ),

      // Money movement. '/payments/record' must precede any '/payments/:id'
      // route added later — go_router matches in declaration order.
      GoRoute(
        path: '/payments/record',
        // `extra` carries an invoice when the flow starts from that invoice's
        // detail screen, so the picker is skipped.
        builder: (context, state) =>
            RecordPaymentScreen(invoice: state.extra as UnpaidInvoice?),
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
      GoRoute(path: '/team', builder: (context, state) => const TeamScreen()),
      GoRoute(path: '/roles', builder: (context, state) => const RolesScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      // Self-service, so no permission gates it — reached from the account
      // sheet rather than the menu, which mirrors the web (2FA lives inside
      // the Settings page there, not in the sidebar).
      GoRoute(
        path: '/security',
        builder: (context, state) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (context, state) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/portal-users',
        builder: (context, state) => const PortalUsersDirectoryScreen(),
      ),

      // Orders on a client's behalf. '/orders/configure' carries its
      // product + client via `extra`; the portal's configure screen is
      // reused with a staff OrderFlow.
      GoRoute(
        path: '/orders',
        builder: (context, state) => const AddOrderScreen(),
      ),
      GoRoute(
        path: '/orders/configure',
        builder: (context, state) =>
            StaffConfigureOrderScreen(args: state.extra! as StaffOrderArgs),
      ),

      // HR
      GoRoute(path: '/leave', builder: (context, state) => const LeaveScreen()),
      GoRoute(
        path: '/payroll',
        builder: (context, state) => const PayrollScreen(),
      ),
      GoRoute(
        path: '/payroll/runs/:id',
        builder: (context, state) =>
            PayrollRunScreen(runId: state.pathParameters['id']!),
      ),

      // Reports — hub plus one screen driven by the slug.
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsHubScreen(),
      ),
      GoRoute(
        path: '/reports/:slug',
        builder: (context, state) =>
            ReportScreen(slug: state.pathParameters['slug']!),
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
      GoRoute(path: '/bills', builder: (context, state) => const BillsScreen()),
      GoRoute(
        path: '/bill-categories',
        builder: (context, state) => const BillCategoriesScreen(),
      ),

      // Documents + catalog. '/documents/new' must precede '/documents/:id',
      // which would otherwise swallow 'new' as an id.
      //
      // This is the blank-form entry — a deep link, or the debug route hook.
      // The screens push `raiseDocument()` instead, because editing a
      // document or seeding a credit note from an invoice carries objects
      // that `extra` cannot survive a real deep link with.
      GoRoute(
        path: '/documents/new',
        builder: (context, state) => DocumentFormScreen(
          type: state.extra is DocumentType
              ? state.extra! as DocumentType
              : DocumentType.invoice,
        ),
      ),
      GoRoute(
        path: '/documents/:id',
        builder: (context, state) =>
            DocumentDetailScreen(documentId: state.pathParameters['id']!),
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
      // '/invoices' itself is a bottom tab (see home_screen.dart); this is
      // the web's "Unpaid Invoices" shortcut as its own screen.
      GoRoute(
        path: '/invoices/unpaid',
        builder: (context, state) => const UnpaidInvoicesScreen(),
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
        path: '/hosting/discover',
        builder: (context, state) => const DiscoverHostingScreen(),
      ),
      GoRoute(
        path: '/hosting/services',
        builder: (context, state) => const ManageServicesScreen(),
      ),
      // The path parameter is the client_subscription id, not a hosting
      // account: services with nothing provisioned are managed here too.
      GoRoute(
        path: '/hosting/services/:id',
        builder: (context, state) => ManageServiceDetailScreen(
          subscriptionId: state.pathParameters['id']!,
        ),
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
        builder: (context, state) =>
            FieldSessionScreen(sessionId: state.pathParameters['id']!),
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

/// Debug-only: open a specific screen on launch instead of home. See
/// [DebugHooks] for the review workflow this serves.
String? _debugStartRoute() => DebugHooks.startRoute;

/// True when [location] belongs to a shell other than [shell].
///
/// Only cross-shell leakage is blocked; within a shell every screen is already
/// gated by the drawer's permission filter and, ultimately, by the API. The
/// prefixes are the whole contract: `/portal/*` is the client app, `/admin/*`
/// is the platform area, everything else is staff.
bool _isForeignShell(String location, AppShell shell) {
  // Segment-exact: the staff route `/portal-users` is not a portal route.
  bool under(String prefix) =>
      location == prefix || location.startsWith('$prefix/');
  final isPortalRoute = under('/portal');
  final isAdminRoute = under('/admin');

  return switch (shell) {
    AppShell.portal => !isPortalRoute,
    AppShell.admin => !isAdminRoute,
    AppShell.staff => isPortalRoute || isAdminRoute,
  };
}
