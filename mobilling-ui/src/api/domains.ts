import api from './axios';

export interface DomainRecord {
  id: string;
  name: string;
  status: 'pending' | 'active' | 'expired' | 'transferred_out' | 'cancelled' | 'failed';
  client: { id: string; name: string } | null;
  registrar_account: { id: string; name: string } | null;
  registered_at: string | null;
  expires_at: string | null;
  auto_renew: boolean;
  meta: Record<string, any> | null;
  created_at: string;
}

export interface DomainCheckResult {
  name: string;
  available: boolean;
  reason: string | null;
  pricing: {
    tld: string;
    register_price: number;
    renew_price: number;
    transfer_price: number;
    years_min: number;
    years_max: number;
  } | null;
}

export interface RegistrarAccountRow {
  id: string;
  name: string;
  driver: string;
  registrar_id: string | null;
  endpoint_url: string | null;
  has_token: boolean;
  is_active: boolean;
  is_sandbox: boolean;
  is_platform: boolean;
  domains_count: number;
}

export interface DomainTldRow {
  id: string;
  tld: string;
  register_price: number;
  renew_price: number;
  transfer_price: number;
  years_min: number;
  years_max: number;
  is_active: boolean;
  is_platform: boolean;
}

export interface DomainLogRow {
  id: string;
  action: string;
  status: 'success' | 'failed';
  error: string | null;
  created_at: string;
}

export const DOMAIN_STATUS_COLORS: Record<DomainRecord['status'], string> = {
  pending: 'blue',
  active: 'green',
  expired: 'red',
  transferred_out: 'gray',
  cancelled: 'gray',
  failed: 'red',
};

export const checkDomain = (name: string) =>
  api.get<DomainCheckResult>('/domains/check', { params: { name } });

export const getDomains = (params?: Record<string, string>) =>
  api.get('/domains', { params });

export const getDomain = (id: string) =>
  api.get<{ data: DomainRecord & { subscription?: { id: string; label: string | null; expire_date: string | null } | null } }>(`/domains/${id}`);

// FredHttpDriver logs raw API paths as the action — translate to something readable.
export const describeDomainAction = (action: string): string => {
  if (action === 'auth_info_revealed') return 'Transfer code viewed';
  if (action === 'nameservers_changed') return 'Nameservers changed';
  if (action.includes('/nssets/') && action.includes('/update/')) return 'Nameserver set updated';
  if (action.includes('/nssets/create')) return 'Nameserver set created';
  if (action.includes('/nssets/')) return 'Nameserver lookup';
  if (action.includes('/info/')) return 'Registry sync check';
  if (action.includes('/renew/')) return 'Registry renewal';
  if (action.includes('/register/')) return 'Domain registration';
  if (action.includes('/transfer/')) return 'Transfer request';
  if (action.includes('/check/')) return 'Availability check';
  if (action.includes('/update/')) return 'Registry update';
  return action.replace(/_/g, ' ');
};

export interface DomainStats {
  total: number;
  active: number;
  pending: number;
  expired: number;
  cancelled: number;
  failed: number;
  expiring_soon: number;
  auto_renew: number;
  our_registrar: string | null;
  ours: number;
  external: number;
}

export interface RegistrarCredit {
  ok: boolean;
  zones: { zone: string; credit: number }[];
  total: number;
  funded_count: number;
  low: string[];
  pending_transfers: CreditTransfer[];
  checked_at: string | null;
  error: string | null;
}
export interface CreditTransfer {
  id: string; from_zone: string; to_zone: string; amount: number;
  status?: string; reference?: string | null; notes?: string | null;
  requested_by: string | null; created_at?: string; completed_at?: string | null;
}
export interface TransferEmail { to: string; subject: string; body: string }

export const getCreditTransfers = () =>
  api.get<{ data: CreditTransfer[] }>('/registrar-credit-transfers');
export const createCreditTransfer = (data: { from_zone: string; to_zone: string; amount: number; notes?: string }) =>
  api.post<{ data: CreditTransfer; email: TransferEmail; message: string }>('/registrar-credit-transfers', data);
export const completeCreditTransfer = (id: string, reference?: string) =>
  api.post<{ message: string }>(`/registrar-credit-transfers/${id}/complete`, { reference });
export const cancelCreditTransfer = (id: string) =>
  api.post<{ message: string }>(`/registrar-credit-transfers/${id}/cancel`);
export const getRegistrarCredit = () =>
  api.get<{ data: RegistrarCredit }>('/domains/registrar-credit');

export const getDomainStats = () =>
  api.get<{ data: DomainStats }>('/domains/stats');

export const getDomainLogs = (id: string) =>
  api.get<{ data: DomainLogRow[] }>(`/domains/${id}/logs`);

export const orderDomain = (data: {
  name: string; client_id: string; years: number;
  action: 'register' | 'transfer'; auth_info?: string;
}) => api.post('/domains/order', data);

export interface DomainNameservers {
  nsset: string | null;
  nameservers: string[];
  tech?: string[];
  shared_with: number;
}

export const getDomainNameservers = (id: string) =>
  api.get<{ data: DomainNameservers }>(`/domains/${id}/nameservers`);

export const updateDomainNameservers = (id: string, nameservers: string[]) =>
  api.put<{ data: { nsset: string; nameservers: string[] }; message: string }>(`/domains/${id}/nameservers`, { nameservers });

export const setDomainAutoRenew = (id: string, enabled: boolean) =>
  api.put<{ data: { auto_renew: boolean }; message: string }>(`/domains/${id}/auto-renew`, { enabled });

export const renewDomain = (id: string, years: number) =>
  api.post(`/domains/${id}/renew`, { years });

export const getDomainAuthInfo = (id: string) =>
  api.get<{ auth_info: string | null }>(`/domains/${id}/auth-info`);

// Settings
export const getRegistrarAccounts = () =>
  api.get<{ data: RegistrarAccountRow[] }>('/registrar-accounts');

export const testRegistrarAccount = (id: string) =>
  api.post<{ ok: boolean; credits: { zone: string; credit: string }[] }>(`/registrar-accounts/${id}/test`);

export interface RegistrarAccountInput {
  name: string;
  endpoint_url: string;
  registrar_id?: string | null;
  service_token?: string;
  is_active?: boolean;
}
export const createRegistrarAccount = (data: RegistrarAccountInput) =>
  api.post('/registrar-accounts', data);

export const updateRegistrarAccount = (id: string, data: Partial<RegistrarAccountInput>) =>
  api.put(`/registrar-accounts/${id}`, data);

export const deleteRegistrarAccount = (id: string) =>
  api.delete(`/registrar-accounts/${id}`);

export const getDomainTlds = () =>
  api.get<{ data: DomainTldRow[] }>('/domain-tlds');

export const createDomainTld = (data: Partial<DomainTldRow>) =>
  api.post('/domain-tlds', data);

export const updateDomainTld = (id: string, data: Partial<DomainTldRow>) =>
  api.put(`/domain-tlds/${id}`, data);

export const deleteDomainTld = (id: string) =>
  api.delete(`/domain-tlds/${id}`);
