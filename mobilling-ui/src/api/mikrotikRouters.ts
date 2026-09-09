import api from './axios';

export type WifiPaymentMode = 'self_managed' | 'platform_collected';

export interface MikrotikRouter {
  id: string;
  name: string;
  host: string;
  api_port: number;
  username: string;
  use_tls: boolean;
  payment_mode: WifiPaymentMode;
  is_active: boolean;
  last_tested_at: string | null;
  last_test_status: string | null;
  last_test_message: string | null;
  created_at: string;
}

export interface MikrotikRouterPayload {
  name: string;
  host: string;
  api_port?: number;
  username: string;
  password?: string;
  use_tls?: boolean;
  payment_mode?: WifiPaymentMode;
  is_active?: boolean;
}

export const getMikrotikRouters = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/mikrotik-routers', { params });

export const createMikrotikRouter = (data: MikrotikRouterPayload) =>
  api.post('/mikrotik-routers', data);

export const updateMikrotikRouter = (id: string, data: MikrotikRouterPayload) =>
  api.put(`/mikrotik-routers/${id}`, data);

export const deleteMikrotikRouter = (id: string) =>
  api.delete(`/mikrotik-routers/${id}`);

export const testMikrotikRouter = (id: string) =>
  api.post<{ data: { ok: boolean; message: string } }>(`/mikrotik-routers/${id}/test`);
