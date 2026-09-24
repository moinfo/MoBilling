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
  domain_count?: number;
  domains?: { id: string; label: string }[];
}

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
export const deleteLinodeRecord = (id: string, rid: number) => api.delete(`/linode/domains/${id}/records/${rid}`);

export const mapLinodeResource = (id: string, d: { client_id: string | null; client_subscription_id?: string | null }) =>
  api.patch<{ data: LinodeResource; message: string }>(`/linode/resources/${id}/map`, d);
