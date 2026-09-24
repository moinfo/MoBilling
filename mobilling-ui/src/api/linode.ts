import api from './axios';

export interface LinodeAccount {
  id: string;
  label: string;
  token_hint: string | null; // masked, e.g. "••••1234" - the token itself is never returned
  soa_email: string | null;
  status: 'active' | 'invalid';
  status_message: string | null;
  last_verified_at: string | null;
  last_synced_at: string | null;
}

export interface LinodeResource {
  id: string;
  linode_account_id: string;
  account_label: string | null;
  type: 'instance' | 'domain';
  remote_id: string;
  label: string;
  status: string | null;
  region: string | null;
  plan: string | null;
  ipv4: string[];
  ipv6: string | null;
  tags: string[];
  meta: Record<string, unknown> | null;
  client_id: string | null;
  client_name: string | null;
  client_subscription_id: string | null;
  domain_id: string | null;
  synced_at: string | null;
  account_last_synced_at: string | null;
  our_domain?: { id: string; status: string; can_set_nameservers: boolean } | null;
  // domains only
  dns?: LinodeDnsInfo;
  suggested_client?: { id: string; name: string; domains?: number } | null;
  // servers only
  subscription?: LinodeServerBilling | null;
  domain_count?: number;
  domains?: { id: string; label: string }[];
}

export interface LinodeServerBilling {
  id: string;
  state: 'active' | 'pending' | 'suspended' | 'expired';
  status: string;
  label: string | null;
  product_name: string | null;
  billing_cycle: string | null;
  amount: number;
  start_date: string | null;
  expire_date: string | null;
  next_invoice_date: string | null;
  latest_invoice: { id: string; number: string; status: string; due_date: string | null; total: string } | null;
}

export interface LinodeBillingProduct { id: string; name: string; price: string; tax_percent: string; billing_cycle: string; category: string | null }
export interface LinodeClientSub { id: string; label: string | null; product_name: string | null; status: string; expire_date: string | null; billing_cycle: string | null }

export type DnsStatus = 'server' | 'external' | 'no_a_record' | 'unknown';
export interface LinodeDnsInfo {
  status: DnsStatus;
  apex_ips: string[];
  www_ips: string[];
  external_ips: string[];
  servers: { id: string; label: string; apex: boolean; www: boolean }[];
  fetched_at: string | null;
  error: string | null;
}

export interface DnsRefreshBatch {
  processed: number;
  ok: number;
  failed: { domain: string; error: string }[];
  total: number;
  next_offset: number | null;
}

export interface LinodeRecord {
  id: number;
  type: string;
  name: string;
  target: string;
  ttl_sec: number;
  priority?: number | null;
  weight?: number | null;
  port?: number | null;
  tag?: string | null;
  service?: string | null;
  protocol?: string | null;
  locked?: boolean;
}

export interface LinodeRecordPayload {
  type: string;
  name: string;
  target: string;
  ttl_sec?: number;
  priority?: number;
  weight?: number;
  port?: number;
  service?: string;
  protocol?: string;
  tag?: string;
}

export interface AddDomainResult extends LinodeResource {
  records_created: number;
  nameservers: string[];
  note: string;
  can_set_nameservers: boolean;
}

export const DOMAIN_TTLS = [0, 30, 120, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200];
export const RECORD_TTLS = [0, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200];
/** Values Linode accepts for SOA ttl/refresh/retry/expire (0 = Default). */
export const SOA_TTLS = [0, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200];
export const RECORD_TYPES = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'SRV', 'CAA'];
export const LINODE_NAMESERVERS = ['ns1.linode.com', 'ns2.linode.com', 'ns3.linode.com', 'ns4.linode.com', 'ns5.linode.com'];

export const getLinodeAccounts = () => api.get<{ data: LinodeAccount[] }>('/linode/accounts');
export const createLinodeAccount = (d: { label: string; token: string; soa_email?: string }) =>
  api.post<{ data: LinodeAccount; message: string }>('/linode/accounts', d);
export const updateLinodeAccount = (id: string, d: { label?: string; token?: string; soa_email?: string | null }) =>
  api.put<{ data: LinodeAccount; message: string }>(`/linode/accounts/${id}`, d);
export const deleteLinodeAccount = (id: string) => api.delete<{ message: string }>(`/linode/accounts/${id}`);
export const verifyLinodeAccount = (id: string) => api.post<{ data: LinodeAccount; message: string }>(`/linode/accounts/${id}/verify`);
export const syncLinodeAccount = (id: string) => api.post<{ data: LinodeAccount; message: string }>(`/linode/accounts/${id}/sync`);

export const getLinodeServers = () => api.get<{ data: LinodeResource[] }>('/linode/servers');
export const getLinodeDomains = () => api.get<{ data: LinodeResource[]; dns_last_refreshed: string | null }>('/linode/domains');
export const refreshLinodeDns = (accountId: string, offset: number, limit = 10) =>
  api.post<DnsRefreshBatch>(`/linode/accounts/${accountId}/refresh-dns`, { offset, limit });
export const autoMapLinodeClients = (ids?: string[]) =>
  api.post<{ mapped: { id: string; domain: string; client: string }[]; message: string }>('/linode/domains/auto-map', { confirm: true, ids });
export const addLinodeDomain = (d: { account_id: string; domain: string; soa_email?: string; ttl?: number; server_id?: string }) =>
  api.post<{ data: AddDomainResult; message: string }>('/linode/domains', d);
export const checkLinodeNameservers = (id: string) =>
  api.post<{ data: { pointing_to_linode: boolean; nameservers: string[]; expected: string[] } }>(`/linode/domains/${id}/check-nameservers`);
export const setLinodeNameservers = (id: string) =>
  api.post<{ message: string }>(`/linode/domains/${id}/set-nameservers`, { confirm: true });

export const getLinodeRecords = (id: string) => api.get<{ data: LinodeRecord[] }>(`/linode/domains/${id}/records`);
export const addLinodeRecord = (id: string, d: LinodeRecordPayload) => api.post(`/linode/domains/${id}/records`, d);
export const updateLinodeRecord = (id: string, rid: number, d: LinodeRecordPayload) => api.put(`/linode/domains/${id}/records/${rid}`, d);

export const mapLinodeResource = (id: string, d: { client_id: string | null; client_subscription_id?: string | null }) =>
  api.patch<{ data: LinodeResource; message: string }>(`/linode/resources/${id}/map`, d);

export const getLinodeBillingProducts = () => api.get<{ data: LinodeBillingProduct[] }>('/linode/billing-products');
export const getLinodeClientSubscriptions = (clientId: string) => api.get<{ data: LinodeClientSub[] }>(`/linode/clients/${clientId}/subscriptions`);
export const billLinodeServer = (id: string, d: {
  client_id: string; product_service_id: string; amount: number; billing_cycle?: string; start_date: string;
  expire_date?: string | null; label?: string; mode: 'paid_outside' | 'invoice_now';
}) => api.post<{ data: { subscription_id: string; document_id: string | null; document_number: string | null }; message: string }>(`/linode/resources/${id}/bill`, d);
export const linkLinodeSubscription = (id: string, client_subscription_id: string) =>
  api.post<{ message: string }>(`/linode/resources/${id}/link-subscription`, { client_subscription_id });
export const unlinkLinodeSubscription = (id: string) => api.post<{ message: string }>(`/linode/resources/${id}/unlink-subscription`);

export type PowerAction = 'reboot' | 'shutdown' | 'boot';
export const linodePower = (id: string, d: { action: PowerAction; confirm_label?: string; confirm?: boolean }) =>
  api.post<{ message: string; data: LinodeResource }>(`/linode/servers/${id}/power`, d);
export const getLinodeServerStatus = (id: string) => api.get<{ data: { id: string; status: string } }>(`/linode/servers/${id}/status`);

export interface LinodeCostsRow {
  account_id: string; label: string; error: string | null;
  balance: number | null; balance_uninvoiced: number | null;
  invoices: { id: number; label: string | null; date: string; total: number }[];
  payments: { id: number; date: string; usd: number }[];
}
export const getLinodeCosts = () => api.get<{ data: LinodeCostsRow[] }>('/linode/costs').then((r) => r.data.data);

export interface LinodeDomainRequestRow {
  id: string; domain: string; status: 'pending' | 'approved' | 'rejected'; note: string | null;
  client_id: string; client_name: string | null; server_id: string; server_label: string | null; server_ip: string | null;
  decided_at: string | null; created_at: string;
}
export const getLinodeDomainRequests = (status: 'pending' | 'approved' | 'rejected' = 'pending') =>
  api.get<{ data: LinodeDomainRequestRow[] }>('/linode/domain-requests', { params: { status } });
export const approveLinodeDomainRequest = (id: string) => api.post<{ message: string }>(`/linode/domain-requests/${id}/approve`);
export const rejectLinodeDomainRequest = (id: string, note?: string) => api.post<{ message: string }>(`/linode/domain-requests/${id}/reject`, { note });
