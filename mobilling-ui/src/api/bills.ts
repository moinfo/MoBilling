import api from './axios';

export interface Bill {
  id: string;
  statutory_id: string | null;
  name: string;
  category: string;
  bill_category_id: string | null;
  bill_category: { id: string; name: string; parent_name: string | null } | null;
  issue_date: string | null;
  amount: string;
  cycle: string;
  due_date: string;
  remind_days_before: number;
  is_active: boolean;
  paid_at: string | null;
  notes: string | null;
  is_overdue: boolean;
  payments?: PaymentOut[];
  created_at: string;
}

export interface PaymentOut {
  id: string;
  bill_id: string;
  amount: string;
  payment_date: string;
  payment_method: string;
  control_number: string | null;
  reference: string | null;
  notes: string | null;
  receipt_url: string | null;
  bill?: Bill;
  created_at: string;
}

export interface BillFormData {
  name: string;
  category?: string;
  bill_category_id?: string | null;
  issue_date?: string | null;
  amount: number;
  cycle: string;
  due_date: string;
  remind_days_before: number;
  is_active: boolean;
  notes: string;
}

export const getBills = (params?: { search?: string; page?: number; active_only?: boolean }) =>
  api.get('/bills', { params });

export const getBill = (id: string) =>
  api.get<{ data: Bill }>(`/bills/${id}`);

export const createBill = (data: BillFormData) =>
  api.post('/bills', data);

export const updateBill = (id: string, data: BillFormData) =>
  api.put(`/bills/${id}`, data);

export const deleteBill = (id: string) =>
  api.delete(`/bills/${id}`);

export const getPaymentsOut = (params?: { bill_id?: string; page?: number }) =>
  api.get('/payments-out', { params });

export const updatePaymentOut = (id: string, data: {
  amount?: number;
  payment_date?: string;
  payment_method?: string;
  control_number?: string | null;
  reference?: string | null;
  notes?: string | null;
}) => api.put(`/payments-out/${id}`, data);

export const deletePaymentOut = (id: string) =>
  api.delete(`/payments-out/${id}`);

export const createPaymentOut = (data: {
  bill_id: string;
  amount: number;
  payment_date: string;
  payment_method: string;
  control_number?: string;
  reference?: string;
  notes?: string;
  receipt?: File | null;
}) => {
  const formData = new FormData();
  formData.append('bill_id', data.bill_id);
  formData.append('amount', String(data.amount));
  formData.append('payment_date', data.payment_date);
  formData.append('payment_method', data.payment_method);
  if (data.control_number) formData.append('control_number', data.control_number);
  if (data.reference) formData.append('reference', data.reference);
  if (data.notes) formData.append('notes', data.notes);
  if (data.receipt) formData.append('receipt', data.receipt);
  return api.post('/payments-out', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
};
