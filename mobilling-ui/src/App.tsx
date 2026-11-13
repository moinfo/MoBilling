import { lazy, Suspense } from 'react';
import { useAppBrandingHead } from './branding';
import { MantineProvider, Center, Loader } from '@mantine/core';
import { theme } from './theme';
import { LanguageProvider } from './i18n/LanguageContext';
import { Notifications } from '@mantine/notifications';
import { ModalsProvider } from '@mantine/modals';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import ProtectedRoute from './components/Layout/ProtectedRoute';
import AppLayout from './components/Layout/AppShell';
import AdminShell from './components/Layout/AdminShell';

// All page components are lazy-loaded so the main bundle stays small — every
// route, including tiny public ones like /wifi/:routerId, used to force a
// ~2MB download before anything could render. A single <Suspense> above the
// whole <Routes> tree (see AppRoutes below) covers all of them.
const Login = lazy(() => import('./pages/Login'));
const Register = lazy(() => import('./pages/Register'));
const Install = lazy(() => import('./pages/Install'));
const LicenseAgreement = lazy(() => import('./pages/LicenseAgreement'));
const BuyLicense = lazy(() => import('./pages/BuyLicense'));
const ForgotPassword = lazy(() => import('./pages/ForgotPassword'));
const ResetPassword = lazy(() => import('./pages/ResetPassword'));
const ImpersonateBridge = lazy(() => import('./pages/ImpersonateBridge'));
const Dashboard = lazy(() => import('./pages/Dashboard'));
const Landing = lazy(() => import('./pages/Landing'));
const Clients = lazy(() => import('./pages/Clients'));
const ClientProfile = lazy(() => import('./pages/ClientProfile'));
const PortalUsersAdmin = lazy(() => import('./pages/PortalUsersAdmin'));
const ProductServices = lazy(() => import('./pages/ProductServices'));
const ProductAddons = lazy(() => import('./pages/ProductAddons'));
const ConfigOptions = lazy(() => import('./pages/ConfigOptions'));
const Coupons = lazy(() => import('./pages/Coupons'));
const Quotations = lazy(() => import('./pages/Quotations'));
const Proformas = lazy(() => import('./pages/Proformas'));
const Invoices = lazy(() => import('./pages/Invoices'));
const Orders = lazy(() => import('./pages/Orders'));
const CreditNotes = lazy(() => import('./pages/CreditNotes'));
const BillCategories = lazy(() => import('./pages/BillCategories'));
const Bills = lazy(() => import('./pages/Bills'));
const PaymentsIn = lazy(() => import('./pages/PaymentsIn'));
const ReceivePayments = lazy(() => import('./pages/ReceivePayments'));
const NextBills = lazy(() => import('./pages/NextBills'));
const ClientSubscriptions = lazy(() => import('./pages/ClientSubscriptions'));
const RetainerBilling = lazy(() => import('./pages/RetainerBilling'));
const PaymentsOut = lazy(() => import('./pages/PaymentsOut'));
const Settings = lazy(() => import('./pages/Settings'));
const Users = lazy(() => import('./pages/Users'));
const Sessions = lazy(() => import('./pages/Sessions'));
const Roles = lazy(() => import('./pages/Roles'));
const AdminDashboard = lazy(() => import('./pages/admin/Dashboard'));
const Tenants = lazy(() => import('./pages/admin/Tenants'));
const WifiSettlements = lazy(() => import('./pages/admin/WifiSettlements'));
const TenantUsers = lazy(() => import('./pages/admin/TenantUsers'));
const EmailSettings = lazy(() => import('./pages/admin/EmailSettings'));
const SmsSettingsAdmin = lazy(() => import('./pages/admin/SmsSettings'));
const SmsPackagesAdmin = lazy(() => import('./pages/admin/SmsPackages'));
const LicensesAdmin = lazy(() => import('./pages/admin/Licenses'));
const LicensePlansAdmin = lazy(() => import('./pages/admin/LicensePlans'));
const ReleasesAdmin = lazy(() => import('./pages/admin/Releases'));
const SmsPurchasesAdmin = lazy(() => import('./pages/admin/SmsPurchases'));
const SubscriptionPlansAdmin = lazy(() => import('./pages/admin/SubscriptionPlans'));
const TenantProfile = lazy(() => import('./pages/admin/TenantProfile'));
const CurrenciesAdmin = lazy(() => import('./pages/admin/Currencies'));
const PlatformSettingsAdmin = lazy(() => import('./pages/admin/PlatformSettings'));
const PermissionsAdmin = lazy(() => import('./pages/admin/Permissions'));
const RolesAdmin = lazy(() => import('./pages/admin/Roles'));
const TemplatesAdmin = lazy(() => import('./pages/admin/Templates'));
const ExpenseCategories = lazy(() => import('./pages/ExpenseCategories'));
const Expenses = lazy(() => import('./pages/Expenses'));
const SystemRecords = lazy(() => import('./pages/SystemRecords'));
const SystemRecordExpenses = lazy(() => import('./pages/SystemRecordExpenses'));
const WifiRouters = lazy(() => import('./pages/WifiRouters'));
const WifiPlans = lazy(() => import('./pages/WifiPlans'));
const WifiVoucherPurchases = lazy(() => import('./pages/WifiVoucherPurchases'));
const WifiEarnings = lazy(() => import('./pages/WifiEarnings'));
// SystemVerifications is now mounted as a tab inside Settings.tsx — no standalone route.
const MyVerifications = lazy(() => import('./pages/MyVerifications'));
// Systems, Bank Accounts, System Properties are now accessed via the
// Settings page tabs (Settings.tsx) — no standalone routes needed.
const PettyCash = lazy(() => import('./pages/PettyCash'));
const Statutories = lazy(() => import('./pages/Statutories'));
const StatutorySchedule = lazy(() => import('./pages/StatutorySchedule'));
const Sms = lazy(() => import('./pages/Sms'));
const Subscription = lazy(() => import('./pages/Subscription'));
const Automation = lazy(() => import('./pages/Automation'));
const Broadcast = lazy(() => import('./pages/Broadcast'));
const BroadcastDeliveryReport = lazy(() => import('./pages/BroadcastDeliveryReport'));
const WhatsappContacts = lazy(() => import('./pages/WhatsappContacts'));
const HostingAccounts = lazy(() => import('./pages/HostingAccounts'));
const DiscoverHostingAccounts = lazy(() => import('./pages/DiscoverHostingAccounts'));
const Subdomains = lazy(() => import('./pages/Subdomains'));
const BandwidthUsage = lazy(() => import('./pages/BandwidthUsage'));
const DiskUsage = lazy(() => import('./pages/DiskUsage'));
const BackupStatus = lazy(() => import('./pages/BackupStatus'));
const EmailAccounts = lazy(() => import('./pages/EmailAccounts'));
const MysqlDatabases = lazy(() => import('./pages/MysqlDatabases'));
const HostingPackages = lazy(() => import('./pages/HostingPackages'));
const ServerHealth = lazy(() => import('./pages/ServerHealth'));
const DnsZone = lazy(() => import('./pages/DnsZone'));
const Linode = lazy(() => import('./pages/Linode'));
const CronJobs = lazy(() => import('./pages/CronJobs'));
const PhpVersions = lazy(() => import('./pages/PhpVersions'));
const FtpAccounts = lazy(() => import('./pages/FtpAccounts'));
const SslExpiry = lazy(() => import('./pages/SslExpiry'));
const ServiceManagement = lazy(() => import('./pages/ServiceManagement'));
const Domains = lazy(() => import('./pages/Domains'));
const DomainActivity = lazy(() => import('./pages/DomainActivity'));
const DomainDetails = lazy(() => import('./pages/DomainDetails'));
const Tickets = lazy(() => import('./pages/Tickets'));
const CannedReplies = lazy(() => import('./pages/CannedReplies'));
const Announcements = lazy(() => import('./pages/Announcements'));
const Knowledgebase = lazy(() => import('./pages/Knowledgebase'));
const FieldMarketing = lazy(() => import('./pages/FieldMarketing'));
const SocialMedia = lazy(() => import('./pages/SocialMedia'));
const ServedCustomers = lazy(() => import('./pages/ServedCustomers'));
const StaffReports = lazy(() => import('./pages/StaffReports'));
const Attendance = lazy(() => import('./pages/Attendance'));
const WorkLocations = lazy(() => import('./pages/WorkLocations'));
const StaffTargets = lazy(() => import('./pages/StaffTargets'));
const UserProfile = lazy(() => import('./pages/UserProfile'));
const Leave = lazy(() => import('./pages/Leave'));
const Payroll = lazy(() => import('./pages/Payroll'));
const Collection = lazy(() => import('./pages/Collection'));
const Followups = lazy(() => import('./pages/Followups'));
const ResellerApplications = lazy(() => import('./pages/ResellerApplications'));
const Wallet = lazy(() => import('./pages/Wallet'));
const MyCollections = lazy(() => import('./pages/MyCollections'));
const SatisfactionCalls = lazy(() => import('./pages/SatisfactionCalls'));
const Appointments = lazy(() => import('./pages/Appointments'));
import PortalShell from './components/Layout/PortalShell';
const PortalDashboard = lazy(() => import('./pages/portal/PortalDashboard'));
const PortalDocuments = lazy(() => import('./pages/portal/PortalDocuments'));
const PortalPayments = lazy(() => import('./pages/portal/PortalPayments'));
const PortalWallet = lazy(() => import('./pages/portal/PortalWallet'));
const PortalReseller = lazy(() => import('./pages/portal/PortalReseller'));
const PortalStatement = lazy(() => import('./pages/portal/PortalStatement'));
const PortalSubscriptions = lazy(() => import('./pages/portal/PortalSubscriptions'));
const PortalWifi = lazy(() => import('./pages/portal/PortalWifi'));
const PortalHosting = lazy(() => import('./pages/portal/PortalHosting'));
const PortalServers = lazy(() => import('./pages/portal/PortalServers'));
const PortalLinodeServerPage = lazy(() => import('./pages/portal/PortalLinodeServerPage'));
const PortalDomains = lazy(() => import('./pages/portal/PortalDomains'));
const PortalTickets = lazy(() => import('./pages/portal/PortalTickets'));
const PortalServiceDetails = lazy(() => import('./pages/portal/PortalServiceDetails'));
const PortalDomainDetails = lazy(() => import('./pages/portal/PortalDomainDetails'));
const PortalInvoiceView = lazy(() => import('./pages/portal/PortalInvoiceView'));
const PortalTicketNew = lazy(() => import('./pages/portal/PortalTicketNew'));
const PortalTicketView = lazy(() => import('./pages/portal/PortalTicketView'));
const PortalLogin = lazy(() => import('./pages/portal/PortalLogin'));
const PortalForgotPassword = lazy(() => import('./pages/portal/PortalForgotPassword'));
const PortalRegister = lazy(() => import('./pages/portal/PortalRegister'));
const PortalAnnouncements = lazy(() => import('./pages/portal/PortalAnnouncements'));
const PortalKnowledgebase = lazy(() => import('./pages/portal/PortalKnowledgebase'));
const PortalProductServices = lazy(() => import('./pages/portal/PortalProductServices'));
const PortalProfile = lazy(() => import('./pages/portal/PortalProfile'));
const PortalUsers = lazy(() => import('./pages/portal/PortalUsers'));
import OrderRoute from './components/order/OrderRoute';
const OrderIndex = lazy(() => import('./pages/order/OrderIndex'));
const OrderCategory = lazy(() => import('./pages/order/OrderCategory'));
const OrderDomain = lazy(() => import('./pages/order/OrderDomain'));
const RevenueSummary = lazy(() => import('./pages/reports/RevenueSummary'));
const OutstandingAging = lazy(() => import('./pages/reports/OutstandingAging'));
const ClientStatementReport = lazy(() => import('./pages/reports/ClientStatementReport'));
const PaymentCollectionReport = lazy(() => import('./pages/reports/PaymentCollectionReport'));
const ExpenseReportPage = lazy(() => import('./pages/reports/ExpenseReportPage'));
const SystemRecordsReportPage = lazy(() => import('./pages/reports/SystemRecordsReportPage'));
const BankBalanceStatementReportPage = lazy(() => import('./pages/reports/BankBalanceStatementReportPage'));
const SystemVerificationsReportPage = lazy(() => import('./pages/reports/SystemVerificationsReportPage'));
const ProfitLossReport = lazy(() => import('./pages/reports/ProfitLossReport'));
const StatutoryComplianceReport = lazy(() => import('./pages/reports/StatutoryComplianceReport'));
const SubscriptionReportPage = lazy(() => import('./pages/reports/SubscriptionReportPage'));
const CollectionEffectivenessReport = lazy(() => import('./pages/reports/CollectionEffectivenessReport'));
const CommunicationLogReport = lazy(() => import('./pages/reports/CommunicationLogReport'));
const SatisfactionReportPage = lazy(() => import('./pages/reports/SatisfactionReport'));
const SubscriptionExpired = lazy(() => import('./pages/SubscriptionExpired'));
const LicenseInactive = lazy(() => import('./pages/LicenseInactive'));
const PesapalCallback = lazy(() => import('./pages/PesapalCallback'));
const PayInvoice = lazy(() => import('./pages/PayInvoice'));
const WifiCheckout = lazy(() => import('./pages/public/WifiCheckout'));
const WifiBalanceCheck = lazy(() => import('./pages/public/WifiBalanceCheck'));

import '@mantine/core/styles.css';
import '@mantine/dates/styles.css';
import '@mantine/notifications/styles.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: false },
  },
});

function AppBrandingHead() {
  useAppBrandingHead();
  return null;
}

/** Shown only while a lazy-loaded chunk is still downloading. */
function LazyPageFallback() {
  return (
    <Center mih="100vh">
      <Loader />
    </Center>
  );
}

export default function App() {
  return (
    <MantineProvider theme={theme} defaultColorScheme="auto">
      <Notifications position="top-right" />
      <LanguageProvider>
      <ModalsProvider>
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            <AuthProvider>
              <AppBrandingHead />
              <Suspense fallback={<LazyPageFallback />}>
              <Routes>
                <Route path="/" element={<Landing />} />
                <Route path="/login" element={<Login />} />
                <Route path="/register" element={<Register />} />
                <Route path="/install" element={<Install />} />
                <Route path="/license-agreement" element={<LicenseAgreement />} />
                <Route path="/buy-license" element={<BuyLicense />} />
                <Route path="/portal/login" element={<PortalLogin />} />
                <Route path="/portal/forgot-password" element={<PortalForgotPassword />} />
                <Route path="/portal/register" element={<PortalRegister />} />
                <Route path="/forgot-password" element={<ForgotPassword />} />
                <Route path="/reset-password" element={<ResetPassword />} />
                <Route path="/impersonate-bridge" element={<ImpersonateBridge />} />
                <Route path="/pesapal/callback" element={<PesapalCallback />} />
                <Route path="/pay/:id" element={<PayInvoice />} />
                <Route path="/wifi/:routerId" element={<WifiCheckout />} />
                <Route path="/wifi/:routerId/status/:purchaseId" element={<WifiCheckout />} />
                <Route path="/wifi/:routerId/balance" element={<WifiBalanceCheck />} />

                {/* Subscription expired (standalone, no sidebar) */}
                <Route
                  path="/subscription/expired"
                  element={
                    <ProtectedRoute allowExpired>
                      <SubscriptionExpired />
                    </ProtectedRoute>
                  }
                />

                {/* Self-hosted install's license inactive (standalone, no sidebar) */}
                <Route
                  path="/license-inactive"
                  element={
                    <ProtectedRoute allowExpired>
                      <LicenseInactive />
                    </ProtectedRoute>
                  }
                />

                {/* Super Admin routes */}
                <Route
                  element={
                    <ProtectedRoute requiredRole="super_admin">
                      <AdminShell />
                    </ProtectedRoute>
                  }
                >
                  <Route path="/admin/dashboard" element={<AdminDashboard />} />
                  <Route path="/admin/tenants" element={<Tenants />} />
                  <Route path="/admin/wifi-settlements" element={<WifiSettlements />} />
                  <Route path="/admin/tenants/:tenantId" element={<TenantProfile />} />
                  <Route path="/admin/tenants/:tenantId/users" element={<TenantUsers />} />
                  <Route path="/admin/email-settings" element={<EmailSettings />} />
                  <Route path="/admin/email-templates" element={<TemplatesAdmin />} />
                  <Route path="/admin/sms-settings" element={<SmsSettingsAdmin />} />
                  <Route path="/admin/sms-packages" element={<SmsPackagesAdmin />} />
                  <Route path="/admin/licenses" element={<LicensesAdmin />} />
                  <Route path="/admin/license-plans" element={<LicensePlansAdmin />} />
                  <Route path="/admin/releases" element={<ReleasesAdmin />} />
                  <Route path="/admin/sms-purchases" element={<SmsPurchasesAdmin />} />
                  <Route path="/admin/subscription-plans" element={<SubscriptionPlansAdmin />} />
                  <Route path="/admin/currencies" element={<CurrenciesAdmin />} />
                  <Route path="/admin/permissions" element={<PermissionsAdmin />} />
                  <Route path="/admin/roles" element={<RolesAdmin />} />
                  <Route path="/admin/platform-settings" element={<PlatformSettingsAdmin />} />
                </Route>

                {/* Tenant user routes */}
                <Route
                  element={
                    <ProtectedRoute>
                      <AppLayout />
                    </ProtectedRoute>
                  }
                >
                  <Route path="/dashboard" element={<Dashboard />} />
                  <Route path="/clients" element={<Clients />} />
                  <Route path="/clients/:clientId" element={<ClientProfile />} />
                  <Route path="/portal-users" element={<PortalUsersAdmin />} />
                  <Route path="/product-services" element={<ProductServices />} />
                  <Route path="/product-addons" element={<ProductAddons />} />
                  <Route path="/config-options" element={<ConfigOptions />} />
                  <Route path="/coupons" element={<Coupons />} />
                  <Route path="/quotations" element={<Quotations />} />
                  <Route path="/proformas" element={<Proformas />} />
                  <Route path="/invoices" element={<Invoices />} />
                  <Route path="/orders" element={<Orders />} />
                  <Route path="/credit-notes" element={<CreditNotes />} />
                  <Route path="/payments-in" element={<PaymentsIn />} />
                  <Route path="/receive-payments" element={<ReceivePayments />} />
                  <Route path="/client-subscriptions" element={<ClientSubscriptions />} />
                  <Route path="/client-billed" element={<RetainerBilling />} />
                  <Route path="/next-bills" element={<NextBills />} />
                  <Route path="/statutories" element={<Statutories />} />
                  <Route path="/statutory-schedule" element={<StatutorySchedule />} />
                  <Route path="/bills" element={<Bills />} />
                  <Route path="/bill-categories" element={<BillCategories />} />
                  <Route path="/payments-out" element={<PaymentsOut />} />
                  <Route path="/expense-categories" element={<ExpenseCategories />} />
                  <Route path="/expenses" element={<Expenses />} />
                  <Route path="/petty-cash" element={<PettyCash />} />
                  <Route path="/system-records" element={<SystemRecords />} />
                  <Route path="/system-record-expenses" element={<SystemRecordExpenses />} />
                  <Route path="/wifi-routers" element={<WifiRouters />} />
                  <Route path="/wifi-plans" element={<WifiPlans />} />
                  <Route path="/wifi-voucher-purchases" element={<WifiVoucherPurchases />} />
                  <Route path="/wifi-earnings" element={<WifiEarnings />} />
                  <Route path="/my-verifications" element={<MyVerifications />} />
                  <Route path="/users" element={<Users />} />
                  <Route path="/users/:userId/profile" element={<UserProfile />} />
                  <Route path="/leave" element={<Leave />} />
                  <Route path="/payroll" element={<Payroll />} />
                  <Route path="/sessions" element={<Sessions />} />
                  <Route path="/roles" element={<Roles />} />
                  <Route path="/sms" element={<Sms />} />
                  <Route path="/subscription" element={<Subscription />} />
                  <Route path="/collection" element={<Collection />} />
                  <Route path="/followups" element={<Followups />} />
                  <Route path="/reseller-applications" element={<ResellerApplications />} />
                  <Route path="/wallet" element={<Wallet />} />
                  <Route path="/my-collections" element={<MyCollections />} />
                  <Route path="/satisfaction-calls" element={<SatisfactionCalls />} />
                  <Route path="/appointments" element={<Appointments />} />
                  <Route path="/automation" element={<Automation />} />
                  <Route path="/broadcast" element={<Broadcast />} />
                  <Route path="/broadcast/:id/delivery-report" element={<BroadcastDeliveryReport />} />
                  <Route path="/whatsapp-contacts" element={<WhatsappContacts />} />
                  <Route path="/hosting" element={<HostingAccounts />} />
                  <Route path="/hosting/discover" element={<DiscoverHostingAccounts />} />
                  <Route path="/hosting/subdomains" element={<Subdomains />} />
                  <Route path="/hosting/bandwidth" element={<BandwidthUsage />} />
                  <Route path="/hosting/disk-usage" element={<DiskUsage />} />
                  <Route path="/hosting/backup-status" element={<BackupStatus />} />
                  <Route path="/hosting/email-accounts" element={<EmailAccounts />} />
                  <Route path="/hosting/mysql-databases" element={<MysqlDatabases />} />
                  <Route path="/hosting/packages" element={<HostingPackages />} />
                  <Route path="/hosting/health" element={<ServerHealth />} />
                  <Route path="/hosting/dns-zone" element={<DnsZone />} />
                  <Route path="/linode" element={<Linode />} />
                  <Route path="/hosting/cron-jobs" element={<CronJobs />} />
                  <Route path="/hosting/php-versions" element={<PhpVersions />} />
                  <Route path="/hosting/ftp-accounts" element={<FtpAccounts />} />
                  <Route path="/domains/ssl-expiry" element={<SslExpiry />} />
                  <Route path="/hosting/services" element={<ServiceManagement />} />
                  <Route path="/domains" element={<Domains />} />
                  <Route path="/domains/activity" element={<DomainActivity />} />
                  <Route path="/domains/:id" element={<DomainDetails />} />
                  <Route path="/tickets" element={<Tickets />} />
                  <Route path="/canned-replies" element={<CannedReplies />} />
                  <Route path="/announcements" element={<Announcements />} />
                  <Route path="/knowledgebase" element={<Knowledgebase />} />
                  <Route path="/field-marketing" element={<FieldMarketing />} />
                  <Route path="/social-media" element={<SocialMedia />} />
                  <Route path="/served-customers" element={<ServedCustomers />} />
                  <Route path="/staff-reports" element={<StaffReports />} />
                  <Route path="/attendance" element={<Attendance />} />
                  <Route path="/work-locations" element={<WorkLocations />} />
                  <Route path="/staff-targets" element={<StaffTargets />} />
                  <Route path="/reports/revenue" element={<RevenueSummary />} />
                  <Route path="/reports/aging" element={<OutstandingAging />} />
                  <Route path="/reports/client-statement" element={<ClientStatementReport />} />
                  <Route path="/reports/payment-collection" element={<PaymentCollectionReport />} />
                  <Route path="/reports/expenses" element={<ExpenseReportPage />} />
                  <Route path="/reports/system-records" element={<SystemRecordsReportPage />} />
                  <Route path="/reports/bank-balance-statement" element={<BankBalanceStatementReportPage />} />
                  <Route path="/reports/system-verifications" element={<SystemVerificationsReportPage />} />
                  <Route path="/reports/profit-loss" element={<ProfitLossReport />} />
                  <Route path="/reports/statutory" element={<StatutoryComplianceReport />} />
                  <Route path="/reports/subscriptions" element={<SubscriptionReportPage />} />
                  <Route path="/reports/collection-effectiveness" element={<CollectionEffectivenessReport />} />
                  <Route path="/reports/satisfaction-calls" element={<SatisfactionReportPage />} />
                  <Route path="/reports/communication-log" element={<CommunicationLogReport />} />
                  <Route path="/settings" element={<Settings />} />
                </Route>

                {/* Client Portal routes */}
                <Route
                  element={
                    <ProtectedRoute requiredUserType="client">
                      <PortalShell />
                    </ProtectedRoute>
                  }
                >
                  <Route path="/portal/dashboard" element={<PortalDashboard />} />
                  <Route path="/portal/invoices" element={<PortalDocuments type="invoice" />} />
                  <Route path="/portal/invoices/:id" element={<PortalInvoiceView />} />
                  <Route path="/portal/quotations" element={<PortalDocuments type="quotation" />} />
                  <Route path="/portal/credit-notes" element={<PortalDocuments type="credit_note" />} />
                  <Route path="/portal/payments" element={<PortalPayments />} />
                  <Route path="/portal/wallet" element={<PortalWallet />} />
                  <Route path="/portal/reseller" element={<PortalReseller />} />
                  <Route path="/portal/statement" element={<PortalStatement />} />
                  <Route path="/portal/products-services" element={<PortalProductServices />} />
                  <Route path="/portal/subscriptions" element={<PortalSubscriptions />} />
                  <Route path="/portal/wifi" element={<PortalWifi />} />
                  <Route path="/portal/hosting" element={<PortalHosting />} />
                  <Route path="/portal/servers" element={<PortalServers />} />
                  <Route path="/portal/servers/:id" element={<PortalLinodeServerPage />} />
                  <Route path="/portal/domains" element={<PortalDomains />} />
                  <Route path="/portal/tickets" element={<PortalTickets />} />
                  <Route path="/portal/tickets/new" element={<PortalTicketNew />} />
                  <Route path="/portal/tickets/:id" element={<PortalTicketView />} />
                  <Route path="/portal/hosting/:id" element={<PortalServiceDetails />} />
                  <Route path="/portal/domains/:id" element={<PortalDomainDetails />} />
                  <Route path="/portal/announcements" element={<PortalAnnouncements />} />
                  <Route path="/portal/knowledgebase" element={<PortalKnowledgebase />} />
                  <Route path="/portal/profile" element={<PortalProfile />} />
                  <Route path="/portal/users" element={<PortalUsers />} />
                </Route>

                {/*
                  Storefront. Entered from moinfo.co.tz as /order/<category>?plan=<slug>,
                  so OrderRoute (not ProtectedRoute) guards it — it preserves the
                  chosen plan through login via ?next=.
                */}
                <Route
                  element={
                    <OrderRoute>
                      <PortalShell />
                    </OrderRoute>
                  }
                >
                  <Route path="/order" element={<OrderIndex />} />
                  <Route path="/order/domain" element={<OrderDomain />} />
                  <Route path="/order/:category" element={<OrderCategory />} />
                </Route>

                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
              </Suspense>
            </AuthProvider>
          </BrowserRouter>
        </QueryClientProvider>
      </ModalsProvider>
      </LanguageProvider>
    </MantineProvider>
  );
}
