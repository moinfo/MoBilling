import api from './axios';

export interface Bill {
  id: string;
  name: string;
  category: string;
  amount: string;
  cycle: string;
  due_date: string;
  remind_days_before: number;
  is_active: boolean;
  notes: string | null;
  next_due_date: string;
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
  reference: string | null;
  notes: string | null;
  bill?: Bill;
  created_at: string;
}

export interface BillFormData {
  name: string;
  category: string;
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

export const createPaymentOut = (data: {
  bill_id: string;
  amount: number;
  payment_date: string;
  payment_method: string;
  reference?: string;
  notes?: string;
}) => api.post('/payments-out', data);
