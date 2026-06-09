import api from './axios';

export interface SystemRecord {
  id: string;
  system_id: string;
  system?: { id: string; name: string };
  system_property_id: string;
  system_property?: { id: string; name: string };
  record_date: string;
  amount: string;
  notes: string | null;
  created_by?: { id: string; name: string } | null;
  created_at: string;
}

export interface SystemRecordPayload {
  system_id: string;
  system_property_id: string;
  record_date: string;
  amount: number;
  notes?: string;
}

export const getSystemRecords = (params?: {
  search?: string;
  page?: number;
  per_page?: number;
  system_id?: string;
  system_property_id?: string;
  date_from?: string;
  date_to?: string;
}) => api.get('/system-records', { params });

export const createSystemRecord = (data: SystemRecordPayload) =>
  api.post('/system-records', data);

export const updateSystemRecord = (id: string, data: SystemRecordPayload) =>
  api.put(`/system-records/${id}`, data);

export const deleteSystemRecord = (id: string) =>
  api.delete(`/system-records/${id}`);
