import api from './axios';

export interface SystemRecord {
  id: string;
  system_id: string;
  system?: { id: string; name: string };
  system_property_id: string;
  system_property?: { id: string; name: string };
  bank_account_id: string | null;
  bank_account?: { id: string; bank_name: string; account_number: string };
  record_date: string;
  amount: string;
  notes: string | null;
  receipt_attachment_url: string | null;
  created_by?: { id: string; name: string } | null;
  created_at: string;
}

export interface SystemRecordPayload {
  system_id: string;
  system_property_id: string;
  bank_account_id?: string | null;
  record_date: string;
  amount: number;
  notes?: string;
  receipt?: File | null;
}

const buildFormData = (data: SystemRecordPayload, includeMethodOverride = false) => {
  const fd = new FormData();
  if (includeMethodOverride) fd.append('_method', 'PUT');
  fd.append('system_id', data.system_id);
  fd.append('system_property_id', data.system_property_id);
  if (data.bank_account_id) fd.append('bank_account_id', data.bank_account_id);
  fd.append('record_date', data.record_date);
  fd.append('amount', String(data.amount));
  if (data.notes) fd.append('notes', data.notes);
  if (data.receipt) fd.append('receipt', data.receipt);
  return fd;
};

export const getSystemRecords = (params?: {
  search?: string;
  page?: number;
  per_page?: number;
  system_id?: string;
  system_property_id?: string;
  bank_account_id?: string;
  date_from?: string;
  date_to?: string;
}) => api.get('/system-records', { params });

export const createSystemRecord = (data: SystemRecordPayload) =>
  api.post('/system-records', buildFormData(data), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// Laravel ignores multipart on PUT, so we POST with _method=PUT spoofing.
export const updateSystemRecord = (id: string, data: SystemRecordPayload) =>
  api.post(`/system-records/${id}`, buildFormData(data, true), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export const deleteSystemRecord = (id: string) =>
  api.delete(`/system-records/${id}`);
