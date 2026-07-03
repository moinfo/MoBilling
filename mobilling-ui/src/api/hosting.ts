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
