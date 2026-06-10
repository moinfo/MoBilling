import api from './axios';

export interface System {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string;
}

export interface SystemPayload {
  name: string;
  is_active?: boolean;
}

export const getSystems = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/systems', { params });

export const createSystem = (data: SystemPayload) =>
  api.post('/systems', data);

export const updateSystem = (id: string, data: SystemPayload) =>
  api.put(`/systems/${id}`, data);

export const deleteSystem = (id: string) =>
  api.delete(`/systems/${id}`);
