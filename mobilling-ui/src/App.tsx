import { MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { ModalsProvider } from '@mantine/modals';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext';
import ProtectedRoute from './components/Layout/ProtectedRoute';
import AppLayout from './components/Layout/AppShell';
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
