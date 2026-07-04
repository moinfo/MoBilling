import api from './axios';

export interface Client {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  address: string | null;
  tax_id: string | null;
  active_subscriptions_count?: number;
  subscription_total?: number;
  created_at: string;
}

export interface ClientFormData {
  name: string;
  email: string;
  phone: string;
  address: string;
  tax_id: string;
}

export const getClients = (params?: {
  search?: string;
  page?: number;
  per_page?: number;
  sort?: 'name' | 'subscriptions' | 'amount' | 'newest';
  has_subscriptions?: 1 | 0;
}) => api.get('/clients', { params });

export interface ClientStats {
  total_clients: number;
  with_subscriptions: number;
  without_subscriptions: number;
  active_subscriptions: number;
  new_this_month: number;
  subscription_value?: number;
  credit_balance_total?: number;
}

export const getClientStats = () =>
  api.get<{ data: ClientStats }>('/clients/stats');

export const getClient = (id: string) =>
  api.get<{ data: Client }>(`/clients/${id}`);

export const createClient = (data: ClientFormData) =>
  api.post('/clients', data);

export const updateClient = (id: string, data: ClientFormData) =>
  api.put(`/clients/${id}`, data);

export const deleteClient = (id: string) =>
  api.delete(`/clients/${id}`);

export interface ClientCommunicationLog {
  id: string;
  channel: 'email' | 'sms';
  type: string;
  recipient: string;
  subject: string | null;
  message: string | null;
  status: 'sent' | 'failed';
  error: string | null;
  created_at: string;
}

export interface ClientProfile {
  client: Client;
  summary: {
    total_invoiced: number;
    total_paid: number;
    balance: number;
    active_subscriptions: number;
    total_subscription_value: number;
  };
  subscriptions: {
    id: string;
    product_service_name: string;
    label: string | null;
    billing_cycle: string;
    quantity: number;
    price: string;
    start_date: string;
    status: string;
    next_bill: string | null;
  }[];
  invoices: {
    id: string;
    document_number: string;
    description?: string | null;
    date: string;
    due_date: string | null;
    subtotal: number;
    late_fee: number;
    total: string;
    paid_amount: number;
    balance_due: number;
    status: string;
  }[];
  payments: {
    id: string;
    amount: string;
    payment_date: string;
    payment_method: string;
    reference: string | null;
    document_number: string | null;
  }[];
  communication_logs: ClientCommunicationLog[];
}

export const getClientProfile = (id: string) =>
  api.get<{ data: ClientProfile }>(`/clients/${id}/profile`);

// Client Portal Users (tenant admin)
export interface ClientPortalUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'admin' | 'viewer';
  is_active: boolean;
  last_login_at: string | null;
}

export const getClientPortalUsers = (clientId: string) =>
  api.get<{ data: ClientPortalUser[] }>(`/clients/${clientId}/portal-users`);

export const createClientPortalUser = (clientId: string, data: { name: string; email: string; password: string; phone?: string; role: string }) =>
  api.post(`/clients/${clientId}/portal-users`, data);

export const updateClientPortalUser = (clientId: string, userId: string, data: Partial<ClientPortalUser & { password?: string }>) =>
  api.put(`/clients/${clientId}/portal-users/${userId}`, data);

export const deleteClientPortalUser = (clientId: string, userId: string) =>
  api.delete(`/clients/${clientId}/portal-users/${userId}`);

export const portalLoginAsClient = (clientId: string) =>
  api.post<{ user: any; token: string; user_type: string; permissions: string[]; message: string }>(`/clients/${clientId}/portal-login`);

export const changePortalPassword = (clientId: string, password: string, portalUserId?: string) =>
  api.post<{ message: string }>(`/clients/${clientId}/portal-password`, { password, portal_user_id: portalUserId });

// ── Client credit (staff) ─────────────────────────────────────────────────────

export const getClientCredit = (clientId: string) =>
  api.get<{ data: { balance: number; ledger: { id: string; type: string; amount: number; balance_after: number; notes: string | null; created_at: string }[] } }>(`/clients/${clientId}/credit`);

export const adjustClientCredit = (clientId: string, amount: number, notes: string) =>
  api.post(`/clients/${clientId}/credit/adjust`, { amount, notes });

export const updateClientNotes = (clientId: string, notes: string) =>
  api.put(`/clients/${clientId}/notes`, { notes });
