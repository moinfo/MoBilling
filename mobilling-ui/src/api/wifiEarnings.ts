import api from './axios';

export interface WifiEarningsSummary {
  owed: number;
  unsettled_count: number;
  total_settled: number;
}

export interface WifiEarningRow {
  id: string;
  router: { id: string; name: string } | null;
  plan: { id: string; name: string } | null;
  customer_phone: string;
  amount: string;
  commission_amount: string | null;
  net_amount: string | null;
  completed_at: string | null;
  settled_at: string | null;
  settlement_method: string | null;
  settlement_reference: string | null;
}

export const getWifiEarningsSummary = () =>
  api.get<{ data: WifiEarningsSummary }>('/wifi-earnings/summary');

export const getWifiEarnings = (params?: { settled?: boolean; page?: number; per_page?: number }) =>
  api.get('/wifi-earnings', { params });

export const requestWifiPayout = () =>
  api.post<{ message: string }>('/wifi-earnings/request-payout');
