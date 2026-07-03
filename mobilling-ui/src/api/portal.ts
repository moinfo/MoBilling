import api from './axios';

// Dashboard
export interface PortalDashboard {
  total_invoiced: number;
  total_paid: number;
  total_balance: number;
  overdue_count: number;
  recent_invoices: PortalInvoice[];
  recent_payments: PortalPayment[];
  upcoming_subscriptions?: any[];
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
  subtotal?: number;
  discount_amount?: string;
  tax_amount?: string;
  total: number;
  status: string;
  notes: string | null;
  items: {
    id: string;
    description: string;
    quantity: number;
    price: number;
    total: number;
    discount_type?: string;
    discount_value?: number;
    service_from?: string;
    service_to?: string;
  }[];
  payments?: {
    id: string;
    amount: string;
    payment_date: string;
    payment_method: string;
    reference: string | null;
  }[];
  paid_amount?: number;
  balance_due?: number;
}

export const getPortalDocuments = (params: { type?: string; status?: string; search?: string; page?: number; per_page?: number }) =>
  api.get('/portal/documents', { params });

export const getPortalDocument = (id: string) =>
  api.get<{ data: PortalDocument }>(`/portal/documents/${id}`);

export const resendPortalDocument = (id: string) =>
  api.post<{ message: string }>(`/portal/documents/${id}/resend`);

// Payments
export const getPortalPayments = (params?: { search?: string; page?: number }) =>
  api.get('/portal/payments', { params });

export const downloadPortalReceipt = (paymentId: string) =>
  api.get(`/portal/payments/${paymentId}/receipt`, { responseType: 'blob' });

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

// ── Hosting ───────────────────────────────────────────────────────────────────

export interface PortalHostingAccount {
  id: string;
  domain: string;
  cpanel_username: string;
  package: string | null;
  status: 'pending' | 'active' | 'suspended' | 'failed';
  disk_used: string | null;
  disk_limit: string | null;
  server_hostname: string | null;
  expires_at: string | null;
}

export const getPortalHosting = () =>
  api.get<{ data: PortalHostingAccount[] }>('/portal/hosting');

export const portalHostingSso = (id: string, opts?: { service?: 'cpanel' | 'webmail'; goto?: string }) =>
  api.post<{ url: string }>(`/portal/hosting/${id}/sso`, opts ?? {});

export interface PortalHostingDetail {
  id: string;
  domain: string;
  cpanel_username: string;
  status: string;
  package: string | null;
  product_name: string | null;
  product_group: string | null;
  price: number;
  billing_cycle: string | null;
  registered_at: string | null;
  next_due: string | null;
  disk_used: string | null;
  disk_limit: string | null;
  last_synced_at: string | null;
  shortcuts: string[];
}

export const getPortalHostingDetail = (id: string) =>
  api.get<{ data: PortalHostingDetail }>(`/portal/hosting/${id}`);

export const refreshPortalHostingUsage = (id: string) =>
  api.post<{ data: { disk_used: string | null; disk_limit: string | null; last_synced_at: string } }>(`/portal/hosting/${id}/refresh-usage`);

export const changePortalHostingPassword = (id: string, password: string, password_confirmation: string) =>
  api.post(`/portal/hosting/${id}/change-password`, { password, password_confirmation });

export const requestPortalHostingCancellation = (id: string, reason: string, when: 'immediate' | 'end_of_period') =>
  api.post(`/portal/hosting/${id}/request-cancellation`, { reason, when });

// ── Domains ───────────────────────────────────────────────────────────────────

export interface PortalDomain {
  id: string;
  name: string;
  status: 'pending' | 'active' | 'expired' | 'failed';
  registered_at: string | null;
  expires_at: string | null;
  auto_renew: boolean;
  expiring_soon: boolean;
  unmanaged: boolean;
  ssl_valid: boolean | null;
  ssl_expires_at: string | null;
}

export interface PortalDomainStats {
  active: number;
  expired: number;
  expiring_soon: number;
  pending: number;
}

export const getPortalDomains = () =>
  api.get<{ data: PortalDomain[]; stats: PortalDomainStats }>('/portal/domains');

export const portalRenewDomain = (id: string, years: number) =>
  api.post(`/portal/domains/${id}/renew`, { years });

export const portalCheckDomain = (name: string) =>
  api.get('/portal/domains/check', { params: { name } });

export const portalOrderDomain = (data: { name: string; years: number; action: 'register' | 'transfer'; auth_info?: string }) =>
  api.post('/portal/domains/order', data);

// ── Support Tickets ───────────────────────────────────────────────────────────

export interface PortalTicket {
  id: string;
  ticket_number: string;
  subject: string;
  status: 'open' | 'answered' | 'customer_reply' | 'closed';
  priority: string;
  replies_count: number | null;
  last_reply_at: string | null;
  created_at: string;
  replies?: { id: string; author_type: 'staff' | 'client'; author_name: string; message: string; created_at: string }[];
}

export const getPortalTickets = () => api.get<{ data: PortalTicket[] }>('/portal/tickets');
export const openPortalTicket = (data: { subject: string; message: string; priority?: string }) =>
  api.post('/portal/tickets', data);
export const getPortalTicket = (id: string) => api.get<{ data: PortalTicket }>(`/portal/tickets/${id}`);
export const replyPortalTicket = (id: string, message: string) => api.post<{ data: PortalTicket }>(`/portal/tickets/${id}/reply`, { message });
export const closePortalTicket = (id: string) => api.post(`/portal/tickets/${id}/close`);

// ── Order New Services (shopping cart) ────────────────────────────────────────

export interface CatalogProduct {
  id: string;
  name: string;
  features: string[];
  price: number;
  billing_cycle: string | null;
  needs_domain: boolean;
}

export interface CatalogGroup {
  name: string;
  order: number;
  products: CatalogProduct[];
}

export const getPortalCatalog = () =>
  api.get<{ data: CatalogGroup[] }>('/portal/catalog');

export const placePortalOrder = (data: {
  product_service_id: string; label?: string;
  domain_mode?: 'register' | 'transfer' | 'existing'; auth_info?: string;
  years?: number; addons?: string[];
}) => api.post('/portal/orders', data);

export interface PortalTldRow {
  tld: string; register_price: number; transfer_price: number;
  years_min: number; years_max: number;
}

export const getPortalDomainTlds = () =>
  api.get<{ data: PortalTldRow[] }>('/portal/domain-tlds');

export interface DomainAddonRow {
  id: string; name: string; description: string | null; price: number; is_free: boolean;
}

export const downloadPortalDocumentPdf = (id: string) =>
  api.get(`/portal/documents/${id}/pdf`, { responseType: 'blob' });

export const getPortalDomainAddons = () =>
  api.get<{ data: DomainAddonRow[] }>('/portal/domain-addons');
