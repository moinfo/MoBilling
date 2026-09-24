import api from './axios';
import type { DnsPayload, DnsRec } from '../components/DnsSections';

/** Client-portal "Domain Manager" endpoints (neutral paths; nothing here names the underlying provider). */
const base = (id: string) => `/portal/domains/${id}`;

export interface DmDns { records: DnsRec[]; in_use: boolean; max_records: number; ttls: number[]; is_admin: boolean }
export interface DmContact {
  first_name: string; last_name: string; company: string; address1: string; address2: string; city: string;
  state: string; zip: string; country: string; email: string; phone: string; fax: string; verified: boolean | null;
}
export type DmRole = 'registrant' | 'admin' | 'tech' | 'billing';
export interface DmContacts { contacts: Record<DmRole, DmContact>; transfer_lock_until: string | null; is_admin: boolean }
export interface DmUrlForward { id: number; host: string; target: string; type: 'permanent' | 'temporary' | 'masked'; title: string | null }
export interface DmEmailForward { box: string; address: string; to: string }
export interface DmForwarding { url: DmUrlForward[]; email: DmEmailForward[]; max: number; is_admin: boolean }
export interface DmHost { hostname: string; ips: string[] }
export interface DmHosts { hosts: DmHost[]; max: number; is_admin: boolean }

export const dmGetDns = (id: string) => api.get<{ data: DmDns }>(`${base(id)}/dns`);
export const dmAddRecord = (id: string, p: DnsPayload) => api.post(`${base(id)}/dns/records`, p);
export const dmEditRecord = (id: string, rid: number, p: DnsPayload) => api.put(`${base(id)}/dns/records/${rid}`, p);
export const dmDeleteRecord = (id: string, rid: number) => api.delete(`${base(id)}/dns/records/${rid}`);
export const dmUseOurDns = (id: string) => api.post(`${base(id)}/dns/use-default-servers`, { confirm: true });

export const dmGetContacts = (id: string) => api.get<{ data: DmContacts }>(`${base(id)}/contacts`);
export const dmSaveContacts = (id: string, contacts: Partial<Record<DmRole, Omit<DmContact, 'verified'>>>) =>
  api.put<{ data: { changed: string[] }; message: string }>(`${base(id)}/contacts`, { confirm: true, contacts });

export const dmGetForwarding = (id: string) => api.get<{ data: DmForwarding }>(`${base(id)}/forwarding`);
export const dmAddUrl = (id: string, p: { host: string; target: string; type: string; title?: string }) => api.post(`${base(id)}/forwarding/url`, p);
export const dmEditUrl = (id: string, fid: number, p: { host?: string; target?: string; type?: string; title?: string }) => api.put(`${base(id)}/forwarding/url/${fid}`, p);
export const dmDeleteUrl = (id: string, fid: number) => api.delete(`${base(id)}/forwarding/url/${fid}`);
export const dmAddEmail = (id: string, p: { box: string; to: string }) => api.post(`${base(id)}/forwarding/email`, p);
export const dmEditEmail = (id: string, box: string, to: string) => api.put(`${base(id)}/forwarding/email/${encodeURIComponent(box)}`, { to });
export const dmDeleteEmail = (id: string, box: string) => api.delete(`${base(id)}/forwarding/email/${encodeURIComponent(box)}`);

export const dmGetHosts = (id: string) => api.get<{ data: DmHosts }>(`${base(id)}/hosts`);
export const dmAddHost = (id: string, host: string, ips: string[]) => api.post(`${base(id)}/hosts`, { host, ips });
export const dmEditHost = (id: string, hostname: string, ips: string[]) => api.put(`${base(id)}/hosts/${encodeURIComponent(hostname)}`, { ips });
