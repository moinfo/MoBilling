import api from './axios';

export interface Server {
  id: string;
  name: string;
  hostname: string;
  port: number;
  username: string;
  nameservers: string[] | null;
  type: string;
  is_active: boolean;
  verify_ssl: boolean;
  hosting_accounts_count?: number;
  created_at: string;
}

export interface ServerFormData {
  name: string;
  hostname: string;
  port: number;
  username: string;
  api_token?: string; // omit on edit to keep the stored token
  is_active: boolean;
  verify_ssl: boolean;
}

export interface HostingAccount {
  id: string;
  domain: string;
  cpanel_username: string;
  package: string | null;
  status: 'pending' | 'active' | 'suspended' | 'terminated' | 'failed';
  last_synced_at: string | null;
  meta: { disk_used?: string; disk_limit?: string; plan?: string; ip?: string; adopted_from_whmcs?: boolean } | null;
  server: { id: string; name: string; hostname: string } | null;
  subscription: { id: string; client: { id: string; name: string } | null } | null;
  created_at: string;
}

export interface ProvisioningLog {
  id: string;
  action: string;
  status: 'success' | 'failed';
  error: string | null;
  created_at: string;
}

export const HOSTING_STATUS_COLORS: Record<HostingAccount['status'], string> = {
  pending: 'blue',
  active: 'green',
  suspended: 'orange',
  terminated: 'gray',
  failed: 'red',
};

// Servers (Settings)
export const getServers = () => api.get<{ data: Server[] }>('/servers');
export const createServer = (data: ServerFormData) => api.post<{ data: Server }>('/servers', data);
export const updateServer = (id: string, data: Partial<ServerFormData>) => api.put<{ data: Server }>(`/servers/${id}`, data);
export const deleteServer = (id: string) => api.delete(`/servers/${id}`);
export const testServer = (id: string) => api.post<{ ok: boolean; packages: string[] }>(`/servers/${id}/test`);
export const getServerPackages = (id: string) => api.get<{ data: string[] }>(`/servers/${id}/packages`);

// Hosting accounts
export const getHostingAccounts = (params?: Record<string, string>) =>
  api.get('/hosting-accounts', { params });
export const getHostingLogs = (id: string) =>
  api.get<{ data: ProvisioningLog[] }>(`/hosting-accounts/${id}/logs`);
export const provisionSubscription = (subscriptionId: string) =>
  api.post(`/client-subscriptions/${subscriptionId}/provision`);
export const suspendHosting = (id: string) => api.post(`/hosting-accounts/${id}/suspend`);
export const unsuspendHosting = (id: string) => api.post(`/hosting-accounts/${id}/unsuspend`);
export const terminateHosting = (id: string) => api.post(`/hosting-accounts/${id}/terminate`);
export const changeHostingPackage = (id: string, pkg: string) =>
  api.post(`/hosting-accounts/${id}/change-package`, { package: pkg });
export const getHostingSso = (id: string) => api.post<{ url: string }>(`/hosting-accounts/${id}/sso`);

// ── Admin service management (Client Profile → Products/Services) ──────────────

export interface ServiceListItem {
  id: string;
  product_name: string;
  domain: string | null;
  status: string;
  has_account: boolean;
}

export interface ServiceMetric {
  metric: string;
  enabled: boolean;
  usage: string | number | null;
  last_update: string | null;
}

export interface ServiceDetail {
  id: string;
  client: { id: string; name: string };
  order_document_id: string | null;
  product_service_id: string;
  server_id: string | null;
  domain: string | null;
  dedicated_ip: string | null;
  username: string | null;
  package: string | null;
  status: string;
  start_date: string | null;
  quantity: number;
  first_payment_amount: number | null;
  recurring_amount: number | null;
  next_due_date: string | null;
  termination_date: string | null;
  billing_cycle: string | null;
  payment_method: string | null;
  promo_code: string | null;
  hosting_account: {
    id: string; status: string; server_id: string | null; server_host: string | null;
    last_synced_at: string | null; not_on_whm: boolean;
  } | null;
  ssl: { valid: boolean | null; issuer: string | null; expires_at: string | null };
  metrics: ServiceMetric[];
  options: {
    servers: { id: string; label: string; hostname: string }[];
    products: { id: string; name: string; price: string; billing_cycle: string; cpanel_package: string | null }[];
    statuses: string[];
    billing_cycles: string[];
    payment_methods: string[];
  };
}

export const getClientServices = (clientId: string) =>
  api.get<{ data: ServiceListItem[] }>('/hosting-services', { params: { client_id: clientId } });

export const getServiceDetail = (subscriptionId: string) =>
  api.get<{ data: ServiceDetail }>(`/hosting-services/${subscriptionId}`);

export const updateService = (subscriptionId: string, data: Record<string, unknown>) =>
  api.put<{ data: ServiceDetail }>(`/hosting-services/${subscriptionId}`, data);

export const changeHostingPassword = (accountId: string, password: string) =>
  api.post<{ message: string }>(`/hosting-accounts/${accountId}/password`, { password });

export const refreshHostingUsage = (accountId: string) =>
  api.post<{ data: ServiceMetric[] }>(`/hosting-accounts/${accountId}/refresh-usage`);

export interface UpgradePlan {
  id: string; name: string; price: number; billing_cycle: string;
  is_current: boolean; direction: 'upgrade' | 'downgrade' | 'same';
  prorated_due: number; prorated_credit: number;
}
export interface UpgradeOptions {
  current_plan: { id: string; name: string; price: number };
  billing_cycle: string; next_due_date: string | null; quantity: number;
  plans: UpgradePlan[];
}
export const getUpgradeOptions = (subscriptionId: string) =>
  api.get<{ data: UpgradeOptions }>(`/hosting-services/${subscriptionId}/upgrade-options`);
export const applyUpgrade = (subscriptionId: string, productServiceId: string, mode: 'invoice' | 'immediate') =>
  api.post<{ applied: boolean; document?: { id: string; number: string; total: number }; message: string }>(
    `/hosting-services/${subscriptionId}/upgrade`, { product_service_id: productServiceId, mode });

export const resendWelcomeEmail = (subscriptionId: string) =>
  api.post<{ message: string }>(`/hosting-services/${subscriptionId}/resend-welcome`);
export const sendClientMessage = (subscriptionId: string, subject: string, body: string) =>
  api.post<{ message: string }>(`/hosting-services/${subscriptionId}/send-message`, { subject, body });
export const resetPasswordAndWelcome = (accountId: string) =>
  api.post<{ password: string; message: string }>(`/hosting-accounts/${accountId}/reset-welcome`);
