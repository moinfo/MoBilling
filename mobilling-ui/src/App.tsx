import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { ModalsProvider } from '@mantine/modals';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import ProtectedRoute from './components/Layout/ProtectedRoute';
import AppLayout from './components/Layout/AppShell';
import AdminShell from './components/Layout/AdminShell';
import Login from './pages/Login';
import Register from './pages/Register';
import ForgotPassword from './pages/ForgotPassword';
import ResetPassword from './pages/ResetPassword';
import Dashboard from './pages/Dashboard';
import Landing from './pages/Landing';
import Clients from './pages/Clients';
import ClientProfile from './pages/ClientProfile';
import ProductServices from './pages/ProductServices';
import Quotations from './pages/Quotations';
import Proformas from './pages/Proformas';
import Invoices from './pages/Invoices';
import BillCategories from './pages/BillCategories';
import Bills from './pages/Bills';
import PaymentsIn from './pages/PaymentsIn';
import NextBills from './pages/NextBills';
import ClientSubscriptions from './pages/ClientSubscriptions';
import PaymentsOut from './pages/PaymentsOut';
import Settings from './pages/Settings';
import Users from './pages/Users';
import Roles from './pages/Roles';
import AdminDashboard from './pages/admin/Dashboard';
import Tenants from './pages/admin/Tenants';
import TenantUsers from './pages/admin/TenantUsers';
import EmailSettings from './pages/admin/EmailSettings';
import SmsSettingsAdmin from './pages/admin/SmsSettings';
import SmsPackagesAdmin from './pages/admin/SmsPackages';
import SmsPurchasesAdmin from './pages/admin/SmsPurchases';
import SubscriptionPlansAdmin from './pages/admin/SubscriptionPlans';
import TenantProfile from './pages/admin/TenantProfile';
import CurrenciesAdmin from './pages/admin/Currencies';
import PlatformSettingsAdmin from './pages/admin/PlatformSettings';
import TemplatesAdmin from './pages/admin/Templates';
import ExpenseCategories from './pages/ExpenseCategories';
import Expenses from './pages/Expenses';
import Statutories from './pages/Statutories';
import StatutorySchedule from './pages/StatutorySchedule';
import Sms from './pages/Sms';
import Subscription from './pages/Subscription';
import Automation from './pages/Automation';
import Broadcast from './pages/Broadcast';
import Collection from './pages/Collection';
import Followups from './pages/Followups';
import RevenueSummary from './pages/reports/RevenueSummary';
import OutstandingAging from './pages/reports/OutstandingAging';
import ClientStatementReport from './pages/reports/ClientStatementReport';
import PaymentCollectionReport from './pages/reports/PaymentCollectionReport';
import ExpenseReportPage from './pages/reports/ExpenseReportPage';
import ProfitLossReport from './pages/reports/ProfitLossReport';
import StatutoryComplianceReport from './pages/reports/StatutoryComplianceReport';
import SubscriptionReportPage from './pages/reports/SubscriptionReportPage';
import CollectionEffectivenessReport from './pages/reports/CollectionEffectivenessReport';
import CommunicationLogReport from './pages/reports/CommunicationLogReport';
import SubscriptionExpired from './pages/SubscriptionExpired';
import PesapalCallback from './pages/PesapalCallback';

import '@mantine/core/styles.css';
import '@mantine/dates/styles.css';
import '@mantine/notifications/styles.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: false },
  },
});

export default function App() {
  return (
    <MantineProvider defaultColorScheme="auto">
      <Notifications position="top-right" />
      <ModalsProvider>
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            <AuthProvider>
              <Routes>
                <Route path="/" element={<Landing />} />
                <Route path="/login" element={<Login />} />
                <Route path="/register" element={<Register />} />
                <Route path="/forgot-password" element={<ForgotPassword />} />
                <Route path="/reset-password" element={<ResetPassword />} />
                <Route path="/pesapal/callback" element={<PesapalCallback />} />

                {/* Subscription expired (standalone, no sidebar) */}
                <Route
                  path="/subscription/expired"
                  element={
                    <ProtectedRoute allowExpired>
                      <SubscriptionExpired />
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
                  <Route path="/admin/tenants/:tenantId" element={<TenantProfile />} />
                  <Route path="/admin/tenants/:tenantId/users" element={<TenantUsers />} />
                  <Route path="/admin/email-settings" element={<EmailSettings />} />
                  <Route path="/admin/email-templates" element={<TemplatesAdmin />} />
                  <Route path="/admin/sms-settings" element={<SmsSettingsAdmin />} />
                  <Route path="/admin/sms-packages" element={<SmsPackagesAdmin />} />
                  <Route path="/admin/sms-purchases" element={<SmsPurchasesAdmin />} />
                  <Route path="/admin/subscription-plans" element={<SubscriptionPlansAdmin />} />
                  <Route path="/admin/currencies" element={<CurrenciesAdmin />} />
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
                  <Route path="/product-services" element={<ProductServices />} />
                  <Route path="/quotations" element={<Quotations />} />
                  <Route path="/proformas" element={<Proformas />} />
                  <Route path="/invoices" element={<Invoices />} />
                  <Route path="/payments-in" element={<PaymentsIn />} />
                  <Route path="/client-subscriptions" element={<ClientSubscriptions />} />
                  <Route path="/next-bills" element={<NextBills />} />
                  <Route path="/statutories" element={<Statutories />} />
                  <Route path="/statutory-schedule" element={<StatutorySchedule />} />
                  <Route path="/bills" element={<Bills />} />
                  <Route path="/bill-categories" element={<BillCategories />} />
                  <Route path="/payments-out" element={<PaymentsOut />} />
                  <Route path="/expense-categories" element={<ExpenseCategories />} />
                  <Route path="/expenses" element={<Expenses />} />
                  <Route path="/users" element={<Users />} />
                  <Route path="/roles" element={<Roles />} />
                  <Route path="/sms" element={<Sms />} />
                  <Route path="/subscription" element={<Subscription />} />
                  <Route path="/collection" element={<Collection />} />
                  <Route path="/followups" element={<Followups />} />
                  <Route path="/automation" element={<Automation />} />
                  <Route path="/broadcast" element={<Broadcast />} />
                  <Route path="/reports/revenue" element={<RevenueSummary />} />
                  <Route path="/reports/aging" element={<OutstandingAging />} />
                  <Route path="/reports/client-statement" element={<ClientStatementReport />} />
                  <Route path="/reports/payment-collection" element={<PaymentCollectionReport />} />
                  <Route path="/reports/expenses" element={<ExpenseReportPage />} />
                  <Route path="/reports/profit-loss" element={<ProfitLossReport />} />
                  <Route path="/reports/statutory" element={<StatutoryComplianceReport />} />
                  <Route path="/reports/subscriptions" element={<SubscriptionReportPage />} />
                  <Route path="/reports/collection-effectiveness" element={<CollectionEffectivenessReport />} />
                  <Route path="/reports/communication-log" element={<CommunicationLogReport />} />
                  <Route path="/settings" element={<Settings />} />
                </Route>
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </AuthProvider>
          </BrowserRouter>
        </QueryClientProvider>
      </ModalsProvider>
    </MantineProvider>
  );
}
