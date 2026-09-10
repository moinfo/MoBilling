import api from './axios';

export type WifiDurationUnit = 'hours' | 'days' | 'weeks';

export interface WifiPlan {
  id: string;
  mikrotik_router_id: string;
  router?: { id: string; name: string };
  name: string;
  duration_value: number | null;
  duration_unit: WifiDurationUnit | null;
  data_cap_mb: number | null;
  price: string;
  hotspot_profile: string | null;
  is_active: boolean;
  created_at: string;
}

export interface WifiPlanPayload {
  mikrotik_router_id: string;
  name: string;
  duration_value?: number;
  duration_unit?: WifiDurationUnit;
  data_cap_mb?: number;
  price: number;
  hotspot_profile?: string | null;
  is_active?: boolean;
}

export const getWifiPlans = (params?: { mikrotik_router_id?: string; page?: number; per_page?: number }) =>
  api.get('/wifi-plans', { params });

export const createWifiPlan = (data: WifiPlanPayload) =>
  api.post('/wifi-plans', data);

export const updateWifiPlan = (id: string, data: WifiPlanPayload) =>
  api.put(`/wifi-plans/${id}`, data);

export const deleteWifiPlan = (id: string) =>
  api.delete(`/wifi-plans/${id}`);
