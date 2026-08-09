import api from './axios';

export interface ResellerTld {
  tld: string;
  reseller_price: number;
  years_min: number;
  years_max: number;
}

export interface ResellerStatus {
  is_reseller: boolean;
  expire_date: string | null;
  wallet_balance: number;
  tlds: ResellerTld[];
}

export const getResellerStatus = () =>
  api.get<{ data: ResellerStatus }>('/portal/reseller/status');

export const checkResellerDomain = (name: string) =>
  api.get<{ name: string; available: boolean; pricing: { reseller_price: number; years_min: number; years_max: number } | null; message?: string }>(
    '/portal/reseller/domains/check', { params: { name } }
  );

export const orderResellerDomain = (data: { name: string; years: number; action: 'register' | 'transfer'; auth_info?: string }) =>
  api.post<{ data: { document_id: string; document_number: string; total: number }; message: string }>(
    '/portal/reseller/domains/order', data
  );

export const renewResellerDomain = (domainId: string, years: number) =>
  api.post<{ data: { document_id: string; document_number: string; total: number }; message: string }>(
    `/portal/reseller/domains/${domainId}/renew`, { years }
  );
