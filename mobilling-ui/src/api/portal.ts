import api from './axios';

// Dashboard
export interface PortalDashboard {
  total_invoiced: number;
  total_paid: number;
  total_balance: number;
  overdue_count: number;
  recent_invoices: PortalInvoice[];
  recent_payments: PortalPayment[];
}

export interface PortalInvoice {
  id: string;
  document_number: string;
  date: string;
  due_date: string | null;
  total: number;
  paid: number;
  balance: number;
  status: string;
}

export interface PortalPayment {
  id: string;
  payment_date: string;
  amount: number;
  payment_method: string;
  reference: string | null;
  document_number: string | null;
}

export const getPortalDashboard = () =>
  api.get<PortalDashboard>('/portal/dashboard');

// Products & Services
export interface PortalProductService {
  id: string;
  type: string;
  name: string;
  code: string | null;
  description: string | null;
  price: number;
  tax_percent: number;
  unit: string | null;
  category: string | null;
  billing_cycle: string | null;
}

export const getPortalProductServices = (params?: { type?: string; search?: string }) =>
  api.get<{ data: PortalProductService[] }>('/portal/products-services', { params });

// Documents
export interface PortalDocument {
  id: string;
  document_number: string;
  type: string;
  date: string;
  due_date: string | null;
  total: number;
  status: string;
  notes: string | null;
  items: {
    id: string;
    description: string;
    quantity: number;
    unit_price: number;
    amount: number;
  }[];
  paid_amount?: number;
  balance_due?: number;
}

export const getPortalDocuments = (params: { type?: string; status?: string; search?: string; page?: number }) =>
  api.get('/portal/documents', { params });

export const getPortalDocument = (id: string) =>
  api.get<{ data: PortalDocument }>(`/portal/documents/${id}`);

export const resendPortalDocument = (id: string) =>
  api.post<{ message: string }>(`/portal/documents/${id}/resend`);

// Payments
export const getPortalPayments = (params?: { search?: string; page?: number }) =>
  api.get('/portal/payments', { params });

// Statement
export interface StatementEntry {
  date: string;
  type: 'invoice' | 'payment';
  reference: string;
  description: string;
  debit: number;
  credit: number;
  balance: number;
}

export interface StatementResponse {
  entries: StatementEntry[];
  total_debits: number;
  total_credits: number;
  closing_balance: number;
}

export const getPortalStatement = (params?: { start_date?: string; end_date?: string }) =>
  api.get<StatementResponse>('/portal/statement', { params });

// Subscriptions
export interface PortalSubscription {
  id: string;
  label: string;
  quantity: number;
  start_date: string;
  status: string;
  product_service?: { id: string; name: string; type: string; price: number };
}

export const getPortalSubscriptions = () =>
  api.get<{ data: PortalSubscription[] }>('/portal/subscriptions');

export const generateSubscriptionInvoice = (subscriptionId: string) =>
  api.post<{ message: string; data: { document_id: string; document_number: string } }>(`/portal/subscriptions/${subscriptionId}/generate-invoice`);

// Profile
export const getPortalProfile = () =>
  api.get('/portal/profile');

export const updatePortalProfile = (data: { name?: string; phone?: string }) =>
  api.put('/portal/profile', data);

export const changePortalPassword = (data: { current_password: string; password: string; password_confirmation: string }) =>
  api.post('/portal/profile/change-password', data);

// Portal Users
export interface PortalUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'admin' | 'viewer';
  is_active: boolean;
  last_login_at: string | null;
}

export const getPortalUsers = () =>
  api.get<{ data: PortalUser[] }>('/portal/users');

export const createPortalUser = (data: { name: string; email: string; password: string; phone?: string; role: string }) =>
  api.post('/portal/users', data);

export const updatePortalUser = (id: string, data: Partial<PortalUser>) =>
  api.put(`/portal/users/${id}`, data);

export const deletePortalUser = (id: string) =>
  api.delete(`/portal/users/${id}`);
