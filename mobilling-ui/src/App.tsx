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
import Dashboard from './pages/Dashboard';
import Landing from './pages/Landing';
import Clients from './pages/Clients';
import ProductServices from './pages/ProductServices';
import Quotations from './pages/Quotations';
import Proformas from './pages/Proformas';
import Invoices from './pages/Invoices';
import Bills from './pages/Bills';
import PaymentsOut from './pages/PaymentsOut';
import Settings from './pages/Settings';
import Users from './pages/Users';
import AdminDashboard from './pages/admin/Dashboard';
import Tenants from './pages/admin/Tenants';
import TenantUsers from './pages/admin/TenantUsers';
import EmailSettings from './pages/admin/EmailSettings';
import SmsSettingsAdmin from './pages/admin/SmsSettings';
import SmsPackagesAdmin from './pages/admin/SmsPackages';
import SmsPurchasesAdmin from './pages/admin/SmsPurchases';
import Sms from './pages/Sms';

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
                  <Route path="/admin/tenants/:tenantId/users" element={<TenantUsers />} />
                  <Route path="/admin/email-settings" element={<EmailSettings />} />
                  <Route path="/admin/sms-settings" element={<SmsSettingsAdmin />} />
                  <Route path="/admin/sms-packages" element={<SmsPackagesAdmin />} />
                  <Route path="/admin/sms-purchases" element={<SmsPurchasesAdmin />} />
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
                  <Route path="/product-services" element={<ProductServices />} />
                  <Route path="/quotations" element={<Quotations />} />
                  <Route path="/proformas" element={<Proformas />} />
                  <Route path="/invoices" element={<Invoices />} />
                  <Route path="/bills" element={<Bills />} />
                  <Route path="/payments-out" element={<PaymentsOut />} />
                  <Route path="/users" element={<Users />} />
                  <Route path="/sms" element={<Sms />} />
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
