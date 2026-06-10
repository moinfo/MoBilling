import api from './axios';

export interface SystemProperty {
  id: string;
  name: string;
  is_active: boolean;
  created_at: string;
}

export interface SystemPropertyPayload {
  name: string;
  is_active?: boolean;
}

export const getSystemProperties = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/system-properties', { params });

export const createSystemProperty = (data: SystemPropertyPayload) =>
  api.post('/system-properties', data);

export const updateSystemProperty = (id: string, data: SystemPropertyPayload) =>
  api.put(`/system-properties/${id}`, data);

export const deleteSystemProperty = (id: string) =>
  api.delete(`/system-properties/${id}`);
