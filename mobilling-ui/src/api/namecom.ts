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
