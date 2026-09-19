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

export interface ServerPackageDetails {
  name: string;
  quota_mb: number | null;
  bandwidth_mb: number | null;
  databases: number | null;
  email_accounts: number | null;
  subdomains: number | null;
  ftp_accounts: number | null;
  addon_domains: number | null;
  parked_domains: number | null;
}
export const getServerPackagesDetailed = (id: string) =>
  api.get<{ data: ServerPackageDetails[] }>(`/servers/${id}/packages-detailed`);

export interface PackageLimits {
  quota_mb?: number | null;
  bandwidth_mb?: number | null;
  databases?: number | null;
  email_accounts?: number | null;
  subdomains?: number | null;
  ftp_accounts?: number | null;
  addon_domains?: number | null;
  parked_domains?: number | null;
}
export const createServerPackage = (serverId: string, data: PackageLimits & { name: string }) =>
  api.post<{ data: ServerPackageDetails }>(`/servers/${serverId}/packages`, data);
export const updateServerPackage = (serverId: string, packageName: string, data: PackageLimits) =>
  api.put<{ data: ServerPackageDetails }>(`/servers/${serverId}/packages/${encodeURIComponent(packageName)}`, data);
export const deleteServerPackage = (serverId: string, packageName: string) =>
  api.delete<{ message: string }>(`/servers/${serverId}/packages/${encodeURIComponent(packageName)}`);

export interface ServerHealth {
  hostname: string | null;
  whm_version: string | null;
  load_avg: { one: number | null; five: number | null; fifteen: number | null };
}
export const getServerHealth = (id: string) =>
  api.get<{ data: ServerHealth }>(`/servers/${id}/health`);

// Hosting accounts
export const getHostingAccounts = (params?: Record<string, string>) =>
  api.get('/hosting-accounts', { params });
export const getHostingLogs = (id: string) =>
  api.get<{ data: ProvisioningLog[] }>(`/hosting-accounts/${id}/logs`);

export interface DiscoveredAccount {
  server_id: string;
  server_name: string;
  cpanel_username: string;
  domain: string | null;
  email: string | null;
  plan: string | null;
  disk_used: string | null;
  disk_limit: string | null;
  ip: string | null;
  setup_date: string | null;
  partition: string | null;
  theme: string | null;
  owner: string | null;
  suspended: boolean;
  suspend_reason: string | null;
  hosting_account_id: string | null;
  client_subscription_id: string | null;
  client: { id: string; name: string } | null;
  imported: boolean;
}
export const discoverHostingAccounts = (params?: { server_id?: string; search?: string; imported?: 0 | 1; suspended?: 0 | 1 }) =>
  api.get<{ data: DiscoveredAccount[]; errors: string[] }>('/hosting-accounts/discover', { params });

export interface Subdomain {
  server_id: string;
  server_name: string;
  type: 'sub' | 'addon';
  subdomain: string | null;
  parent_domain: string | null;
  cpanel_username: string;
  docroot: string | null;
  ip: string | null;
  php_version: string | null;
  client: { id: string; name: string } | null;
}
export const getSubdomains = (params?: { server_id?: string; search?: string; type?: 'sub' | 'addon' }) =>
  api.get<{ data: Subdomain[]; errors: string[] }>('/hosting-accounts/subdomains', { params });

export interface BandwidthUsageRow {
  server_id: string;
  server_name: string;
  cpanel_username: string;
  domain: string | null;
  used_bytes: number;
  limit_bytes: number | null;
  percent_used: number | null;
  bandwidth_limited: boolean;
  client: { id: string; name: string } | null;
}
export const getBandwidthUsage = (params?: { server_id?: string; search?: string }) =>
  api.get<{ data: BandwidthUsageRow[]; errors: string[] }>('/hosting-accounts/bandwidth-usage', { params });

export interface DiskUsageRow {
  server_id: string;
  server_name: string;
  cpanel_username: string;
  domain: string | null;
  used_mb: number;
  limit_mb: number | null;
  percent_used: number | null;
  client: { id: string; name: string } | null;
}
export const getDiskUsage = (params?: { server_id?: string; search?: string }) =>
  api.get<{ data: DiskUsageRow[]; errors: string[] }>('/hosting-accounts/disk-usage', { params });

export interface BackupStatusRow {
  server_id: string;
  server_name: string;
  cpanel_username: string;
  domain: string | null;
  backup_enabled: boolean;
  backup_exists: boolean;
  client: { id: string; name: string } | null;
}
export const getBackupStatus = (params?: { server_id?: string; search?: string }) =>
  api.get<{ data: BackupStatusRow[]; errors: string[] }>('/hosting-accounts/backup-status', { params });

export interface EmailAccountRow {
  email: string | null;
  suspended_incoming: boolean;
  suspended_login: boolean;
  used_bytes: number;
  quota_bytes: number | null;
}
export const getEmailAccounts = (params: { server_id: string; cpanel_username: string }) =>
  api.get<{ data: EmailAccountRow[] }>('/hosting-accounts/email-accounts', { params });

export const addEmailAccount = (data: { server_id: string; cpanel_username: string; email: string; domain: string; password: string; quota_mb: number }) =>
  api.post<{ message: string }>('/hosting-accounts/email-accounts', data);

export const changeEmailAccountPassword = (data: { server_id: string; cpanel_username: string; email: string; password: string }) =>
  api.post<{ message: string }>('/hosting-accounts/email-accounts/password', data);

export const toggleEmailAccountSuspension = (data: { server_id: string; cpanel_username: string; email: string; suspend: boolean }) =>
  api.post<{ message: string }>('/hosting-accounts/email-accounts/toggle-suspension', data);

export const deleteEmailAccount = (data: { server_id: string; cpanel_username: string; email: string; domain: string }) =>
  api.post<{ message: string }>('/hosting-accounts/email-accounts/delete', data);

export interface MysqlDatabaseRow {
  database: string | null;
  users: string[];
  disk_usage: number;
}
export const getMysqlDatabases = (params: { server_id: string; cpanel_username: string }) =>
  api.get<{ data: MysqlDatabaseRow[] }>('/hosting-accounts/mysql-databases', { params });

export interface DnsZoneRecord {
  type: string;
  name: string;
  ttl: number;
  data: string[];
}
export const getDnsZone = (params: { server_id: string; domain: string }) =>
  api.get<{ data: DnsZoneRecord[] }>('/hosting-accounts/dns-zone', { params });

export interface AddDnsRecordPayload {
  server_id: string;
  domain: string;
  type: 'A' | 'AAAA' | 'CNAME' | 'TXT' | 'MX';
  name: string;
  ttl: number;
  value?: string;
  priority?: number;
}
export const addDnsRecord = (data: AddDnsRecordPayload) =>
  api.post<{ message: string }>('/hosting-accounts/dns-zone', data);

export interface CronJobRow {
  linekey: number;
  minute: string;
  hour: string;
  day: string;
  month: string;
  weekday: string;
  command: string;
}
export const getCronJobs = (params: { server_id: string; cpanel_username: string }) =>
  api.get<{ data: CronJobRow[] }>('/hosting-accounts/cron-jobs', { params });

export interface CronJobPayload {
  server_id: string;
  cpanel_username: string;
  minute: string;
  hour: string;
  day: string;
  month: string;
  weekday: string;
  command: string;
}
export const addCronJob = (data: CronJobPayload) =>
  api.post<{ message: string }>('/hosting-accounts/cron-jobs', data);

export const updateCronJob = (data: CronJobPayload & { linekey: number }) =>
  api.put<{ message: string }>('/hosting-accounts/cron-jobs', data);

export const deleteCronJob = (data: { server_id: string; cpanel_username: string; linekey: number }) =>
  api.delete<{ message: string }>('/hosting-accounts/cron-jobs', { data });

export interface PhpVhostRow {
  vhost: string | null;
  version: string | null;
  main_domain: boolean;
}
export const getPhpVersions = (params: { server_id: string; cpanel_username: string }) =>
  api.get<{ data: PhpVhostRow[]; installed: string[] }>('/hosting-accounts/php-versions', { params });

export const updatePhpVersion = (data: { server_id: string; cpanel_username: string; vhost: string; version: string }) =>
  api.put<{ message: string }>('/hosting-accounts/php-versions', data);

export interface FtpAccountRow {
  user: string;
  homedir: string;
  type: 'main' | 'sub';
}
export const getFtpAccounts = (params: { server_id: string; cpanel_username: string }) =>
  api.get<{ data: FtpAccountRow[] }>('/hosting-accounts/ftp-accounts', { params });

export const addFtpAccount = (data: { server_id: string; cpanel_username: string; user: string; password: string; homedir: string; quota_mb: number }) =>
  api.post<{ message: string }>('/hosting-accounts/ftp-accounts', data);

export const updateFtpAccountPassword = (data: { server_id: string; cpanel_username: string; user: string; password: string }) =>
  api.put<{ message: string }>('/hosting-accounts/ftp-accounts/password', data);

export const deleteFtpAccount = (data: { server_id: string; cpanel_username: string; user: string; destroy_files?: boolean }) =>
  api.delete<{ message: string }>('/hosting-accounts/ftp-accounts', { data });

export const importHostingAccount = (data: {
  server_id: string; cpanel_username: string; domain: string;
  client_id: string; product_service_id: string;
}) => api.post<{ data: unknown; message: string }>('/hosting-accounts/import', data);
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
    contact_email: string | null; suspend_reason: string | null; suspend_time: string | null;
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

export const changeHostingContactEmail = (accountId: string, email: string) =>
  api.post<{ message: string }>(`/hosting-accounts/${accountId}/contact-email`, { email });

export const clearBandwidthSuspension = (accountId: string, unlimited: boolean, limitMb?: number) =>
  api.post<{ message: string }>(`/hosting-accounts/${accountId}/clear-bandwidth-suspension`, { unlimited, limit_mb: limitMb });

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
