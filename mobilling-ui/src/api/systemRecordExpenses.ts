import api from './axios';

export interface SystemRecordExpense {
  id: string;
  system_record_id: string;
  system_record?: {
    id: string;
    amount: string;
    record_date: string;
    transaction_reference: string | null;
    system: { id: string; name: string } | null;
    system_property: { id: string; name: string } | null;
  };
  amount: string;
  expense_date: string;
  description: string;
  attachment_url: string | null;
  created_by?: { id: string; name: string } | null;
  created_at: string;
}

export interface SystemRecordExpensePayload {
  system_record_id: string;
  amount: number;
  expense_date: string;
  description: string;
  attachment?: File | null;
}

const buildFormData = (data: SystemRecordExpensePayload, includeMethodOverride = false) => {
  const fd = new FormData();
  if (includeMethodOverride) fd.append('_method', 'PUT');
  fd.append('system_record_id', data.system_record_id);
  fd.append('amount', String(data.amount));
  fd.append('expense_date', data.expense_date);
  fd.append('description', data.description);
  if (data.attachment) fd.append('attachment', data.attachment);
  return fd;
};

export const getSystemRecordExpenses = (params?: {
  search?: string;
  page?: number;
  per_page?: number;
  system_record_id?: string;
  date_from?: string;
  date_to?: string;
}) => api.get('/system-record-expenses', { params });

export const createSystemRecordExpense = (data: SystemRecordExpensePayload) =>
  api.post('/system-record-expenses', buildFormData(data), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

// Laravel ignores multipart on PUT, so we POST with _method=PUT spoofing.
export const updateSystemRecordExpense = (id: string, data: SystemRecordExpensePayload) =>
  api.post(`/system-record-expenses/${id}`, buildFormData(data, true), {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export const deleteSystemRecordExpense = (id: string) =>
  api.delete(`/system-record-expenses/${id}`);
