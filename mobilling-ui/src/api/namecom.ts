import api from './axios';

export interface NameComAccount {
  id: string;
  username: string;
  token_hint: string | null; // masked - the token itself is never returned
  is_sandbox: boolean;
  status: 'active' | 'invalid';
  status_message: string | null;
  last_verified_at: string | null;
}

export interface NameComDomainRow {
  name: string;
  expires_at: string | null;
  locked: boolean | null;
  nameservers: string[];
  domain_id: string | null;
  client_id: string | null;
  client_name: string | null;
  linked: boolean;
  in_mobilling: boolean;
  fred_managed: boolean;
}

export const NAMECOM_LINODE_NAMESERVERS = ['ns1.linode.com', 'ns2.linode.com', 'ns3.linode.com', 'ns4.linode.com', 'ns5.linode.com'];

export const getNameComAccount = () => api.get<{ data: NameComAccount | null }>('/namecom/account');
export const saveNameComAccount = (b: { username: string; token?: string; is_sandbox: boolean }) =>
  api.put<{ data: NameComAccount; message: string }>('/namecom/account', b);
export const deleteNameComAccount = () => api.delete<{ message: string }>('/namecom/account');
export const testNameComAccount = () => api.post<{ data: NameComAccount; message: string }>('/namecom/account/test');
export const listNameComDomains = () => api.get<{ data: NameComDomainRow[] }>('/namecom/domains');
export const linkNameComDomain = (domain_name: string, client_id: string) =>
  api.post<{ message: string }>('/namecom/link', { domain_name, client_id });

// ── selling Name.com TLDs (staff only; USD costs never reach the client portal) ──
export interface NameComSettingsData { usd_rate: number; fixed_markup: number; auto_register: boolean; auto_cap_usd: number; auto_daily_limit: number }
export interface NameComTldRow {
  tld: string;
  usd_register: number | null; usd_renew: number | null; usd_transfer: number | null;
  register_price: number; renew_price: number; transfer_price: number;
  is_active: boolean; is_popular: boolean; sort_order: number; price_overridden: boolean; usd_changed: boolean;
  usd_prev: { register: number | null; renew: number | null; transfer: number | null; at?: string } | null;
  synced_at: string | null;
}
export interface NameComTldList {
  data: NameComTldRow[];
  meta: { current_page: number; last_page: number; total: number };
  counts: { total: number; enabled: number; changed: number; overridden: number };
  settings: NameComSettingsData;
}
export const getNameComSettings = () => api.get<{ data: NameComSettingsData }>('/namecom/settings');
export const saveNameComSettings = (b: NameComSettingsData) => api.put<{ data: NameComSettingsData; message: string }>('/namecom/settings', b);
export const listNameComTlds = (p: { search?: string; filter?: string; page?: number }) => api.get<NameComTldList>('/namecom/tlds', { params: p });
export const syncNameComTlds = () => api.post<{ message: string }>('/namecom/tlds/sync');
export const recomputeNameComTlds = () => api.post<{ message: string }>('/namecom/tlds/recompute');
export const ackNameComTlds = (tlds?: string[]) => api.post<{ message: string }>('/namecom/tlds/ack', tlds ? { tlds } : {});
export const updateNameComTld = (tld: string, b: Partial<{ register_price: number; renew_price: number; transfer_price: number | null; is_active: boolean; is_popular: boolean; sort_order: number; reset_override: boolean }>) =>
  api.put<{ data: NameComTldRow; message: string }>(`/namecom/tlds/${tld}`, b);

export interface NameComRegistrationPreview {
  domain: string; client: { id: string; name: string } | null; years: number;
  contact: Record<string, string>; missing: string[];
  usd_cost: number | null; usd_expected: number | null; price_changed: boolean; available: boolean | null;
  invoice_total: number | null; invoice_number: string | null;
  request: Record<string, any>; blockers: string[]; notes: string[]; can_register: boolean; uncertain: boolean;
}
export const previewNameComRegistration = (domainId: string) => api.get<{ data: NameComRegistrationPreview }>(`/namecom/registration/${domainId}`);
export const registerAtNameCom = (domainId: string, usd_cost: number) =>
  api.post<{ message: string }>(`/namecom/registration/${domainId}`, { confirm: true, usd_cost });
