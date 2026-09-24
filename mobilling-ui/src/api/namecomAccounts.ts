import api from './axios';

/** Several Name.com credential sets per tenant. Tokens are write-only and never returned. */
export interface NameComAccountRow {
  id: string;
  label: string;
  is_default: boolean;
  username: string;
  token_hint: string | null; // masked
  is_sandbox: boolean;
  status: 'active' | 'invalid';
  status_message: string | null;
  last_verified_at: string | null;
  linked_domains: number;
}
export interface NameComAccountOption { id: string; label: string; username: string; is_default: boolean; status: string }

export interface NameComImportRow {
  name: string;
  expires_at: string | null;
  locked: boolean | null;
  nameservers: string[];
  account_id: string;
  account_label: string;
  domain_id: string | null;
  client_id: string | null;
  client_name: string | null;
  linked: boolean;
  linked_account_label: string | null;
  in_mobilling: boolean;
  fred_managed: boolean;
}
export interface NameComImportResult { data: NameComImportRow[]; errors: { account_id: string; account_label: string; message: string }[] }

export const listNameComAccounts = () => api.get<{ data: NameComAccountRow[] }>('/namecom/accounts');
export const listNameComAccountOptions = () => api.get<{ data: NameComAccountOption[] }>('/namecom/account-options');
export const createNameComAccount = (b: { label: string; username: string; token: string; is_sandbox: boolean; is_default?: boolean }) =>
  api.post<{ data: NameComAccountRow; message: string }>('/namecom/accounts', b);
export const updateNameComAccount = (id: string, b: Partial<{ label: string; username: string; token: string; is_sandbox: boolean; is_default: boolean }>) =>
  api.put<{ data: NameComAccountRow; message: string }>(`/namecom/accounts/${id}`, b);
export const deleteNameComAccountById = (id: string, confirm_linked = false) =>
  api.delete<{ message: string }>(`/namecom/accounts/${id}`, { params: confirm_linked ? { confirm_linked: 1 } : undefined, data: confirm_linked ? { confirm_linked: true } : undefined });
export const testNameComAccountById = (id: string) => api.post<{ data: NameComAccountRow; message: string }>(`/namecom/accounts/${id}/test`);

export const importNameComDomains = (account_id: string) => api.get<NameComImportResult>('/namecom/domains', { params: { account_id } });
export const linkNameComDomainTo = (domain_name: string, client_id: string, account_id: string) =>
  api.post<{ message: string }>('/namecom/link', { domain_name, client_id, account_id });

export interface BulkLinkResult { name: string; status: 'ready' | 'linked' | 'new' | 'skipped' | 'failed'; message?: string; client_name?: string }
export const bulkLinkMatched = (items: { domain_name: string; account_id: string }[], confirm: boolean) =>
  api.post<{ data: BulkLinkResult[]; message: string }>('/namecom/link-matched', { items, confirm });

// ── registration: staff chooses which Name.com account is charged ──
import type { NameComRegistrationPreview } from './namecom';
export type NameComRegistrationPreviewX = NameComRegistrationPreview & {
  account: { id: string; label: string; username: string; is_sandbox: boolean } | null;
  accounts: { id: string; label: string; username: string; is_default: boolean; status: string }[];
};
export const previewNameComRegistrationWith = (domainId: string, account_id?: string) =>
  api.get<{ data: NameComRegistrationPreviewX }>(`/namecom/registration/${domainId}`, { params: account_id ? { account_id } : undefined });
export const registerAtNameComWith = (domainId: string, usd_cost: number, account_id?: string) =>
  api.post<{ message: string }>(`/namecom/registration/${domainId}`, { confirm: true, usd_cost, account_id });
